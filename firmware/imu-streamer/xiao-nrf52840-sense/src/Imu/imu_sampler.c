/**
 ******************************************************************************
 * @file    imu_sampler.c
 * @brief   LSM6DS3TR-C FIFO to sample blocks, see imu_sampler.h.
 ******************************************************************************
 */
#include "Imu/imu_sampler.h"

#include "Imu/lsm6ds3trc.h"

#include <errno.h>
#include <stdbool.h>
#include <zephyr/kernel.h>

#define FRAME_BYTES    (IMU_AXES * sizeof(int16_t))
#define CTRL1_XL_VALUE ((uint8_t) (IMU_ODR << 4) | IMU_ACCEL_FS)
#define CTRL2_G_VALUE  ((uint8_t) (IMU_ODR << 4) | IMU_GYRO_FS)

_Static_assert(IMU_ODR >= LSM6_ODR_12_5HZ && IMU_ODR <= LSM6_ODR_1660HZ, "IMU_ODR must be 12.5 Hz .. 1.66 kHz");
_Static_assert(IMU_FRAMES_PER_BLOCK > 0U, "IMU_FRAMES_PER_BLOCK must be at least 1");
_Static_assert(sizeof(imu_payload_t) == 4U + IMU_FRAMES_PER_BLOCK * FRAME_BYTES, "payload must have no padding");
_Static_assert(__BYTE_ORDER__ == __ORDER_LITTLE_ENDIAN__, "FIFO words are copied as they arrive, LSB first");

static imu_block_t filling;   /* the block being filled; its seq is the next one to send */
static unsigned    n_filled;  /* frames in filling */
static unsigned    n_discard; /* frames still to drop after a FIFO start */

/* Empties the FIFO and starts it again. When samples were lost, drops the partial block
 * and skips one seq, so the PC sees the gap. */
static int fifo_restart(bool samples_lost)
{
    if (samples_lost)
    {
        filling.seq++;
        n_filled = 0U;
    }
    /* The first sample after switching into a FIFO mode is not valid (datasheet 5.5.1) */
    n_discard = 1U;

    const int err = lsm6_write(LSM6_REG_FIFO_CTRL5, LSM6_FIFO_MODE_BYPASS);
    return err < 0 ? err : lsm6_write(LSM6_REG_FIFO_CTRL5, (uint8_t) (IMU_ODR << 3) | LSM6_FIFO_MODE_CONTINUOUS);
}

static int fifo_read_frames(void *frames, unsigned n)
{
    const int err = lsm6_read_burst(LSM6_REG_FIFO_DATA_OUT, frames, n * FRAME_BYTES);

    if (err < 0)
    {
        /* Part of the read may have left the FIFO */
        fifo_restart(true);
    }
    return err;
}

static int software_reset(void)
{
    const int err = lsm6_write(LSM6_REG_CTRL3_C, LSM6_CTRL3_C_SW_RESET);

    for (int tries = 0; err == 0 && tries < 10; tries++)
    {
        k_usleep(100);
        const int ctrl3 = lsm6_read(LSM6_REG_CTRL3_C);
        if (ctrl3 < 0 || (ctrl3 & LSM6_CTRL3_C_SW_RESET) == 0)
        {
            return ctrl3 < 0 ? ctrl3 : 0;
        }
    }
    return err < 0 ? err : -EIO;
}

/* Writes the register and reads it back; returns 0, -EIO when it reads back different, or a negative errno */
static int write_checked(uint8_t reg, uint8_t value)
{
    const int err = lsm6_write(reg, value);
    if (err < 0)
    {
        return err;
    }

    const int read_back = lsm6_read(reg);
    return read_back < 0 ? read_back : (read_back == value ? 0 : -EIO);
}

int imu_sampler_start(void)
{
    /* CTRL3_C first: BDU and IF_INC hold for every read after it */
    static const uint8_t setup[][2] = {
        {LSM6_REG_CTRL3_C, LSM6_CTRL3_C_BDU | LSM6_CTRL3_C_IF_INC},
        {LSM6_REG_FIFO_CTRL3, LSM6_FIFO_CTRL3_NO_DECIMATION},
        {LSM6_REG_CTRL1_XL, CTRL1_XL_VALUE},
        {LSM6_REG_CTRL2_G, CTRL2_G_VALUE},
    };

    int err = lsm6_begin();
    if (err < 0)
    {
        return err;
    }

    const int who_am_i = lsm6_read(LSM6_REG_WHO_AM_I);
    if (who_am_i < 0)
    {
        return who_am_i;
    }
    if (who_am_i != LSM6_WHO_AM_I_VALUE)
    {
        return -EIO;
    }

    /* The MCU can reset without the IMU, so start from the IMU's reset state */
    err = software_reset();
    for (size_t i = 0; err == 0 && i < ARRAY_SIZE(setup); i++)
    {
        err = write_checked(setup[i][0], setup[i][1]);
    }
    if (err < 0)
    {
        return err;
    }

    filling.payload.ctrl1_xl = CTRL1_XL_VALUE;
    filling.payload.ctrl2_g  = CTRL2_G_VALUE;

    k_msleep(IMU_SETTLE_MS);
    return fifo_restart(false);
}

int imu_sampler_get_block(imu_block_t *block)
{
    uint8_t status[4]; /* FIFO_STATUS1..4 */
    int     err = lsm6_read_burst(LSM6_REG_FIFO_STATUS1, status, sizeof(status));

    if (err < 0)
    {
        return err;
    }

    const unsigned words   = status[0] | (unsigned) (status[1] & LSM6_FIFO_STATUS2_DIFF_MASK) << 8;
    const unsigned pattern = status[2] | (unsigned) (status[3] & LSM6_FIFO_STATUS4_PATTERN_MASK) << 8;

    /* An overrun overwrote the oldest samples. And since whole frames are always read, the next
     * word should be a gyro X (pattern 0); but an empty FIFO reads pattern 5, the last word read,
     * so only a FIFO with data says anything. Either way the FIFO no longer joins up with the last read. */
    if ((status[1] & LSM6_FIFO_STATUS2_OVER_RUN) || (words > 0U && pattern != 0U))
    {
        return fifo_restart(true);
    }

    unsigned frames = words / IMU_AXES;

    for (; n_discard > 0U && frames > 0U; n_discard--, frames--)
    {
        int16_t frame[IMU_AXES];

        err = fifo_read_frames(frame, 1U);
        if (err < 0)
        {
            return err;
        }
    }

    const unsigned n = MIN(frames, IMU_FRAMES_PER_BLOCK - n_filled);
    if (n > 0U)
    {
        err = fifo_read_frames(filling.payload.frames[n_filled], n);
        if (err < 0)
        {
            return err;
        }
        n_filled += n;
    }
    if (n_filled < IMU_FRAMES_PER_BLOCK)
    {
        return 0;
    }

    err = lsm6_read_burst(LSM6_REG_OUT_TEMP_L, &filling.payload.temperature, sizeof(filling.payload.temperature));
    if (err < 0)
    {
        return err;
    }

    *block   = filling;
    n_filled = 0U;
    filling.seq++;
    return 1;
}

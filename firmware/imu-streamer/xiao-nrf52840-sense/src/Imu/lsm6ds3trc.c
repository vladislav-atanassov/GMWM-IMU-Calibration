/**
 ******************************************************************************
 * @file    lsm6ds3trc.c
 * @brief   LSM6DS3TR-C over i2c0, see lsm6ds3trc.h.
 ******************************************************************************
 */
#include "Imu/lsm6ds3trc.h"

#include <errno.h>
#include <zephyr/drivers/i2c.h>
#include <zephyr/kernel.h>

static const struct i2c_dt_spec imu = I2C_DT_SPEC_GET(DT_NODELABEL(lsm6ds3tr_c));

int lsm6_begin(void)
{
    if (!i2c_is_ready_dt(&imu))
    {
        return -ENODEV;
    }

    /* The regulator powers the IMU at boot, so the turn-on time counts from boot */
    k_sleep(K_TIMEOUT_ABS_MS(LSM6_TURN_ON_MS));
    return 0;
}

int lsm6_read(uint8_t reg)
{
    uint8_t   value;
    const int err = i2c_reg_read_byte_dt(&imu, reg, &value);

    return err < 0 ? err : value;
}

int lsm6_write(uint8_t reg, uint8_t value)
{
    return i2c_reg_write_byte_dt(&imu, reg, value);
}

int lsm6_read_burst(uint8_t reg, void *data, size_t length)
{
    return i2c_burst_read_dt(&imu, reg, data, length);
}

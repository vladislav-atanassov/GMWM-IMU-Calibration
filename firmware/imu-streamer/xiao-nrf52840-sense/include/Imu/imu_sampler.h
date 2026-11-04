/**
 ******************************************************************************
 * @file    imu_sampler.h
 * @brief   Raw gyro, accelerometer, and temperature samples from the LSM6DS3TR-C, in blocks.
 *
 *          The IMU's own clock paces the samples: it writes each one to its FIFO,
 *          and imu_sampler_get_block() drains the FIFO. So a late poll delays
 *          samples but never loses them, until the FIFO fills (see IMU_POLL_MS).
 *          When it does overflow, the partial block is dropped and one seq is
 *          skipped, so the PC sees the gap.
 ******************************************************************************
 */
#ifndef IMU_SAMPLER_H
#define IMU_SAMPLER_H

#include "app_config.h"

#include <stdint.h>

#ifdef __cplusplus
extern "C"
{
#endif

#define IMU_AXES 6U /* gx gy gz ax ay az, the FIFO's order */

/* The STREAM_SRC_LSM6DS3TRC payload, in its wire layout: little-endian, no padding */
typedef struct
{
    uint8_t ctrl1_xl;                               /* accelerometer ODR_XL and FS_XL as the IMU runs them */
    uint8_t ctrl2_g;                                /* gyro ODR_G, FS_G and FS_125 */
    int16_t temperature;                            /* 256 LSB/degC, 0 = 25 degC; read as the block completes */
    int16_t frames[IMU_FRAMES_PER_BLOCK][IMU_AXES]; /* raw codes, oldest first */
} imu_payload_t;

typedef struct
{
    uint32_t      seq; /* block number from start */
    imu_payload_t payload;
} imu_block_t;

/* Resets and sets up the IMU, then starts its FIFO. Returns 0 or a negative errno:
 * -ENODEV when i2c0 is not ready, -EIO when WHO_AM_I or a setting reads back wrong */
int imu_sampler_start(void);

/* Returns 1 when block is filled, 0 when the FIFO has no full block yet, or a negative errno */
int imu_sampler_get_block(imu_block_t *block);

#ifdef __cplusplus
}
#endif

#endif /* IMU_SAMPLER_H */

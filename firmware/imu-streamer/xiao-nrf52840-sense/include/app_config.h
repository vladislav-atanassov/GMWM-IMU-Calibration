/**
 ******************************************************************************
 * @file    app_config.h
 * @brief   Acquisition settings: edit, rebuild, reflash.
 *
 *          Every stream packet carries the CTRL1_XL and CTRL2_G values the IMU
 *          actually runs with, so the PC reads the rate and scales from the data
 *          and nothing here needs copying to MATLAB or Python.
 ******************************************************************************
 */
#ifndef APP_CONFIG_H
#define APP_CONFIG_H

#include "Imu/lsm6ds3trc.h"

/* Gyro, accelerometer, and FIFO sample rate: LSM6_ODR_12_5HZ .. LSM6_ODR_1660HZ.
 * 1.66 kHz uses about half of i2c0's 400 kHz. */
#define IMU_ODR LSM6_ODR_104HZ

/* Full scales: the smallest give the finest resolution, and a static IMU never nears them.
 * 125 dps = 4.375 mdps/LSB and 2 g = 0.061 mg/LSB (datasheet Table 3) */
#define IMU_GYRO_FS  LSM6_FS_G_125DPS
#define IMU_ACCEL_FS LSM6_FS_XL_2G

/* Samples per stream packet: 32 makes a 400-byte packet, about 3 per second at 104 Hz */
#define IMU_FRAMES_PER_BLOCK 32U

/* How often the FIFO is drained. It holds 341 samples: 3.3 s at 104 Hz, 205 ms at 1.66 kHz */
#define IMU_POLL_MS 10U

/* Time from turning the gyro and accelerometer on to the first sample kept, a margin
 * for the gyro's turn-on from power-down */
#define IMU_SETTLE_MS 100U

#endif /* APP_CONFIG_H */

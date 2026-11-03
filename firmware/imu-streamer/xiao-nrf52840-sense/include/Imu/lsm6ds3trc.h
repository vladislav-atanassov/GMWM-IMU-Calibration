/**
 ******************************************************************************
 * @file    lsm6ds3trc.h
 * @brief   The XIAO Sense's on-board LSM6DS3TR-C, wired and powered by the board's devicetree.
 ******************************************************************************
 */
#ifndef LSM6DS3TRC_H
#define LSM6DS3TRC_H

#include <stdint.h>

#ifdef __cplusplus
extern "C"
{
#endif

#define LSM6_TURN_ON_MS 35U /* datasheet Table 4, Ton */

#define LSM6_REG_WHO_AM_I   0x0FU
#define LSM6_WHO_AM_I_VALUE 0x6AU

/* Waits until the IMU has turned on; returns 0, or -ENODEV when i2c0 is not ready */
int lsm6_begin(void);

/* Returns the register's value, or a negative errno when the IMU does not answer */
int lsm6_read(uint8_t reg);

#ifdef __cplusplus
}
#endif

#endif /* LSM6DS3TRC_H */

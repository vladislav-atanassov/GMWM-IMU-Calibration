/**
 ******************************************************************************
 * @file    lsm6ds3trc.h
 * @brief   The XIAO Sense's on-board LSM6DS3TR-C, wired and powered by the board's devicetree.
 *
 *          Register access only; imu_sampler.h sets the IMU up and reads it.
 *          Register and bit names follow the datasheet (DocID030071 Rev 3, section 9).
 ******************************************************************************
 */
#ifndef LSM6DS3TRC_H
#define LSM6DS3TRC_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C"
{
#endif

#define LSM6_TURN_ON_MS 35U /* datasheet Table 4, Ton */

#define LSM6_REG_FIFO_CTRL3    0x08U
#define LSM6_REG_FIFO_CTRL5    0x0AU
#define LSM6_REG_WHO_AM_I      0x0FU
#define LSM6_REG_CTRL1_XL      0x10U
#define LSM6_REG_CTRL2_G       0x11U
#define LSM6_REG_CTRL3_C       0x12U
#define LSM6_REG_OUT_TEMP_L    0x20U
#define LSM6_REG_FIFO_STATUS1  0x3AU /* STATUS1..4 read as one burst */
#define LSM6_REG_FIFO_DATA_OUT 0x3EU /* a burst read wraps 3Fh back to 3Eh */
#define LSM6_WHO_AM_I_VALUE    0x6AU

/* CTRL3_C */
#define LSM6_CTRL3_C_BDU      0x40U /* output registers update only after both bytes are read */
#define LSM6_CTRL3_C_IF_INC   0x04U /* address increments in a burst */
#define LSM6_CTRL3_C_SW_RESET 0x01U /* clears itself when the reset is done */

/* ODR codes, the same for ODR_XL, ODR_G and ODR_FIFO; high-performance mode, the reset default */
#define LSM6_ODR_12_5HZ 0x1U
#define LSM6_ODR_26HZ   0x2U
#define LSM6_ODR_52HZ   0x3U
#define LSM6_ODR_104HZ  0x4U
#define LSM6_ODR_208HZ  0x5U
#define LSM6_ODR_416HZ  0x6U
#define LSM6_ODR_833HZ  0x7U
#define LSM6_ODR_1660HZ 0x8U

/* CTRL1_XL FS_XL[1:0], already in place (bits 3:2) */
#define LSM6_FS_XL_2G  0x0U
#define LSM6_FS_XL_16G 0x4U
#define LSM6_FS_XL_4G  0x8U
#define LSM6_FS_XL_8G  0xCU

/* CTRL2_G FS_G[1:0] and FS_125, already in place (bits 3:1) */
#define LSM6_FS_G_125DPS  0x2U
#define LSM6_FS_G_250DPS  0x0U
#define LSM6_FS_G_500DPS  0x4U
#define LSM6_FS_G_1000DPS 0x8U
#define LSM6_FS_G_2000DPS 0xCU

/* FIFO_CTRL3: gyro is the 1st FIFO data set and the accelerometer the 2nd */
#define LSM6_FIFO_CTRL3_NO_DECIMATION 0x09U /* DEC_FIFO_GYRO = DEC_FIFO_XL = 001 */

/* FIFO_CTRL5 FIFO_MODE[2:0]; ODR_FIFO goes in bits 6:3 */
#define LSM6_FIFO_MODE_BYPASS     0x0U /* also empties the FIFO */
#define LSM6_FIFO_MODE_CONTINUOUS 0x6U /* when full, a new sample overwrites the oldest */

/* FIFO_STATUS2 */
#define LSM6_FIFO_STATUS2_OVER_RUN  0x40U
#define LSM6_FIFO_STATUS2_DIFF_MASK 0x07U /* DIFF_FIFO[10:8] */

/* FIFO_STATUS4 */
#define LSM6_FIFO_STATUS4_PATTERN_MASK 0x03U /* FIFO_PATTERN[9:8] */

/* Waits until the IMU has turned on; returns 0, or -ENODEV when i2c0 is not ready */
int lsm6_begin(void);

/* Returns the register's value, or a negative errno when the IMU does not answer */
int lsm6_read(uint8_t reg);

/* Returns 0 or a negative errno */
int lsm6_write(uint8_t reg, uint8_t value);

/* Reads length bytes from reg on; returns 0 or a negative errno */
int lsm6_read_burst(uint8_t reg, void *data, size_t length);

#ifdef __cplusplus
}
#endif

#endif /* LSM6DS3TRC_H */

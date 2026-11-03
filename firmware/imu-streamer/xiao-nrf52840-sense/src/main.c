/**
 ******************************************************************************
 * @file    main.c
 * @brief   Bring-up check: prints the LSM6DS3TR-C's WHO_AM_I once a second and blinks the red LED.
 ******************************************************************************
 */
#include "Imu/lsm6ds3trc.h"

#include <zephyr/drivers/gpio.h>
#include <zephyr/kernel.h>
#include <zephyr/sys/printk.h>

static const struct gpio_dt_spec red_led = GPIO_DT_SPEC_GET(DT_ALIAS(led0), gpios);

int main(void)
{
    gpio_pin_configure_dt(&red_led, GPIO_OUTPUT_INACTIVE);

    if (lsm6_begin() < 0)
    {
        printk("LSM6DS3TR-C: i2c0 is not ready\n");
        return 0;
    }

    for (;;)
    {
        const int who_am_i = lsm6_read(LSM6_REG_WHO_AM_I);

        if (who_am_i < 0)
        {
            printk("LSM6DS3TR-C: no answer on i2c0 (%d)\n", who_am_i);
        }
        else
        {
            printk("LSM6DS3TR-C: WHO_AM_I = 0x%02X (%s)\n", who_am_i,
                   who_am_i == LSM6_WHO_AM_I_VALUE ? "ok" : "expected 0x6A");
        }

        gpio_pin_toggle_dt(&red_led);
        k_msleep(1000);
    }
}

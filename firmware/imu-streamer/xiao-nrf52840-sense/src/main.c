/**
 ******************************************************************************
 * @file    main.c
 * @brief   The data flow, end to end:
 *
 *            LSM6DS3TR-C FIFO --i2c0--> imu sampler --blocks--> stream --USB CDC ACM--> PC
 *
 *          The red LED toggles with every block sent. It stays on when the IMU
 *          could not be set up, and the reason is printed to the same USB port.
 ******************************************************************************
 */
#include "Imu/imu_sampler.h"
#include "stream_packet.h"

#include <zephyr/drivers/gpio.h>
#include <zephyr/kernel.h>
#include <zephyr/sys/printk.h>

static const struct gpio_dt_spec red_led = GPIO_DT_SPEC_GET(DT_ALIAS(led0), gpios);

int main(void)
{
    gpio_pin_configure_dt(&red_led, GPIO_OUTPUT_INACTIVE);

    int err = imu_sampler_start();
    if (err < 0)
    {
        gpio_pin_set_dt(&red_led, 1);
        for (;;)
        {
            /* Repeated, since the PC usually opens the port after boot */
            printk("LSM6DS3TR-C: setup failed (%d)\n", err);
            k_msleep(1000);
        }
    }

    for (;;)
    {
        imu_block_t block;

        /* A failed read is retried at the next poll. One that lost samples restarts the FIFO
         * and skips a seq, so the PC sees it. No printk here: text between packets costs
         * the PC the packet before it. */
        if (imu_sampler_get_block(&block) > 0)
        {
            stream_send(STREAM_SRC_LSM6DS3TRC, block.seq, &block.payload, sizeof(block.payload));
            gpio_pin_toggle_dt(&red_led);
            continue; /* the FIFO may hold another block */
        }
        k_msleep(IMU_POLL_MS);
    }
}

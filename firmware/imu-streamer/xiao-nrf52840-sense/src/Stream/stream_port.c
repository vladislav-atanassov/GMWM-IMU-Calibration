/**
 ******************************************************************************
 * @file    stream_port.c
 * @brief   Stream packets over USB CDC ACM.
 *
 *          The console shares this port for now, so printk() text mixes with packets.
 ******************************************************************************
 */
#include "stream_port.h"

#include <zephyr/device.h>
#include <zephyr/drivers/uart.h>

static const struct device *const cdc_acm = DEVICE_DT_GET(DT_NODELABEL(board_cdc_acm_uart));

void stream_port_write(const void *data, uint16_t length)
{
    const uint8_t *bytes = data;

    for (uint16_t i = 0; i < length; i++)
    {
        uart_poll_out(cdc_acm, bytes[i]);
    }
}

/**
 ******************************************************************************
 * @file    stream_port.c
 * @brief   Stream packets over USB CDC ACM.
 *
 *          Never blocks: with no flow control, bytes that do not fit the CDC ACM
 *          TX FIFO (sized in app.overlay) are dropped, for example while no PC
 *          has the port open. The PC sees that as a seq gap.
 *
 *          The console shares this port. The PC skips text that is not a packet,
 *          but it also drops the packet just before the text, since it checks that
 *          a packet is followed by the next one's magic. So printk() only before
 *          streaming starts.
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

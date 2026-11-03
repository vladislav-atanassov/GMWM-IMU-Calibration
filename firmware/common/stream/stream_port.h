/**
  ******************************************************************************
  * @file    stream_port.h
  * @brief   The link a board sends stream packets over, see stream_packet.h.
  *
  *          stream_packet.c calls this; each board's firmware provides it, for
  *          example over a UART or USB CDC. Application code calls
  *          stream_send() and does not include this header.
  ******************************************************************************
  */
#ifndef STREAM_PORT_H
#define STREAM_PORT_H

#include <stdint.h>

#ifdef __cplusplus
extern "C"
{
#endif

/* Sends all length bytes in order, blocking until they are sent */
void stream_port_write(const void *data, uint16_t length);

#ifdef __cplusplus
}
#endif

#endif /* STREAM_PORT_H */

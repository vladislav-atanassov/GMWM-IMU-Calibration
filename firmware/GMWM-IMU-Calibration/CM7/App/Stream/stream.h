/**
  ******************************************************************************
  * @file    stream.h
  * @brief   Packets to MATLAB over USART3 (ST-LINK virtual COM port).
  *
  *          Every packet is a 12-byte header followed by the payload, all
  *          little-endian:
  *            uint32  magic   STREAM_MAGIC, to find packet boundaries
  *            uint16  source  STREAM_SRC_*, who produced the payload
  *            uint16  length  payload size in bytes
  *            uint32  seq     block number from the source; a gap = lost blocks
  ******************************************************************************
  */
#ifndef STREAM_H
#define STREAM_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define STREAM_MAGIC 0xC0DEC0DEU

#define STREAM_SRC_EMULATOR 1U /* payload: frames of [clean, noisy] uint16 ADC codes */

/* Blocks until the whole packet is sent */
void stream_send(uint16_t source, uint32_t seq, const void *payload, uint16_t length);

#ifdef __cplusplus
}
#endif

#endif /* STREAM_H */

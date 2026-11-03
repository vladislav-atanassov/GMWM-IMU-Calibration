/**
  ******************************************************************************
  * @file    stream_packet.h
  * @brief   Packets to the PC, the same format from every board.
  *
  *          Every packet is a 12-byte header followed by the payload, all
  *          little-endian:
  *            uint32  magic   STREAM_MAGIC, to find packet boundaries
  *            uint16  source  STREAM_SRC_*, who produced the payload
  *            uint16  length  payload size in bytes
  *            uint32  seq     block number from the source; a gap = lost blocks
  *
  *          The bytes go out through stream_port_write(), which each board
  *          implements for its own link (see stream_port.h).
  *
  *          Not named stream.h: on Windows that name also matches Arduino's
  *          Stream.h, and the XIAO's core would include this file instead.
  ******************************************************************************
  */
#ifndef STREAM_PACKET_H
#define STREAM_PACKET_H

#include <stdint.h>

#ifdef __cplusplus
extern "C"
{
#endif

#define STREAM_MAGIC 0xC0DEC0DEU

/* One ID per payload format, so IDs from different boards never collide */
#define STREAM_SRC_EMULATOR 1U /* payload: frames of [clean, noisy] uint16 ADC codes */

/* Blocks until the whole packet is sent */
void stream_send(uint16_t source, uint32_t seq, const void *payload, uint16_t length);

#ifdef __cplusplus
}
#endif

#endif /* STREAM_PACKET_H */

/**
  ******************************************************************************
  * @file    stream_packet.c
  * @brief   Packet framing, see stream_packet.h.
  ******************************************************************************
  */
#include "stream_packet.h"

#include "stream_port.h"

typedef struct
{
    uint32_t magic;
    uint16_t source;
    uint16_t length;
    uint32_t seq;
} stream_header_t;

/* The header is sent as its in-memory bytes, so its layout must be the wire layout */
_Static_assert(sizeof(stream_header_t) == 12U, "stream header must have no padding");
_Static_assert(__BYTE_ORDER__ == __ORDER_LITTLE_ENDIAN__, "stream format is little-endian");

void stream_send(uint16_t source, uint32_t seq, const void *payload, uint16_t length)
{
    const stream_header_t header = {STREAM_MAGIC, source, length, seq};

    stream_port_write(&header, sizeof(header));
    stream_port_write(payload, length);
}

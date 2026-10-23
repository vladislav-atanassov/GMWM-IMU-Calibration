/**
  ******************************************************************************
  * @file    stream.c
  * @brief   Packets to MATLAB over USART3, see stream.h.
  ******************************************************************************
  */
#include "stream.h"

#include "usart.h"

typedef struct
{
    uint32_t magic;
    uint16_t source;
    uint16_t length;
    uint32_t seq;
} stream_header_t;

_Static_assert(sizeof(stream_header_t) == 12U, "stream header must have no padding");

void stream_send(uint16_t source, uint32_t seq, const void *payload, uint16_t length)
{
    const stream_header_t header = {STREAM_MAGIC, source, length, seq};

    HAL_UART_Transmit(&huart3, (const uint8_t *) &header, sizeof(header), HAL_MAX_DELAY);
    HAL_UART_Transmit(&huart3, (const uint8_t *) payload, length, HAL_MAX_DELAY);
}

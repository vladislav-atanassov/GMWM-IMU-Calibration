/**
  ******************************************************************************
  * @file    stream_port.c
  * @brief   Stream packets over USART3, the ST-LINK virtual COM port.
  ******************************************************************************
  */
#include "stream_port.h"

#include "usart.h"

void stream_port_write(const void *data, uint16_t length)
{
    HAL_UART_Transmit(&huart3, (const uint8_t *) data, length, HAL_MAX_DELAY);
}

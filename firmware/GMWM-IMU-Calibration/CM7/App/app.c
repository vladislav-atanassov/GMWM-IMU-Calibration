/**
  ******************************************************************************
  * @file    app.c
  * @brief   The data flow, end to end:
  *
  *            sensor emulator --blocks--> stream --USART3--> MATLAB
  ******************************************************************************
  */
#include "app.h"

#include "sensor_emulator.h"
#include "stream.h"

void app_start(void)
{
  sensor_emulator_start();
}

void app_poll(void)
{
  sensor_emulator_block_t block;
  if (sensor_emulator_get_block(&block))
  {
    stream_send(STREAM_SRC_EMULATOR, block.seq, block.frames,
                (uint16_t)(block.n_frames * SENSOR_EMULATOR_CHANNELS * sizeof(uint16_t)));
  }
}

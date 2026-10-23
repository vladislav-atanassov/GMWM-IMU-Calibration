/**
  ******************************************************************************
  * @file    sensor_emulator.h
  * @brief   A sensor with known noise, built from the DAC and ADC.
  *
  *          SignalGen writes a clean signal to DAC1 CH1 and the same signal with
  *          noise to DAC1 CH2. ADC2 reads both back on every TIM6 tick, so each
  *          frame holds the measured [clean, noisy] pair: ground truth plus a
  *          noisy measurement. Settings are in app_config.h.
  ******************************************************************************
  */
#ifndef SENSOR_EMULATOR_H
#define SENSOR_EMULATOR_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C"
{
#endif

#define SENSOR_EMULATOR_CHANNELS 2U /* per frame: clean, noisy */

typedef struct
{
    const uint16_t *frames; /* n_frames x [clean, noisy] 16-bit ADC codes */
    uint32_t        n_frames;
    uint32_t        seq; /* block number since start; a gap means blocks were skipped */
} sensor_emulator_block_t;

/* Sets TIM6 to EMULATOR_FS_HZ, starts the DAC and ADC, then the timer */
void sensor_emulator_start(void);

/* Returns true and fills block when a new block is ready. The data stays valid
 * for one block period (256 samples), until the ADC wraps around to it again. */
bool sensor_emulator_get_block(sensor_emulator_block_t *block);

#ifdef __cplusplus
}
#endif

#endif /* SENSOR_EMULATOR_H */

/**
  ******************************************************************************
  * @file    signal_gen_config.h
  * @brief   Experiment settings for the sensor emulator: edit, rebuild, reflash.
  ******************************************************************************
  */
#ifndef SIGNAL_GEN_CONFIG_H
#define SIGNAL_GEN_CONFIG_H

#include "signal_gen.h"

#include <stddef.h>

/* Sensor emulator
 * A sensor with known noise: DAC1 CH1 outputs the clean signal, DAC1 CH2 the
 * same signal with noise added, and ADC2 samples both on every TIM6 tick.
 *
 * Levels are 12-bit DAC codes: 1 code = VREF+ / 4096, about 0.81 mV with the
 * Nucleo's 3.3 V VREF+. Keep offset + amplitude + 4 x noise inside 0..4095,
 * or samples clip (signal_gen_t.clipped counts them).
 */

static const signal_gen_config_t signal_gen_config_app = {
    .fs_hz = 1000.0f, /* sample rate, 1..10000 Hz; TIM6 is set from this */

    /* Signal: offset + amplitude * wave(f t); amplitude 0 gives a constant level */
    .wave        = signal_gen_wave_sine, /* signal_gen_wave_*, or any signal_gen_wave_t */
    .wave_params = NULL,                 /* signal_gen_pulse_t or signal_gen_table_t for those waves */
    .offset      = 2048.0f,              /* DC level, mid-scale */
    .amplitude   = 1024.0f,              /* about +-0.83 V */
    .freq_hz     = 1.0f,                 /* must be below half the sample rate */

    /* Noise on the second channel: OR SIGNAL_GEN_NOISE_* flags, or SIGNAL_GEN_NOISE_NONE */
    .noise     = SIGNAL_GEN_NOISE_WHITE,
    .white_std = 64.0f, /* white noise standard deviation, about 52 mV */
    .seed      = 1U,    /* the same seed reproduces the same noise */
};

#endif /* SIGNAL_GEN_CONFIG_H */

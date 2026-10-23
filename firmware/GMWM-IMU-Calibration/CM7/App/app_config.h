/**
  ******************************************************************************
  * @file    app_config.h
  * @brief   Experiment settings: edit, rebuild, reflash.
  ******************************************************************************
  */
#ifndef APP_CONFIG_H
#define APP_CONFIG_H

#include "signal_gen.h"

/* ---- Sensor emulator ---------------------------------------------------------
 * A sensor with known noise: DAC1 CH1 outputs the clean signal, DAC1 CH2 the
 * same signal with noise added, and ADC2 samples both on every TIM6 tick.
 *
 * Levels are 12-bit DAC codes: 1 code = VREF+ / 4096, about 0.81 mV with the
 * Nucleo's 3.3 V VREF+. Keep offset + amplitude + 4 x noise inside 0..4095,
 * or samples clip (signal_gen_t.clipped counts them).
 */

#define EMULATOR_FS_HZ           1000U   /* sample rate, 1..10000 Hz; TIM6 is set from this */

/* Signal: offset + amplitude * sin(2 pi f t); amplitude 0 gives a constant level */
#define EMULATOR_SIG_OFFSET      2048.0f /* DC level, mid-scale */
#define EMULATOR_SIG_AMPLITUDE   1024.0f /* about +-0.83 V */
#define EMULATOR_SIG_FREQ_HZ     1.0f    /* must be below half the sample rate */

/* Noise on the second channel: OR SIGNAL_GEN_NOISE_* flags, or SIGNAL_GEN_NOISE_NONE */
#define EMULATOR_NOISE           (SIGNAL_GEN_NOISE_WHITE)
#define EMULATOR_NOISE_WHITE_STD 64.0f   /* white noise standard deviation, about 52 mV */
#define EMULATOR_NOISE_SEED      1U      /* the same seed reproduces the same noise */

/* Signal generator settings from the values above; fs is the rate TIM6 actually
 * achieves. A new SignalGen parameter only needs its define above and a line here. */
#define EMULATOR_SIGNAL_GEN_CONFIG(fs)        \
  {                                           \
    .fs_hz = (fs),                            \
    .offset = EMULATOR_SIG_OFFSET,            \
    .amplitude = EMULATOR_SIG_AMPLITUDE,      \
    .freq_hz = EMULATOR_SIG_FREQ_HZ,          \
    .noise = EMULATOR_NOISE,                  \
    .white_std = EMULATOR_NOISE_WHITE_STD,    \
    .seed = EMULATOR_NOISE_SEED,              \
  }

#endif /* APP_CONFIG_H */

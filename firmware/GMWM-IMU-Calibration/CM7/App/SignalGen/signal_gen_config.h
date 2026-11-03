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
 * DAC1 CH1 outputs the clean signal and DAC1 CH2 the same signal with noise
 * added; ADC2 samples both on every TIM6 tick. Levels are 12-bit DAC codes
 * (1 code = VREF+ / 4096, about 0.81 mV). Keep offset + amplitude + 4 x noise
 * inside 0..4095, or samples clip (signal_gen_t.clipped counts them).
 *
 * As set, the noisy channel is one axis of a static LSM6DS3TR-C gyro logged
 * at 104 Hz. One DAC code is 0.20 mdps (0.72 deg/h), and each sample stands
 * for one 104 Hz IMU sample, so 19 min at 1 kHz replays a 3 h log:
 *   white noise   5 mdps/rtHz (datasheet): an angle random walk of 0.3 deg/rth
 *   Gauss-Markov  11.5 and 10.8 deg/h with correlation times of 3.6 s and 80 s
 *                 at 104 Hz; together a bias instability of about 11 deg/h
 *   random walk   a rate random walk of 31 deg/h/rth
 *
 * The random walk starts at 0 on reset and is unbounded: its standard deviation
 * is rw_step x sqrt(samples since reset), about 75 codes after 19 min but 650
 * after a day, enough that samples can clip. Reset the board before recording.
 */

static const signal_gen_config_t signal_gen_config_app = {
    .fs_hz = 1000.0f, /* sample rate, 1..10000 Hz; TIM6 is set from this */

    /* Signal: offset + amplitude * wave(f t); amplitude 0 gives a constant level */
    .wave        = signal_gen_wave_sine, /* signal_gen_wave_*, or any signal_gen_wave_t */
    .wave_params = NULL,                 /* signal_gen_pulse_t or signal_gen_table_t for those waves */
    .offset      = 2048.0f,              /* DC level, mid-scale */
    .amplitude   = 0.0f,                 /* a constant level, like a static IMU */
    .freq_hz     = 1.0f,                 /* must be below half the sample rate */

    /* Noise on the second channel: OR SIGNAL_GEN_NOISE_* flags, or SIGNAL_GEN_NOISE_NONE */
    .noise     = SIGNAL_GEN_NOISE_WHITE | SIGNAL_GEN_NOISE_GM | SIGNAL_GEN_NOISE_RW,
    .white_std = 256.0f,                                                        /* white noise standard deviation */
    .gm        = {{.tc_s = 0.37f, .std = 16.0f}, {.tc_s = 8.3f, .std = 15.0f}}, /* bias instability */
    .rw_step   = 0.07f,                                                         /* rate random walk, per sample */
    .seed      = 1U, /* the same seed reproduces the same noise */
};

#endif /* SIGNAL_GEN_CONFIG_H */

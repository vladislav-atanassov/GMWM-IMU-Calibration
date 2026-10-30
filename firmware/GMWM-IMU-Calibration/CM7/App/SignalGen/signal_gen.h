/**
  ******************************************************************************
  * @file    signal_gen.h
  * @brief   DAC test-signal generator: a periodic waveform plus the same
  *          waveform with white Gaussian noise added, as 12-bit DAC codes.
  *
  *          All levels are in DAC codes (1 LSB = VREF+ / 4096).
  ******************************************************************************
  */
#ifndef SIGNAL_GEN_H
#define SIGNAL_GEN_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C"
{
#endif

#define SIGNAL_GEN_DAC_MAX 4095U /* 12-bit DAC full scale */

/* Noise processes added to the noisy output; OR them together to combine */
#define SIGNAL_GEN_NOISE_NONE  0U
#define SIGNAL_GEN_NOISE_WHITE (1U << 0) /* white Gaussian noise, set by white_std */

/* Level in -1..1 at phase (2^32 = one period); params is cfg.wave_params */
typedef float (*signal_gen_wave_t)(uint32_t phase, const void *params);

typedef struct
{
    float             fs_hz;       /* sample rate = DAC trigger frequency */
    signal_gen_wave_t wave;        /* signal shape */
    const void       *wave_params; /* passed to wave */
    float             offset;      /* DC level */
    float             amplitude;   /* peak deviation from offset, 0 for a constant level */
    float             freq_hz;     /* waveform frequency, must be below fs_hz / 2 */
    uint32_t          noise;       /* SIGNAL_GEN_NOISE_* flags */
    float             white_std;   /* white noise standard deviation */
    uint32_t          seed;        /* the same seed reproduces the same noise sequence */
} signal_gen_config_t;

typedef struct
{
    signal_gen_config_t cfg;
    uint32_t            phase; /* waveform phase, one full period = 2^32 */
    uint32_t            phase_inc;
    uint64_t            rng;   /* PCG32 state */
    float               spare; /* second Box-Muller output, used on the next call */
    bool                has_spare;
    uint32_t            clipped; /* samples clipped to 0..SIGNAL_GEN_DAC_MAX since init */
} signal_gen_t;

/* wave_params for signal_gen_wave_pulse */
typedef struct
{
    float duty; /* fraction of the period at +1, 0..1 */
} signal_gen_pulse_t;

/* wave_params for signal_gen_wave_table: one period of samples */
typedef struct
{
    const float *samples;
    uint32_t     n; /* at least 1 */
} signal_gen_table_t;

/* Built-in waveforms, p = phase / 2^32; they match MATLAB's sin, square and sawtooth */
float signal_gen_wave_sine(uint32_t phase, const void *params);     /* sin(2 pi p) */
float signal_gen_wave_square(uint32_t phase, const void *params);   /* +1 for p < 1/2, else -1 */
float signal_gen_wave_triangle(uint32_t phase, const void *params); /* -1 at p = 0, +1 at p = 1/2 */
float signal_gen_wave_sawtooth(uint32_t phase, const void *params); /* 2p - 1, rising */
float signal_gen_wave_pulse(uint32_t phase, const void *params);    /* +1 for p < duty, else -1 */
float signal_gen_wave_table(uint32_t phase, const void *params);    /* samples, linearly interpolated */

/* Returns false, leaving sg untouched, if cfg is invalid: fs_hz <= 0,
 * freq_hz outside [0, fs_hz / 2), no wave or a negative noise level. */
bool signal_gen_init(signal_gen_t *sg, const signal_gen_config_t *cfg);

/* Generates the next n samples:
 *   clean[i] = offset + amplitude * wave(phase)
 *   noisy[i] = clean[i] + the noise processes selected in cfg.noise
 * Either output pointer may be NULL. */
void signal_gen_fill(signal_gen_t *sg, uint16_t *clean, uint16_t *noisy, uint32_t n);

#ifdef __cplusplus
}
#endif

#endif /* SIGNAL_GEN_H */

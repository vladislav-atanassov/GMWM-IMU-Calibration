/**
  ******************************************************************************
  * @file    signal_gen.h
  * @brief   DAC test-signal generator: a sine wave plus the same sine with
  *          white Gaussian noise added, as 12-bit DAC codes.
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

typedef struct
{
    float    fs_hz;     /* sample rate = DAC trigger frequency */
    float    offset;    /* DC level */
    float    amplitude; /* sine amplitude, 0 for a constant level */
    float    freq_hz;   /* sine frequency, must be below fs_hz / 2 */
    uint32_t noise;     /* SIGNAL_GEN_NOISE_* flags */
    float    white_std; /* white noise standard deviation */
    uint32_t seed;      /* the same seed reproduces the same noise sequence */
} signal_gen_config_t;

typedef struct
{
    signal_gen_config_t cfg;
    uint32_t            phase; /* sine phase, one full turn = 2^32 */
    uint32_t            phase_inc;
    uint64_t            rng;   /* PCG32 state */
    float               spare; /* second Box-Muller output, used on the next call */
    bool                has_spare;
    uint32_t            clipped; /* samples clipped to 0..SIGNAL_GEN_DAC_MAX since init */
} signal_gen_t;

/* Returns false, leaving sg untouched, if cfg is invalid: fs_hz <= 0,
 * freq_hz outside [0, fs_hz / 2) or a negative noise level. */
bool signal_gen_init(signal_gen_t *sg, const signal_gen_config_t *cfg);

/* Generates the next n samples:
 *   clean[i] = offset + amplitude * sin(2 pi freq t)
 *   noisy[i] = clean[i] + the noise processes selected in cfg.noise
 * Either output pointer may be NULL. */
void signal_gen_fill(signal_gen_t *sg, uint16_t *clean, uint16_t *noisy, uint32_t n);

#ifdef __cplusplus
}
#endif

#endif /* SIGNAL_GEN_H */

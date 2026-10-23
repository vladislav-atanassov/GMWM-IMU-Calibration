/**
  ******************************************************************************
  * @file    signal_gen.c
  * @brief   DAC test-signal generator, see signal_gen.h.
  ******************************************************************************
  */
#include "signal_gen.h"

#include <math.h>
#include <stddef.h>

#define TWO_PI_F     6.28318530718f
#define PHASE_TO_RAD (TWO_PI_F / 4294967296.0f)

/* PCG32 (O'Neill, pcg-random.org): 64-bit state, 32-bit output, period 2^64 */
static uint32_t pcg32(uint64_t *state)
{
  uint64_t old = *state;
  *state = old * 6364136223846793005ULL + 1442695040888963407ULL;
  uint32_t xorshifted = (uint32_t)(((old >> 18) ^ old) >> 27);
  uint32_t rot = (uint32_t)(old >> 59);
  return (xorshifted >> rot) | (xorshifted << ((32U - rot) & 31U));
}

/* Uniform in (0, 1] with 24-bit resolution; never 0, so logf() is safe */
static float uniform(signal_gen_t *sg)
{
  return (float)((pcg32(&sg->rng) >> 8) + 1U) * (1.0f / 16777216.0f);
}

/* Standard normal sample (Box-Muller); each pair costs one logf, sqrtf, sinf, cosf */
static float gauss(signal_gen_t *sg)
{
  if (sg->has_spare)
  {
    sg->has_spare = false;
    return sg->spare;
  }

  float r = sqrtf(-2.0f * logf(uniform(sg)));
  float theta = TWO_PI_F * uniform(sg);
  sg->spare = r * sinf(theta);
  sg->has_spare = true;
  return r * cosf(theta);
}

static uint16_t to_code(signal_gen_t *sg, float v)
{
  if (v < 0.0f)
  {
    sg->clipped++;
    return 0U;
  }
  if (v > (float)SIGNAL_GEN_DAC_MAX)
  {
    sg->clipped++;
    return SIGNAL_GEN_DAC_MAX;
  }
  return (uint16_t)(v + 0.5f);
}

bool signal_gen_init(signal_gen_t *sg, const signal_gen_config_t *cfg)
{
  /* Written as !(valid) so NaN settings are rejected too */
  if (!(cfg->fs_hz > 0.0f) || !(cfg->freq_hz >= 0.0f) || !(cfg->freq_hz < 0.5f * cfg->fs_hz) ||
      !(cfg->white_std >= 0.0f))
  {
    return false;
  }

  sg->cfg = *cfg;
  sg->phase = 0U;
  /* Rounded: the frequency is then within fs / 2^33 of freq_hz */
  sg->phase_inc = (uint32_t)((double)cfg->freq_hz / (double)cfg->fs_hz * 4294967296.0 + 0.5);

  /* Standard PCG32 seeding */
  sg->rng = 0U;
  (void)pcg32(&sg->rng);
  sg->rng += cfg->seed;
  (void)pcg32(&sg->rng);

  sg->spare = 0.0f;
  sg->has_spare = false;
  sg->clipped = 0U;
  return true;
}

void signal_gen_fill(signal_gen_t *sg, uint16_t *clean, uint16_t *noisy, uint32_t n)
{
  for (uint32_t i = 0U; i < n; i++)
  {
    float s = sg->cfg.offset + sg->cfg.amplitude * sinf((float)sg->phase * PHASE_TO_RAD);
    sg->phase += sg->phase_inc;

    if (clean != NULL)
    {
      clean[i] = to_code(sg, s);
    }
    if (noisy != NULL)
    {
      float noise = 0.0f;
      if ((sg->cfg.noise & SIGNAL_GEN_NOISE_WHITE) != 0U)
      {
        noise += sg->cfg.white_std * gauss(sg);
      }
      noisy[i] = to_code(sg, s + noise);
    }
  }
}

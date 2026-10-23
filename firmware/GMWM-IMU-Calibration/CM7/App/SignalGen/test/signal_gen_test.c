/**
  ******************************************************************************
  * @file    signal_gen_test.c
  * @brief   PC-side checks for SignalGen. Not part of the firmware build.
  *
  *          From this directory:
  *            gcc -std=c11 -Wall -Wextra -O2 -I.. ../signal_gen.c signal_gen_test.c -lm -o signal_gen_test
  *            ./signal_gen_test
  *
  *          Exits with 0 when every check passes.
  ******************************************************************************
  */
#include <math.h>
#include <stdio.h>
#include <string.h>

#include "signal_gen.h"

#define N      200000U
#define CHUNK  250U /* fill in chunks, like the firmware's half-buffers */
#define FS     500.0f
#define STD    64.0f
#define PI     3.14159265358979323846 /* M_PI is not in strict C11 */

static uint16_t clean[N];
static uint16_t noisy[N];
static uint16_t clean2[N];
static uint16_t noisy2[N];
static int failures;

#define CHECK(cond, ...)                \
  do                                    \
  {                                     \
    printf("%s  ", (cond) ? "PASS" : "FAIL"); \
    printf(__VA_ARGS__);                \
    printf("\n");                       \
    if (!(cond))                        \
    {                                   \
      failures++;                       \
    }                                   \
  } while (0)

static signal_gen_config_t base_config(void)
{
  signal_gen_config_t cfg = {
    .fs_hz = FS,
    .offset = 2048.0f,
    .amplitude = 1024.0f,
    .freq_hz = 1.0f,
    .noise = SIGNAL_GEN_NOISE_WHITE,
    .white_std = STD,
    .seed = 1U,
  };
  return cfg;
}

static void generate(const signal_gen_config_t *cfg, uint16_t *c, uint16_t *n, uint32_t chunk)
{
  signal_gen_t sg;
  signal_gen_init(&sg, cfg);
  for (uint32_t i = 0U; i < N; i += chunk)
  {
    signal_gen_fill(&sg, c ? &c[i] : NULL, n ? &n[i] : NULL, chunk);
  }
}

static void test_white_noise(void)
{
  const signal_gen_config_t cfg = base_config();
  generate(&cfg, clean, noisy, CHUNK);

  double mean = 0.0;
  for (uint32_t i = 0U; i < N; i++)
  {
    mean += (double)noisy[i] - (double)clean[i];
  }
  mean /= N;

  double var = 0.0, m3 = 0.0, m4 = 0.0, lag1 = 0.0, prev = 0.0;
  for (uint32_t i = 0U; i < N; i++)
  {
    double d = (double)noisy[i] - (double)clean[i] - mean;
    var += d * d;
    m3 += d * d * d;
    m4 += d * d * d * d;
    if (i > 0U)
    {
      lag1 += d * prev;
    }
    prev = d;
  }
  var /= N;
  m3 /= N;
  m4 /= N;
  lag1 /= (N - 1U) * var;

  double std = sqrt(var);
  double skew = m3 / pow(var, 1.5);
  double kurt = m4 / (var * var);

  /* Limits are about 4 standard errors for N = 200000 */
  CHECK(fabs(mean) < 0.6, "noise mean %.3f (0)", mean);
  CHECK(fabs(std - STD) < 0.5, "noise std %.3f (%.0f)", std, STD);
  CHECK(fabs(skew) < 0.025, "noise skew %.4f (0)", skew);
  CHECK(fabs(kurt - 3.0) < 0.05, "noise kurtosis %.4f (3)", kurt);
  CHECK(fabs(lag1) < 0.01, "noise lag-1 autocorrelation %.4f (0, white)", lag1);
}

static void test_sine(void)
{
  const signal_gen_config_t cfg = base_config();
  generate(&cfg, clean, NULL, CHUNK);

  uint16_t lo = 0xFFFF, hi = 0U;
  for (uint32_t i = 0U; i < N; i++)
  {
    lo = clean[i] < lo ? clean[i] : lo;
    hi = clean[i] > hi ? clean[i] : hi;
  }
  CHECK(lo == 1024U && hi == 3072U, "sine range %u..%u (1024..3072)", lo, hi);

  /* Compare against an exact sine over the whole run (400 s); amplitude, phase
   * and frequency errors would all grow past 1 code */
  double worst = 0.0;
  for (uint32_t i = 0U; i < N; i++)
  {
    double ideal = cfg.offset + cfg.amplitude * sin(2.0 * PI * cfg.freq_hz * i / FS);
    double err = fabs((double)clean[i] - ideal);
    worst = err > worst ? err : worst;
  }
  CHECK(worst <= 1.0, "sine within %.3f codes of an exact sine over %u samples", worst, N);
}

static void test_chunking(void)
{
  /* Filling in chunks must give exactly the same output as one long fill */
  const signal_gen_config_t cfg = base_config();
  generate(&cfg, clean, noisy, CHUNK);
  generate(&cfg, clean2, noisy2, N);
  CHECK(memcmp(clean, clean2, sizeof(clean)) == 0 && memcmp(noisy, noisy2, sizeof(noisy)) == 0,
        "chunked fill equals single fill");
}

static void test_seed(void)
{
  signal_gen_config_t cfg = base_config();
  generate(&cfg, NULL, noisy, CHUNK);
  generate(&cfg, NULL, noisy2, CHUNK);
  CHECK(memcmp(noisy, noisy2, sizeof(noisy)) == 0, "same seed gives the same noise");

  cfg.seed = 2U;
  generate(&cfg, NULL, noisy2, CHUNK);
  CHECK(memcmp(noisy, noisy2, sizeof(noisy)) != 0, "different seed gives different noise");
}

static void test_no_noise(void)
{
  signal_gen_config_t cfg = base_config();
  cfg.noise = SIGNAL_GEN_NOISE_NONE;
  generate(&cfg, clean, noisy, CHUNK);
  CHECK(memcmp(clean, noisy, sizeof(clean)) == 0, "SIGNAL_GEN_NOISE_NONE: noisy equals clean");
}

static void test_clipping(void)
{
  signal_gen_config_t cfg = base_config();
  cfg.offset = 4000.0f;
  cfg.amplitude = 0.0f;

  signal_gen_t sg;
  signal_gen_init(&sg, &cfg);
  signal_gen_fill(&sg, clean, noisy, 1000U);

  uint16_t hi = 0U;
  for (uint32_t i = 0U; i < 1000U; i++)
  {
    hi = noisy[i] > hi ? noisy[i] : hi;
  }
  CHECK(sg.clipped > 0U && hi == SIGNAL_GEN_DAC_MAX, "clipping counted (%u) and capped at %u", sg.clipped, hi);
}

static void test_validation(void)
{
  signal_gen_t sg;
  signal_gen_config_t cfg = base_config();
  CHECK(signal_gen_init(&sg, &cfg), "valid settings accepted");

  cfg = base_config();
  cfg.freq_hz = FS / 2.0f;
  CHECK(!signal_gen_init(&sg, &cfg), "freq = fs/2 rejected");

  cfg = base_config();
  cfg.fs_hz = 0.0f;
  CHECK(!signal_gen_init(&sg, &cfg), "fs = 0 rejected");

  cfg = base_config();
  cfg.white_std = -1.0f;
  CHECK(!signal_gen_init(&sg, &cfg), "negative noise level rejected");

  cfg = base_config();
  cfg.freq_hz = NAN;
  CHECK(!signal_gen_init(&sg, &cfg), "NaN frequency rejected");
}

int main(void)
{
  test_white_noise();
  test_sine();
  test_chunking();
  test_seed();
  test_no_noise();
  test_clipping();
  test_validation();

  printf("\n%s: %d failure(s)\n", failures ? "FAILED" : "OK", failures);
  return failures ? 1 : 0;
}

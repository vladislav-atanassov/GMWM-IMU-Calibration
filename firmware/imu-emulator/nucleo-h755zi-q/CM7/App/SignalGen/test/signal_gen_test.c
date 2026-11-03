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
#include "signal_gen.h"

#include <math.h>
#include <stdio.h>
#include <string.h>

#define N     200000U
#define CHUNK 250U /* fill in chunks, like the firmware's half-buffers */
#define FS    500.0f
#define STD   64.0f
#define PI    3.14159265358979323846 /* M_PI is not in strict C11 */

static uint16_t clean[N];
static uint16_t noisy[N];
static uint16_t clean2[N];
static uint16_t noisy2[N];
static int      failures;

#define CHECK(cond, ...)                                                                                               \
    do                                                                                                                 \
    {                                                                                                                  \
        printf("%s  ", (cond) ? "PASS" : "FAIL");                                                                      \
        printf(__VA_ARGS__);                                                                                           \
        printf("\n");                                                                                                  \
        if (!(cond))                                                                                                   \
        {                                                                                                              \
            failures++;                                                                                                \
        }                                                                                                              \
    } while (0)

static signal_gen_config_t base_config(void)
{
    signal_gen_config_t cfg = {
        .fs_hz     = FS,
        .wave      = signal_gen_wave_sine,
        .offset    = 2048.0f,
        .amplitude = 1024.0f,
        .freq_hz   = 1.0f,
        .noise     = SIGNAL_GEN_NOISE_WHITE,
        .white_std = STD,
        .seed      = 1U,
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
        mean += (double) noisy[i] - (double) clean[i];
    }
    mean /= N;

    double var = 0.0, m3 = 0.0, m4 = 0.0, lag1 = 0.0, prev = 0.0;
    for (uint32_t i = 0U; i < N; i++)
    {
        double d = (double) noisy[i] - (double) clean[i] - mean;
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

    double std  = sqrt(var);
    double skew = m3 / pow(var, 1.5);
    double kurt = m4 / (var * var);

    /* Limits are about 4 standard errors for N = 200000 */
    CHECK(fabs(mean) < 0.6, "noise mean %.3f (0)", mean);
    CHECK(fabs(std - STD) < 0.5, "noise std %.3f (%.0f)", std, STD);
    CHECK(fabs(skew) < 0.025, "noise skew %.4f (0)", skew);
    CHECK(fabs(kurt - 3.0) < 0.05, "noise kurtosis %.4f (3)", kurt);
    CHECK(fabs(lag1) < 0.01, "noise lag-1 autocorrelation %.4f (0, white)", lag1);
}

static void test_gauss_markov(void)
{
    signal_gen_config_t cfg = base_config();
    cfg.amplitude           = 0.0f;
    cfg.noise               = SIGNAL_GEN_NOISE_GM;
    cfg.gm[0].tc_s          = 10.0f / FS; /* 10 samples; gm[1] stays off */
    cfg.gm[0].std           = STD;
    generate(&cfg, NULL, noisy, CHUNK);

    double mean = 0.0;
    for (uint32_t i = 0U; i < N; i++)
    {
        mean += (double) noisy[i];
    }
    mean /= N;

    double var = 0.0, lag1 = 0.0, prev = 0.0;
    for (uint32_t i = 0U; i < N; i++)
    {
        double d = (double) noisy[i] - mean;
        var += d * d;
        if (i > 0U)
        {
            lag1 += d * prev;
        }
        prev = d;
    }
    var /= N;
    lag1 /= (N - 1U) * var;

    double std = sqrt(var);
    double phi = exp(-1.0 / 10.0);

    /* Limits are about 4 standard errors for N = 200000 and this phi */
    CHECK(fabs(std - STD) < 1.3, "Gauss-Markov std %.3f (%.0f)", std, (double) STD);
    CHECK(fabs(lag1 - phi) < 0.004, "Gauss-Markov lag-1 autocorrelation %.4f (%.4f)", lag1, phi);
}

/* RMS of x[i + lag] - x[i]; every increment has mean 0 here */
static double increment_rms(const uint16_t *x, uint32_t lag)
{
    double sum = 0.0;
    for (uint32_t i = lag; i < N; i++)
    {
        double d = (double) x[i] - (double) x[i - lag];
        sum += d * d;
    }
    return sqrt(sum / (N - lag));
}

static void test_random_walk(void)
{
    signal_gen_config_t cfg = base_config();
    cfg.amplitude           = 0.0f;
    cfg.noise               = SIGNAL_GEN_NOISE_RW;
    cfg.rw_step             = 1.0f;
    generate(&cfg, NULL, noisy, CHUNK);

    /* Over lag samples the walk moves sqrt(lag) x rw_step, and rounding to codes adds a
     * variance of 1/12 at each end. White noise would give the same spread at both lags.
     * Limits are about 4 standard errors for N = 200000 */
    double s1   = increment_rms(noisy, 1U);
    double s100 = increment_rms(noisy, 100U);
    double e1   = sqrt(1.0 + 1.0 / 6.0);
    double e100 = sqrt(100.0 + 1.0 / 6.0);
    CHECK(fabs(s1 - e1) < 0.01, "random walk spread over 1 sample %.4f (%.4f)", s1, e1);
    CHECK(fabs(s100 - e100) < 0.5, "random walk spread over 100 samples %.3f (%.3f)", s100, e100);
}

/* A custom waveform: steps through the levels in params */
typedef struct
{
    const float *levels;
    uint32_t     n;
} staircase_t;

static float wave_staircase(uint32_t phase, const void *params)
{
    const staircase_t *s = params;
    return s->levels[((uint64_t) phase * s->n) >> 32];
}

static const float       STAIRS[]  = {-1.0f, 0.5f, 1.0f, -0.25f};
static const staircase_t STAIRCASE = {STAIRS, 4U};

/* Exact waveforms over one period, p in [0, 1) */
static double exact_sine(double p)
{
    return sin(2.0 * PI * p);
}

static double exact_square(double p)
{
    return p < 0.5 ? 1.0 : -1.0;
}

static double exact_triangle(double p)
{
    return p < 0.5 ? 4.0 * p - 1.0 : 3.0 - 4.0 * p;
}

static double exact_sawtooth(double p)
{
    return 2.0 * p - 1.0;
}

static double exact_pulse(double p)
{
    return p < 0.25 ? 1.0 : -1.0;
}

static double exact_staircase(double p)
{
    return STAIRS[(int) (p * 4.0)];
}

/* Interpolates to a triangle, including the wrap from the last sample to the first */
static const float              TABLE_SAMPLES[] = {0.0f, 1.0f, 0.0f, -1.0f};
static const signal_gen_table_t TABLE           = {TABLE_SAMPLES, 4U};

static double exact_table(double p)
{
    return p < 0.25 ? 4.0 * p : p < 0.75 ? 2.0 - 4.0 * p : 4.0 * p - 4.0;
}

static void test_waves(void)
{
    static const signal_gen_pulse_t PULSE = {.duty = 0.25f};
    static const struct
    {
        const char       *name;
        signal_gen_wave_t wave;
        const void       *params;
        double (*exact)(double p);
    } waves[] = {
        {"sine", signal_gen_wave_sine, NULL, exact_sine},
        {"square", signal_gen_wave_square, NULL, exact_square},
        {"triangle", signal_gen_wave_triangle, NULL, exact_triangle},
        {"sawtooth", signal_gen_wave_sawtooth, NULL, exact_sawtooth},
        {"pulse, duty 0.25", signal_gen_wave_pulse, &PULSE, exact_pulse},
        {"table", signal_gen_wave_table, &TABLE, exact_table},
        {"custom staircase", wave_staircase, &STAIRCASE, exact_staircase},
    };

    for (uint32_t w = 0U; w < sizeof(waves) / sizeof(waves[0]); w++)
    {
        signal_gen_config_t cfg = base_config();
        cfg.wave                = waves[w].wave;
        cfg.wave_params         = waves[w].params;
        generate(&cfg, clean, NULL, CHUNK);

        /* Compare against the exact waveform over the whole run (400 s); amplitude,
         * phase and frequency errors would all grow past 1 code */
        double worst = 0.0;
        for (uint32_t i = 0U; i < N; i++)
        {
            double p     = fmod((double) cfg.freq_hz * i / FS, 1.0);
            double ideal = cfg.offset + cfg.amplitude * waves[w].exact(p);
            double err   = fabs((double) clean[i] - ideal);
            worst        = err > worst ? err : worst;
        }
        CHECK(worst <= 1.0, "%s within %.3f codes of the exact waveform over %u samples", waves[w].name, worst, N);
    }
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
    cfg.noise               = SIGNAL_GEN_NOISE_NONE;
    generate(&cfg, clean, noisy, CHUNK);
    CHECK(memcmp(clean, noisy, sizeof(clean)) == 0, "SIGNAL_GEN_NOISE_NONE: noisy equals clean");
}

static void test_clipping(void)
{
    signal_gen_config_t cfg = base_config();
    cfg.offset              = 4000.0f;
    cfg.amplitude           = 0.0f;

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
    signal_gen_t        sg;
    signal_gen_config_t cfg = base_config();
    CHECK(signal_gen_init(&sg, &cfg), "valid settings accepted");

    cfg         = base_config();
    cfg.freq_hz = FS / 2.0f;
    CHECK(!signal_gen_init(&sg, &cfg), "freq = fs/2 rejected");

    cfg       = base_config();
    cfg.fs_hz = 0.0f;
    CHECK(!signal_gen_init(&sg, &cfg), "fs = 0 rejected");

    cfg           = base_config();
    cfg.white_std = -1.0f;
    CHECK(!signal_gen_init(&sg, &cfg), "negative noise level rejected");

    cfg         = base_config();
    cfg.rw_step = -1.0f;
    CHECK(!signal_gen_init(&sg, &cfg), "negative random walk step rejected");

    cfg           = base_config();
    cfg.gm[0].std = 1.0f; /* tc_s stays 0 */
    CHECK(!signal_gen_init(&sg, &cfg), "Gauss-Markov with std > 0 and no correlation time rejected");

    cfg         = base_config();
    cfg.freq_hz = NAN;
    CHECK(!signal_gen_init(&sg, &cfg), "NaN frequency rejected");

    cfg      = base_config();
    cfg.wave = NULL;
    CHECK(!signal_gen_init(&sg, &cfg), "no waveform rejected");
}

int main(void)
{
    test_white_noise();
    test_gauss_markov();
    test_random_walk();
    test_waves();
    test_chunking();
    test_seed();
    test_no_noise();
    test_clipping();
    test_validation();

    printf("\n%s: %d failure(s)\n", failures ? "FAILED" : "OK", failures);
    return failures ? 1 : 0;
}

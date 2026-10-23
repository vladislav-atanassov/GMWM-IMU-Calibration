/**
  ******************************************************************************
  * @file    sensor_emulator.c
  * @brief   A sensor with known noise, built from the DAC and ADC, see
  *          sensor_emulator.h.
  *
  *          TIM6 TRGO triggers DAC1 CH1/CH2 and ADC2 together. All three use
  *          circular DMA over two halves; when an ADC half is full, the DAC
  *          DMA has finished reading the matching DAC half, which is refilled
  *          with the next stretch of signal.
  ******************************************************************************
  */
#include "sensor_emulator.h"

#include "adc.h"
#include "app_config.h"
#include "dac.h"
#include "main.h"
#include "signal_gen.h"
#include "tim.h"

#define HALF_FRAMES 256U                                          /* frames per block */
#define DAC_LEN     (2U * HALF_FRAMES)                            /* samples per DAC channel */
#define ADC_LEN     (2U * HALF_FRAMES * SENSOR_EMULATOR_CHANNELS) /* 2 halves, interleaved */

/* Above about 10 kHz the ADC conversions and the 921600 baud link run out of room */
_Static_assert(EMULATOR_FS_HZ >= 1U && EMULATOR_FS_HZ <= 10000U, "EMULATOR_FS_HZ must be 1..10000 Hz");

/* DMA buffers live in AXI SRAM (.dma_buffer): DMA1 cannot reach DTCM */
static uint16_t dac_clean[DAC_LEN] __attribute__((section(".dma_buffer")));
static uint16_t dac_noisy[DAC_LEN] __attribute__((section(".dma_buffer")));
static uint16_t adc_buf[ADC_LEN] __attribute__((section(".dma_buffer"))); /* clean, noisy, clean, ... */

static volatile uint32_t blocks_done; /* ADC halves completed, counted in the DMA callbacks */
static uint32_t          blocks_taken;
static signal_gen_t      signal_gen;

/* APB1 timers run at 2 x PCLK1 whenever APB1 is divided */
static uint32_t tim6_clock_hz(void)
{
    uint32_t clk = HAL_RCC_GetPCLK1Freq();
    if ((RCC->D2CFGR & RCC_D2CFGR_D2PPRE1) != RCC_APB1_DIV1)
    {
        clk *= 2U;
    }
    return clk;
}

/* Sets TIM6 as close to fs as its clock allows and returns the rate achieved */
static float tim6_set_rate(uint32_t fs)
{
    uint32_t clk   = tim6_clock_hz();
    uint32_t ticks = (clk + fs / 2U) / fs;  /* timer clocks per sample */
    uint32_t psc   = (ticks - 1U) / 65536U; /* smallest prescaler that keeps ARR within 16 bits */
    uint32_t arr   = (ticks + (psc + 1U) / 2U) / (psc + 1U) - 1U;

    /* Overrides the CubeMX values; DAC and ADC are not enabled yet, so the update
   * event this generates triggers nothing */
    htim6.Init.Prescaler = psc;
    htim6.Init.Period    = arr;
    if (HAL_TIM_Base_Init(&htim6) != HAL_OK)
    {
        Error_Handler();
    }
    return (float) clk / ((float) (psc + 1U) * (float) (arr + 1U));
}

static void fill_dac_half(uint32_t half)
{
    signal_gen_fill(&signal_gen, &dac_clean[half * HALF_FRAMES], &dac_noisy[half * HALF_FRAMES], HALF_FRAMES);
}

void sensor_emulator_start(void)
{
    const float               fs_hz = tim6_set_rate(EMULATOR_FS_HZ);
    const signal_gen_config_t cfg   = EMULATOR_SIGNAL_GEN_CONFIG(fs_hz);
    if (!signal_gen_init(&signal_gen, &cfg))
    {
        Error_Handler();
    }

    fill_dac_half(0U);
    fill_dac_half(1U);

    /* Arm all DMA streams first; TIM6 starts last so everything begins on the same tick */
    if (HAL_DAC_Start_DMA(&hdac1, DAC_CHANNEL_1, (uint32_t *) dac_clean, DAC_LEN, DAC_ALIGN_12B_R) != HAL_OK)
    {
        Error_Handler();
    }
    if (HAL_DAC_Start_DMA(&hdac1, DAC_CHANNEL_2, (uint32_t *) dac_noisy, DAC_LEN, DAC_ALIGN_12B_R) != HAL_OK)
    {
        Error_Handler();
    }
    if (HAL_ADC_Start_DMA(&hadc2, (uint32_t *) adc_buf, ADC_LEN) != HAL_OK)
    {
        Error_Handler();
    }
    if (HAL_TIM_Base_Start(&htim6) != HAL_OK)
    {
        Error_Handler();
    }
}

bool sensor_emulator_get_block(sensor_emulator_block_t *block)
{
    uint32_t done = blocks_done;
    if (done == blocks_taken)
    {
        return false;
    }
    blocks_taken = done;

    /* Always the newest block; if the caller fell behind, the skipped ones show
   * up as a gap in seq */
    uint32_t half = (done - 1U) & 1U;
    fill_dac_half(half);

    block->frames   = &adc_buf[half * HALF_FRAMES * SENSOR_EMULATOR_CHANNELS];
    block->n_frames = HALF_FRAMES;
    block->seq      = done - 1U;
    return true;
}

void HAL_ADC_ConvHalfCpltCallback(ADC_HandleTypeDef *hadc)
{
    if (hadc->Instance == ADC2)
    {
        blocks_done++;
    }
}

void HAL_ADC_ConvCpltCallback(ADC_HandleTypeDef *hadc)
{
    if (hadc->Instance == ADC2)
    {
        blocks_done++;
    }
}

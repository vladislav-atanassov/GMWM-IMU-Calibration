# GMWM IMU Calibration

Use the Generalized Method of Wavelet Moments (GMWM) to identify an IMU's stochastic error model from real data. Then turn that model into the noise parameters of a Kalman filter.

Hardware: a NUCLEO-H755ZI-Q (STM32H755) for the step 1 warm-up, then a Seeed Studio XIAO nRF52840 Sense and its LSM6DS3TR-C 6-axis IMU. Firmware in C, analysis in MATLAB.

## Status

Step 1 is done. The board emulates a static MEMS IMU, and from one 19 min recording GMWM recovers the white noise within 0.2% and both Gauss-Markov standard deviations within 5%. The correlation times (14% and 45% low) and the random walk (29% low) are within the normal spread for one recording this long, so the real IMU will need longer or repeated logs. Step 2 is next.

![Controller setup: TIM6 triggers DAC1 and ADC2, DMA moves samples through AXI SRAM, and blocks stream over USART3 and the ST-LINK to the PC](assets/controller-setup.excalidraw.svg)

TIM6 ticks at 1 kHz and triggers both DAC channels and an ADC2 scan of both on the same tick, all inside the chip. Every 256 ticks the CM7 sends one 1036-byte packet over USART3, and the ST-LINK passes it to the PC as a virtual COM port. The diagram is an Excalidraw file: open it in Excalidraw to edit it.

## Steps

1. **Emulated IMU** (done). The DAC generates a constant level and the same level with a known IMU noise model added: white noise, two Gauss-Markov processes, and a random walk, at the levels of an LSM6DS3TR-C gyro. The ADC samples both and streams them to MATLAB, where GMWM has to recover the model.
2. **Stream the IMU** (next). Firmware for the XIAO that reads the LSM6DS3TR-C's raw gyro, accelerometer, and temperature and streams them to the PC over USB.
3. **Real IMU data.** Record long, static IMU logs and fit GMWM models to the gyro and accelerometer.
4. **Kalman calibration.** Turn the fitted model into Kalman filter noise parameters and test the filter.
5. **Compare.** Compare IMUs and calibration methods, such as GMWM against the Allan variance.

## Repository layout

```text
.
├── firmware/
│   └── GMWM-IMU-Calibration/         step 1: STM32CubeMX dual-core CMake project
│       ├── GMWM-IMU-Calibration.ioc  peripheral setup
│       ├── CM7/
│       │   └── App/                  hand-written firmware
│       │       ├── SignalGen/
│       │       │   └── signal_gen_config.h  experiment settings
│       │       ├── SensorEmulator/
│       │       └── Stream/
│       └── CM4/                      second core, unused; waits in Stop mode
├── matlab/
│   ├── wavelets/                     Haar wavelet variance, model wavelet variances, GMWM fit
│   ├── read_packets.m                reads the stream
│   └── emulated_imu.m                fits GMWM to the emulated IMU: recorded or simulated
├── data/                             recordings
├── tools/
│   └── gmwm/                         Python CLI to build, flash, and monitor the board
├── assets/
└── .githooks/
```

## Getting started

You need:

- Arm GNU Toolchain (`arm-none-eabi-gcc`; 14.2 is used here), CMake 3.22 or newer, and Ninja
- STM32CubeProgrammer, to flash through the board's ST-LINK
- Python 3.10 or newer
- MATLAB R2019b or newer, for `serialport`
- clang-format 21 or newer, for the pre-commit hook

Once per clone:

```sh
pip install -e .                       # installs the gmwm CLI and pyserial
git config core.hooksPath .githooks    # turns on the format check
```

Build, flash, and watch the stream:

```sh
python -m gmwm flash-monitor
```

| Command | What it does |
| --- | --- |
| `python -m gmwm build` | Builds both cores with the `Debug` preset |
| `python -m gmwm clean` | Deletes the build folders |
| `python -m gmwm flash` | Builds, then flashes and verifies both cores over SWD |
| `python -m gmwm monitor` | Prints one line per streamed block: clean range, noise mean and std (`-p` port, `-b` baud) |
| `python -m gmwm flash-monitor` | `flash`, then `monitor` |

## Run GMWM

Run `matlab/emulated_imu.m` from `matlab/`. Set `source` at the top:

| `source` | Data | Needs |
| --- | --- | --- |
| `"recording"` | the board recording in `data/emulated_imu.mat` | MATLAB |
| `"sim"` | the same noise, simulated in MATLAB | MATLAB |
| `"board"` | a new 19 min recording from your board, saved to `file` | the board, flashed |

For `"board"`, set `file` to a new name and stop the monitor (the COM port has one owner). Reset the board just before, since the random walk grows from reset, and keep the PC awake, since sleep cuts the stream.

The experiment settings (sample rate, signal, noise processes, seed) are in `firmware/GMWM-IMU-Calibration/CM7/App/SignalGen/signal_gen_config.h`. Change them, then flash again.

## Code style

`.clang-format` applies to `CM7/App/` only, so the CubeMX code stays as generated. With the hook on, a commit that stages unformatted files there is rejected, and the hook prints the command that fixes them. If clang-format is not on your PATH, point the hook at it with `git config hooks.clangFormat <path-to-clang-format>`.

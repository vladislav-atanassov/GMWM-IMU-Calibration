# GMWM IMU Calibration

Use the Generalized Method of Wavelet Moments (GMWM) to identify an IMU's stochastic error model from real data. Then turn that model into the noise  arameters of a Kalman filter, for rocket thrust vector control.

Hardware: NUCLEO-H755ZI-Q (STM32H755) and an IMU (BNO086). Firmware in C using ST's eco system, analysis in MATLAB.

## Steps

1. **Loopback reference.** The DAC generates a clean signal and the same signal with known noise added. The ADC samples both, and the data is streamed to MATLAB.
2. **GMWM on known noise.** Compute the wavelet variance and fit a GMWM model to the loopback data. Check that it recovers the noise that was injected.
3. **Real IMU data.** Record long, static IMU logs and fit GMWM models to the gyro and accelerometer.
4. **Kalman calibration.** Turn the fitted model into Kalman filter noise parameters and test the filter.
5. **Compare.** Compare IMUs and calibration methods, such as GMWM against the Allan variance.

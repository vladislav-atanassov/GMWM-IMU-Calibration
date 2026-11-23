# E05: Predict stationary gyro drift with a board-specific noise model

**Conclusion:** The measured drift, predicted uncertainty and predictive scores are in [RESULTS.md](../../RESULTS.md).

## Question

Does the GMWM profile fitted to `imu_static_01` predict stationary gyro angle drift on
`imu_static_02` better than a white-noise model using the datasheet rate noise density?

## Setup

- Use hours 4–5 of `imu_static_02`, at 104 Hz, as a separate recording for evaluation.
  This hour was previously inspected for stationarity in E03. All profile parameters come from 01.
- For each of 1, 10, 60 and 300 seconds, divide the hour into contiguous, non-overlapping trials.
  In each trial estimate one bias from the preceding 60 seconds and integrate the bias-subtracted
  rate for the forecast period. Both methods use the same bias and predict zero mean drift.
  Trials at different horizons can reuse samples.
- The baseline uses 5 mdps/√Hz of white noise on every axis.
  [ST LSM6DS3TR-C datasheet, Table 3](https://www.st.com/resource/en/datasheet/lsm6ds3tr-c.pdf#page=21)
- The board-specific profile uses E01 on X and E04 on Y and Z. On Y and Z the fast
  Gauss–Markov component is represented by white noise with the same low-frequency power.
  The predicted variance includes the uncertainty of the startup bias and its covariance
  with subsequent samples under each model. This tests open-loop uncertainty on stationary data.

## Outputs

Run with `python experiments/run.py E05`. [drift.csv](out/drift.csv) compares observed
RMS endpoint drift and predicted standard deviations, empirical coverage of nominal 95%
prediction intervals, and the mean paired Gaussian log-score gain in nats per trial.
Positive gain favors GMWM. [drift_trials.csv](out/drift_trials.csv) lists every startup
bias and signed endpoint drift. The recorded temperature and vibration conditions
apply to a single board and session.

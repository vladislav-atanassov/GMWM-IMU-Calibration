# E06: Does GMWM reduce gyro angle error after bias correction?

**Conclusion:** The measured endpoint errors and baseline comparisons are reported in [RESULTS.md](../../RESULTS.md).

## Question

Does the GMWM noise profile improve the actual angle estimate on a stationary bench replay
when the estimator gets only intermittent zero-rate references?

## Setup

- Replay hours 6.55–7.5 of `imu_static_02` at 104 Hz. This quiet stretch is separate from E05's
  replay window and from the recording used to fit the noise profile. Treat the stationary
  board's rotation relative to the bench as zero.
- Give every method the first 60 seconds for startup, then alternate 10 seconds of known
  stationarity and 10, 60, or 300 seconds with no reference. Each horizon starts its own
  replay, so trials at different horizons can reuse samples.
- Compare a fixed startup mean, a constant-bias estimate using the mean of all available
  reference samples, the mean of the latest 10-second reference, and a GMWM Kalman bias
  tracker. The constant-bias mean is the estimate for the datasheet white-noise model
  with an unknown constant offset. The GMWM tracker uses E01's X model and E04's Y and Z
  models, with the sub-sample Gauss–Markov terms folded into effective white noise as in E05.
- All four methods integrate the measured gyro rate after subtracting their predicted bias.
  Scored samples contribute to this integral and never update any bias estimate. The GMWM
  model propagates bias through the scored windows and resumes updating when the next
  reference becomes available. It starts from a broad 1 °/s standard deviation for the
  persistent bias and stationary variances for the Gauss–Markov terms.

## Outputs

Run from the repository root with `python experiments/run.py E06`. [correction.csv](out/correction.csv)
reports RMS endpoint angle error and GMWM's reduction versus the lowest-RMSE baseline for each
axis and horizon. [correction_trials.csv](out/correction_trials.csv) gives the four signed
errors for every trial. The results describe this board on a static bench with simulated
reference availability. A dynamic test with an independent motion reference would address
correction during real movement.

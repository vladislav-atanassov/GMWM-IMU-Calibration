# E07: Repeat the gyro correction test on one longer window

**Conclusion:** See the measured endpoint errors and baseline comparisons in [RESULTS.md](../../RESULTS.md).

## Question

Does the E06 result repeat on the longest continuous stretch of recording 02 that
passes the same conservative accelerometer screen?

## Window selection

- Scan the 2.0–7.5 h temperature plateau of `imu_static_02` in one-second bins.
  For each bin, combine the three accelerometer sample variances as
  `sqrt(var(ax) + var(ay) + var(az))`. Keep the longest span where every bin
  stays at or below 1.5 mg. The screen uses accelerometer samples independently
  of the gyro correction errors.
- The longest span was 03:27:43–05:01:02 from the first packet. Round inward to
  **03:27:44–05:01:00** to align with whole stream packets and one-second bins.
  This leaves 93 min 16 s and 17 complete five-minute trials.
- This window is disjoint from E06. It includes the 4–5 h window previously
  used for E03 and E05. The bias tracker parameters still come from recording 01.

## Replay

Reuse E06's MATLAB entry script, profile, baselines, 60-second startup and
10-second reference updates. Score the same 10, 60 and 300 s horizons using
only the chosen window. Run with `python experiments/run.py E07`.

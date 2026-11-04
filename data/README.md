# Data

Every recording the experiments use. `experiments/run.py` finds a dataset in the table below
and checks the file against its SHA-256 before it runs anything, so a result always names
the exact bytes it came from.

The logs are not in git (`*.bin` is ignored): a day-long log is over GitHub's 100 MB file
limit. Ask the author for a copy.

| Dataset | File | Size | SHA-256 | Recorded | Duration | Settings |
| --- | --- | --- | --- | --- | --- | --- |
| imu_static_01 | imu_static_01.bin | 54,154,000 B | 0654d130f12efd50e960e3fb1c021c876a47f3224b1ea98a5d4ff90737831bc0 | 2026-11-04, about 09:52 to 21:27 | 11.57 h, 135,385 blocks, 0 lost | 104 Hz, ±125 dps, ±2 g |

`emulated_imu.mat` is in git: the step 1 recording of the emulated IMU (see the main README).

## imu_static_01

The first static log of the XIAO's LSM6DS3TR-C, recorded with `python -m gmwm record`
from the streaming firmware at d8e0894. The board lay still
on a desk. The start time is inferred from the file's last write and the log's length; the
log itself holds no clock time.

What it shows, from a check of the whole log:

- **Use 2.8 h to 9.5 h.** Before 2.8 h the temperature still rises (23.6 to 24.2 °C) and
  vibration bursts are frequent. From 9.5 h it warms again (to 25.2 °C) and the bursts
  return. In between it holds 24.2 ± 0.07 °C.
- **Vibration bursts:** ringing up to ±4 dps, mostly in gx and ay, with a 6 to 13 Hz band.
  Something knocking the desk, not the sensor.
- **A tone near 34 Hz in gx and ay the whole time,** hopping between fixed frequencies
  (32.4 to 37.3 Hz) for hours at a time: likely a motor or fan nearby. It inflates gx's
  finest wavelet scales even in the stable window.
- **The board shifts during strong bursts:** az steps 0.9 mg at 11.15 h, a 0.05° tilt.
  Through the stable window az still creeps about 1.1 mg/h, so the accelerometer needs
  a drift term or detrending.
- **gz bias follows temperature** at about 15 mdps/°C (r = 0.90 over the last 1.5 h).

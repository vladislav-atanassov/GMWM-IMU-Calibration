# Data

Every recording the experiments use. `experiments/run.py` finds a dataset in the table below
and checks the file against its SHA-256 before it runs anything, so a result always names
the exact bytes it came from.

The logs are not in git (`*.bin` is ignored): a day-long log is over GitHub's 100 MB file
limit. Ask the author for a copy.

| Dataset | File | Size | SHA-256 | Recorded | Duration | Settings |
| --- | --- | --- | --- | --- | --- | --- |
| imu_static_01 | imu_static_01.bin | 54,154,000 B | 0654d130f12efd50e960e3fb1c021c876a47f3224b1ea98a5d4ff90737831bc0 | 2026-11-04, about 09:52 to 21:27 | 11.57 h, 135,385 blocks, 0 lost | 104 Hz, ±125 dps, ±2 g |
| imu_static_02 | imu_static_02.bin | 37,536,400 B | 46bd5d8e542cdb13a6303bf24e4770f7614bfc99c23e6311ab2777ec237e8498 | 2026-11-20, ended about 18:10 | 8.02 h, 93,841 blocks, 0 lost | 104 Hz, ±125 dps, ±2 g |

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

## imu_static_02

- **4 to 5 h** is a quiet, contiguous window. The IMU temperature was
  28.36 ± 0.03 °C (one standard deviation). The three-axis gyro RMS
  within one-second bins was about 0.041 dps typically and never exceeded 0.054 dps.
- Between 2 and 7.5 h the temperature was fairly steady. The largest motion events
  were at 3:27:42 and 6:27:27, both with a step on the Y accelerometer. Motion bursts
  returned in the final 16 min. All times are measured from the first logged packet.
- Narrowband peaks persist in the quiet window. The strongest are around 17.5 Hz
  on gx and ay, and 42 Hz on gy and az. The 34 Hz peak on gx is also visible.

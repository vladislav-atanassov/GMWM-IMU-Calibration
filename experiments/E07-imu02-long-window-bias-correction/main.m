% Use E06's recorded procedure with one longer, separately screened window.
cfg = exp_config();
d = exp_data();
assert(d.lost == 0 && d.fs == cfg.sample_rate_hz && mod(size(d.accel, 1), d.fs) == 0, ...
    "Expected contiguous whole seconds at the configured sample rate");
bins = reshape(d.accel, d.fs, [], 3);
motionMg = 1000 * sqrt(sum(var(bins, 0, 1), 3));
peakMotionMg = max(motionMg);
assert(peakMotionMg <= cfg.motion_limit_mg, "Window failed the accelerometer motion screen");
fprintf("Single window %s s, %.2f minutes, peak within-second acceleration RMS %.3f mg\n", ...
    d.window_s, size(d.accel, 1) / d.fs / 60, peakMotionMg);

% Pin the saved fits as well as E06's entry script in this run's input record.
assert(isfile(exp_path("experiments/E01-imu01-haar-gmwm/out/params.csv")));
assert(isfile(exp_path("experiments/E04-imu01-full-gmwm/out/params.csv")));
run(exp_path("experiments/E06-imu02-gyro-bias-correction/main.m"));

% The reused script labels its chart E06. Label the E07 chart before publication.
title(tiles, "E07 | Stationary gyro bias correction on one screened window", Interpreter="none");
exp_figure(fig, "gyro_correction");

% Look over a log from `python -m gmwm record` before fitting it: the gyro,
% accelerometer, and temperature against time, and each axis's Haar wavelet
% variance. Run from matlab/.

file = "../data/imu_static_01.bin";

% The part of the log to keep [s]; [0 inf] keeps it all. In imu_static_01, before
% 2.8 h the temperature still settles and vibration bursts are frequent, and
% after 9.5 h it warms again and the bursts return
window = [2.8 9.5] * 3600;

addpath("wavelets");
imu = read_imu_log(file, window);
N   = size(imu.gyro, 1);
fprintf("%s: %d samples, %.2f h from %.2f h at %g Hz, %d blocks lost, %.2f..%.2f degC\n", file, N, ...
        N / imu.fs / 3600, imu.t0 / 3600, imu.fs, imu.lost, min(imu.temp), max(imu.temp));

% Times are since the start of the log, so they match the full recording
t = (imu.t0 + (0:N-1)' / imu.fs) / 60;
figure;
tiledlayout(3, 1);
nexttile;
plot(t, imu.gyro);
ylabel("gyro [dps]");
legend("x", "y", "z");
title(file, "Interpreter", "none");
nexttile;
plot(t, imu.accel - mean(imu.accel));
ylabel("accel - mean [g]");
nexttile;
plot((imu.t0 + imu.temp_k / imu.fs) / 60, imu.temp);
ylabel("temperature [degC]");
xlabel("time [min]");

% The wavelet variance against tau in seconds
J = floor(log2(N)) - 2;
units = struct("gyro", "dps", "accel", "g");
figure;
tiledlayout(1, 2);
for sensor = ["gyro" "accel"]
    nexttile;
    hold on;
    for axis = 1:3
        [nu2, tau] = haar_wvar(imu.(sensor)(:, axis), J);
        plot(tau / imu.fs, nu2, "o-", "DisplayName", char('w' + axis)); % x y z
    end
    set(gca, "XScale", "log", "YScale", "log");
    grid on;
    legend("Location", "southwest");
    xlabel("\tau [s]");
    ylabel("\nu^2 [" + units.(sensor) + "^2]");
    title(sensor + " wavelet variance");
end

% Step 1: check that GMWM recovers the IMU noise model set in
% signal_gen_config.h. Run from matlab/. Pick the data with source:
%   "recording"  fit the board recording in file
%   "sim"        simulate the same noise here; no board needed
%   "board"      record 19 min from your board into a new file, then fit it

source = "recording";
file   = "../data/emulated_imu.mat";
port   = "COM4"; % for "board"

addpath("wavelets");
fs   = 1000;
secs = 1124; % 3 h of 104 Hz IMU samples, replayed at 1 kHz

% As set in signal_gen_config.h, in DAC codes: white noise std, GM 1 tc [s] and std,
% GM 2 tc [s] and std, random walk step
injected = [256, 0.37, 16, 8.3, 15, 0.07];

switch source
    case "recording"
        load(file, "clean", "noisy", "fs", "injected"); % the settings it was recorded with
    case "sim"
        noisy = simulate(injected, fs, secs * fs);
        clean = [];
    case "board"
        assert(~isfile(file), "%s exists: set file to a new name", file);
        packets = read_packets(port, ceil(secs * fs / 256)); % 256 samples per packet
        assert(all(diff([packets.seq]) == 1), "Lost packets: the record has gaps");
        samples = double(typecast([packets.payload], "uint16")); % [clean, noisy] pairs
        clean = samples(1:2:end);
        noisy = samples(2:2:end);
        save(file, "clean", "noisy", "fs", "injected");
end

J = floor(log2(numel(noisy))) - 2;
[nu2, tau, v] = haar_wvar(noisy, J);
types = ["WN" "AR1" "AR1" "RW"];
p = gmwm_fit(nu2, tau, v, types, gmwm_start(nu2, tau, v, types));
estimated = from_params(p, fs);

names = ["white noise std", "GM 1 tc [s]", "GM 1 std", "GM 2 tc [s]", "GM 2 std", "random walk step"];
fprintf("%-17s %9s %9s %8s\n", "DAC codes", "injected", "estimated", "error");
for k = 1:6
    fprintf("%-17s %9.3g %9.3g %+7.1f%%\n", names(k), injected(k), estimated(k), 100 * (estimated(k) / injected(k) - 1));
end

figure;
hold on;
t2 = unique(2 * round(2.^(0:0.05:J-1)))'; % even scales: the AR1 lag sum needs whole samples
parts = {"WN", p(1), [0.47 0.67 0.19], "white noise";
         "AR1", p(2:3), [0.93 0.69 0.13], "Gauss-Markov 1";
         "AR1", p(4:5), [0.30 0.75 0.93], "Gauss-Markov 2";
         "RW", p(6), [0.85 0.35 0.75], "random walk"};
for k = 1:4
    plot(t2, wv_theory(t2, parts{k, 1}, parts{k, 2}), "--", "Color", parts{k, 3}, "LineWidth", 1.2, "DisplayName", parts{k, 4});
end
plot(t2, wv_theory(t2, types, p), "Color", [0 0.45 0.74], "LineWidth", 2, "DisplayName", "GMWM fit");
plot(tau, nu2, "o", "Color", [0.85 0.33 0.10], "MarkerFaceColor", [0.85 0.33 0.10], "DisplayName", "noisy channel");
if ~isempty(clean)
    plot(tau, haar_wvar(clean, J), "o-", "Color", [0.65 0.65 0.65], "DisplayName", "clean channel: the DAC and ADC alone");
end
set(gca, "XScale", "log", "YScale", "log");
grid on;
legend("Location", "southwest");
xlabel("\tau [samples]");
ylabel("\nu^2 [ADC codes^2]");
title("Emulated static IMU (" + source + "): wavelet variance and GMWM fit");

% The noise of signal_gen.c in ADC codes: rounded to DAC codes like the DAC,
% then x16 (1 DAC code = 16 ADC codes). The DAC and ADC add nothing here
function noisy = simulate(injected, fs, n)
rng(1); % the same simulation every run
x = injected(1) * randn(n, 1) ...
    + gauss_markov(injected(2), injected(3), fs, n) ...
    + gauss_markov(injected(4), injected(5), fs, n) ...
    + [0; cumsum(injected(6) * randn(n - 1, 1))];
noisy = 16 * round(2048 + x);
end

% x[k+1] = phi x[k] + std sqrt(1 - phi^2) e[k], started stationary like signal_gen.c
function x = gauss_markov(tc, s, fs, n)
phi = exp(-1 / (tc * fs));
x   = filter(1, [1, -phi], s * sqrt(1 - phi^2) * randn(n, 1), phi * s * randn);
end

% p in ADC codes to the layout of injected (1 DAC code = 16 ADC codes), faster GM first
function q = from_params(p, fs)
phi    = p([2 4]);
tc     = -1 ./ log(phi) / fs;
s      = sqrt(p([3 5]) ./ (1 - phi.^2)) / 16;
[~, i] = sort(tc);
q      = [sqrt(p(1)) / 16, tc(i(1)), s(i(1)), tc(i(2)), s(i(2)), sqrt(p(6)) / 16];
end

% Record a short static log from the XIAO and look at its noise: each axis
% against time, its histogram, and its Haar wavelet variance next to the
% datasheet's white noise. Run from matlab/ with the board streaming, lying
% still, and its port free (close gmwm monitor). Set file to plot a log from
% `python -m gmwm record` instead.

port = "COM12";
secs = 120; % how long to record
file = "";  % e.g. "../data/imu_static_01.bin"; empty records from port

addpath("wavelets");
if file == ""
    fprintf("Recording %d s from %s...\n", secs, port);
    packets = read_packets(port, ceil(secs * 104 / 32)); % 32 samples per packet at the nominal 104 Hz
    bytes = cell(1, numel(packets));
    for k = 1:numel(packets)
        p = packets(k);
        bytes{k} = [typecast(uint32(0xC0DEC0DE), "uint8"), typecast(uint16([p.source, numel(p.payload)]), "uint8"), ...
                    typecast(uint32(p.seq), "uint8"), p.payload(:).'];
    end
    imu   = read_imu_log([bytes{:}]);
    label = sprintf("%s, %d s recorded now", port, secs);
else
    imu   = read_imu_log(file);
    label = file;
end

N = size(imu.gyro, 1);
t = (0:N-1)' / imu.fs;
J = floor(log2(N)) - 2;
colors = [0 0.45 0.74; 0.85 0.33 0.10; 0.47 0.67 0.19]; % x y z
axes_names = ["x" "y" "z"];

% Datasheet Table 3, typical, high-performance mode. White noise of one-sided density D
% has Haar wavelet variance D^2 / (2 T) at T seconds
sensors = struct("field", {"gyro", "accel"}, "unit", {"mdps", "mg"}, "density", {5, 0.090}, ...
                 "density_unit", {"mdps/\surdHz", "mg/\surdHz"});

fig = figure("Position", [80 80 1500 820]);
tl  = tiledlayout(2, 3, "TileSpacing", "compact", "Padding", "compact");
fprintf("%-6s %-4s %10s %22s\n", "", "axis", "std", "density at tau = 1 s");
for s = sensors
    x    = 1000 * (imu.(s.field) - mean(imu.(s.field))); % mdps or mg
    code = 1000 * imu.(s.field + "_scale");

    nexttile;
    hold on;
    for a = 1:3
        plot(t, x(:, a), "Color", colors(a, :), "LineWidth", 0.5, ...
             "DisplayName", sprintf("%s  std %.3g %s", axes_names(a), std(x(:, a)), s.unit));
    end
    grid on;
    xlim([0 t(end)]);
    legend("Location", "northeast");
    xlabel("time [s]");
    ylabel(s.field + " - mean [" + s.unit + "]");
    title(s.field + ": noise against time");

    % One bin per code: the samples are quantized, so other widths make a comb
    nexttile;
    hold on;
    for a = 1:3
        histogram(x(:, a), "BinWidth", code, "Normalization", "pdf", "DisplayStyle", "stairs", ...
                  "EdgeColor", colors(a, :), "LineWidth", 1.2, "DisplayName", axes_names(a));
    end
    xs = linspace(-4, 4, 200) * max(std(x));
    for a = 1:3
        sd = std(x(:, a));
        plot(xs, exp(-xs.^2 / (2 * sd^2)) / (sd * sqrt(2 * pi)), "--", "Color", colors(a, :), ...
             "HandleVisibility", "off");
    end
    grid on;
    xlim(xs([1 end]));
    legend("Location", "northeast");
    xlabel(s.field + " - mean [" + s.unit + "]  (1 code = " + sprintf("%.3g", code) + " " + s.unit + ")");
    ylabel("probability density");
    title(s.field + ": histogram, Gaussian of the same std dashed");

    nexttile;
    hold on;
    for a = 1:3
        [nu2, tau] = haar_wvar(x(:, a), J);
        T = tau / imu.fs;
        plot(T, nu2, "o-", "Color", colors(a, :), "MarkerFaceColor", colors(a, :), "MarkerSize", 4, ...
             "DisplayName", axes_names(a));
        [~, j] = min(abs(log(T)));
        fprintf("%-6s %-4s %7.3g %s %13.3g %s/sqrt(Hz)\n", s.field, axes_names(a), std(x(:, a)), s.unit, ...
                sqrt(2 * T(j) * nu2(j)), s.unit);
    end
    T = tau / imu.fs;
    plot(T, s.density^2 ./ (2 * T), "k--", "LineWidth", 1.2, ...
         "DisplayName", sprintf("datasheet white noise, %.3g %s", s.density, s.density_unit));
    set(gca, "XScale", "log", "YScale", "log");
    grid on;
    legend("Location", "southwest");
    xlabel("\tau [s]");
    ylabel("\nu^2 [" + s.unit + "^2]");
    title(s.field + ": Haar wavelet variance");
end
lost = "";
if imu.lost > 0
    lost = sprintf(", %d BLOCKS LOST", imu.lost);
end
title(tl, sprintf("LSM6DS3TR-C noise: %s, %d samples at %g Hz, %.2f..%.2f degC%s", label, N, imu.fs, ...
                  min(imu.temp), max(imu.temp), lost), "Interpreter", "none");

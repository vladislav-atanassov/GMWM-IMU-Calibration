% E01: GMWM on the Haar wavelet variance with this repo's step 1 code
% (matlab/wavelets), fitted to each axis of the sensor in config.json.
% Run from the repository root with: python experiments/run.py E01

addpath(exp_path("matlab/wavelets"));
cfg = exp_config();
d   = exp_data();
assert(d.lost == 0, "Blocks were lost in the window, and the samples run straight across gaps");

model = strjoin(string(cfg.model).', " + ");
types = string(cfg.model).';
types(types == "GM") = "AR1"; % wv_theory's name: a sampled Gauss-Markov process is an AR(1)
names = ["x" "y" "z"];

x = 1000 * d.(cfg.sensor); % mdps
N = size(x, 1);
J = floor(log2(N)) - 2;    % as in step 1: the coarsest scales hold too few independent blocks
fprintf("%s, %s s: %d samples at %g Hz, %d scales up to %.0f s\n", d.dataset, d.window_s, N, d.fs, J, 2^J / d.fs);

params = table();
wv     = table();
fit    = table();
fig = figure("Position", [80 80 1500 520]);
tl  = tiledlayout(1, 3, "TileSpacing", "compact", "Padding", "compact");
for a = 1:3
    tic;
    [nu2, tau, v] = haar_wvar(x(:, a), J);
    [p, obj] = gmwm_fit(nu2, tau, v, types, gmwm_start(nu2, tau, v, types));
    secs = toc;

    % 95% interval of each estimate: chi-square with the degrees of freedom its variance implies
    eta = 2 * nu2.^2 ./ v;
    lo  = eta .* nu2 ./ chi2inv(0.975, eta);
    hi  = eta .* nu2 ./ chi2inv(0.025, eta);

    [P, parts] = physical(p, types, d.fs);
    n = height(P);
    params = [params; table(repmat(string(cfg.sensor), n, 1), repmat(names(a), n, 1), P.term, P.parameter, ...
                            P.value, P.unit, nan(n, 1), nan(n, 1), 'VariableNames', ...
                            ["sensor" "axis" "term" "parameter" "value" "unit" "ci_low" "ci_high"])]; %#ok<AGROW>
    wv = [wv; table(repmat(string(cfg.sensor), J, 1), repmat(names(a), J, 1), tau / d.fs, nu2, lo, hi, ...
                    wv_theory(tau, types, p), 'VariableNames', ...
                    ["sensor" "axis" "scale_s" "nu2" "ci_low" "ci_high" "nu2_model"])]; %#ok<AGROW>
    fit = [fit; table(string(cfg.sensor), names(a), obj, J, secs, 'VariableNames', ...
                      ["sensor" "axis" "objective" "scales" "seconds"])]; %#ok<AGROW>

    fprintf("\n%s %s: objective %.4g, %.0f s\n", cfg.sensor, names(a), obj, secs);
    for r = 1:n
        fprintf("  %-4s %-8s %10.4g %s\n", P.term(r), P.parameter(r), P.value(r), P.unit(r));
    end

    nexttile;
    hold on;
    t2 = 2.^(1:0.05:J)'; % wv_theory takes any scale, so the curves can be smooth
    colors = ["#1baf7a" "#eda100" "#e87ba4" "#6250d6"];
    for c = 1:numel(parts)
        plot(t2 / d.fs, wv_theory(t2, parts(c).type, parts(c).p), "--", "Color", colors(mod(c - 1, numel(colors)) + 1), "LineWidth", 1.2, ...
             "DisplayName", parts(c).label);
    end
    plot(t2 / d.fs, wv_theory(t2, types, p), "Color", "#2a78d6", "LineWidth", 2, "DisplayName", "GMWM fit");
    errorbar(tau / d.fs, nu2, nu2 - lo, hi - nu2, "o", "Color", "#52514e", "MarkerFaceColor", "#52514e", ...
             "MarkerSize", 4, "DisplayName", "Haar WV, 95% interval");
    set(gca, "XScale", "log", "YScale", "log");
    ylim([min(lo) / 10, max(hi) * 10]); % the data's range: a vanishing term would stretch the axis
    grid on;
    xlabel("scale \tau [s]");
    ylabel("\nu^2 [mdps^2]");
    title("g" + names(a));
    if a == 1
        legend("Location", "southwest");
    end
end
title(tl, sprintf("%s: %s, %s s, %s", getenv("EXP_ID"), d.dataset, d.window_s, model), "Interpreter", "none");

exp_write("params.csv", params);
exp_write("wv.csv", wv);
exp_write("fit.csv", fit);
exp_figure(fig, cfg.sensor + "_wv");

% p per sample [mdps^2] to the units in experiments/README.md, Gauss-Markov terms by increasing
% correlation time. parts holds each term's own type and per-sample parameters, for plotting
function [P, parts] = physical(p, types, fs)
wn = [];
rw = [];
gm = zeros(0, 4); % tc [s], std [mdps], phi, v^2
k = 1;
for type = types
    switch type
        case "WN"
            wn = p(k);
        case "RW"
            rw = p(k);
        case "AR1"
            phi = p(k);
            gm(end+1, :) = [-1 / (fs * log(phi)), sqrt(p(k+1) / (1 - phi^2)), phi, p(k+1)]; %#ok<AGROW>
            k = k + 1;
        otherwise
            error("No physical units defined for %s yet", type);
    end
    k = k + 1;
end
gm = sortrows(gm, 1);

term = strings(0, 1);
parameter = strings(0, 1);
value = zeros(0, 1);
unit = strings(0, 1);
parts = struct("type", {}, "p", {}, "label", {});
if ~isempty(wn)
    % One-sided density D: white noise has Haar WV D^2 / (2 T) at T seconds, as in matlab/imu_noise.m
    term(end+1) = "WN"; parameter(end+1) = "density"; value(end+1) = sqrt(2 * wn / fs); unit(end+1) = "mdps/sqrt(Hz)";
    parts(end+1) = struct("type", "WN", "p", wn, "label", "white noise");
end
for g = 1:size(gm, 1)
    name = "GM" + g;
    term(end+1:end+2) = name;
    parameter(end+1:end+2) = ["tc" "std"];
    value(end+1:end+2) = gm(g, 1:2);
    unit(end+1:end+2) = ["s" "mdps"];
    parts(end+1) = struct("type", "AR1", "p", gm(g, 3:4), "label", sprintf("%s, tc %.3g s", name, gm(g, 1))); %#ok<AGROW>
end
if ~isempty(rw)
    % K: the walk's standard deviation grows as K sqrt(t)
    term(end+1) = "RW"; parameter(end+1) = "K"; value(end+1) = sqrt(rw * fs); unit(end+1) = "mdps/sqrt(s)";
    parts(end+1) = struct("type", "RW", "p", rw, "label", "random walk");
end
P = table(term(:), parameter(:), value(:), unit(:), 'VariableNames', ["term" "parameter" "value" "unit"]);
end

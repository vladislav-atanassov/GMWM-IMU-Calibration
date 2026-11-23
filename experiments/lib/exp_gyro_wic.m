function exp_gyro_wic()
% Full-covariance GMWM and WIC for the static gyro recordings.
cfg = exp_config();
d = exp_data();
assert(d.lost == 0, "Blocks were lost in the window, and the samples run straight across gaps");
assert(string(cfg.sensor) == "gyro", "This experiment reports gyro units");
axesNames = ["x", "y", "z"];
sensor = string(cfg.sensor);
x = 1000 * d.gyro; % mdps
N = size(x, 1);
J = floor(log2(N)) - 2;
fprintf("%s, %s s: %d samples at %g Hz, %d scales up to %.0f s\n", d.dataset, d.window_s, N, d.fs, J, 2^J / d.fs);

models = cell(1, 2 * (cfg.max_gm_terms + 1));
labels = strings(size(models));
for k = 0:cfg.max_gm_terms
    models{2*k + 1} = ["WN", repmat("AR1", 1, k)];
    models{2*k + 2} = [models{2*k + 1}, "RW"];
end
for m = 1:numel(models)
    labels(m) = strjoin(replace(models{m}, "AR1", "GM"), " + ");
end

if cfg.workers > 0 && isempty(gcp("nocreate"))
    parpool("Processes", cfg.workers);
end

params = table();
wv = table();
fit = table();
scores = table();
covariance = table();
fig = figure("Position", [80 80 1500 520]);
tiles = tiledlayout(1, 3, "TileSpacing", "compact", "Padding", "compact");
for a = 1:3
    axisName = axesNames(a);
    timer = tic;
    [nu2, tau, v] = haar_wvar(x(:, a), J);
    selected = gmwm_select(nu2, tau, v, models, N, cfg.bootstrap, cfg.seed + a - 1, cfg.workers);
    best = selected.best;
    types = models{best};
    p = selected.fits{best};
    [P, parts] = gmwm_physical(p, types, d.fs, gmwm_log_cov(tau, selected.V, types, p));

    eta = 2 * nu2.^2 ./ v;
    lo = eta .* nu2 ./ chi2inv(0.975, eta);
    hi = eta .* nu2 ./ chi2inv(0.025, eta);
    scales = tau / d.fs;
    params = [params; table(repmat(sensor, height(P), 1), repmat(axisName, height(P), 1), ...
        P.term, P.parameter, P.value, P.unit, P.ci_low, P.ci_high, ...
        'VariableNames', ["sensor" "axis" "term" "parameter" "value" "unit" "ci_low" "ci_high"])]; %#ok<AGROW>
    wv = [wv; table(repmat(sensor, J, 1), repmat(axisName, J, 1), scales, nu2, lo, hi, ...
        wv_theory(tau, types, p), ...
        'VariableNames', ["sensor" "axis" "scale_s" "nu2" "ci_low" "ci_high" "nu2_model"])]; %#ok<AGROW>
    fit = [fit; table(sensor, axisName, selected.loss(best), J, toc(timer), ...
        'VariableNames', ["sensor" "axis" "objective" "scales" "seconds"])]; %#ok<AGROW>
    [~, order] = sort(selected.wic);
    delta = selected.wic - selected.wic(best);
    m = numel(models);
    scores = [scores; table(repmat(sensor, m, 1), repmat(axisName, m, 1), labels(order).', ...
        selected.loss(order).', selected.optimism(order).', selected.wic(order).', ...
        delta(order).', selected.deltaSE(order).', ...
        'VariableNames', ["sensor" "axis" "model" "objective" "optimism" "wic" "delta_wic" "delta_mc_se"])]; %#ok<AGROW>
    [s1, s2] = ndgrid(scales, scales);
    covariance = [covariance; table(repmat(sensor, J^2, 1), repmat(axisName, J^2, 1), ...
        s1(:), s2(:), selected.V(:), ...
        'VariableNames', ["sensor" "axis" "scale_s" "scale2_s" "covariance"])]; %#ok<AGROW>

    fprintf("g%s: %s, WIC %.4g; runner-up %s, delta %.4g (MC SE %.3g)\n", axisName, labels(best), ...
        selected.wic(best), labels(order(2)), delta(order(2)), selected.deltaSE(order(2)));
    panel(axisName, labels(best), scales, nu2, lo, hi, types, p, parts, d.fs);
end
title(tiles, sprintf("%s: %s, %s s, full covariance and WIC", getenv("EXP_ID"), d.dataset, d.window_s), "Interpreter", "none");
exp_write("params.csv", params);
exp_write("wv.csv", wv);
exp_write("fit.csv", fit);
exp_write("wic.csv", scores);
exp_write("wv_cov.csv", covariance);
exp_figure(fig, sensor + "_wv");
end

function panel(axisName, model, scales, nu2, lo, hi, types, p, parts, fs)
nexttile;
hold on;
t = 2.^linspace(1, numel(scales), 300).';
colors = ["#1baf7a", "#eda100", "#e87ba4", "#6250d6"];
for k = 1:numel(parts)
    plot(t / fs, wv_theory(t, parts(k).type, parts(k).p), "--", "Color", colors(k), ...
        "DisplayName", parts(k).label);
end
plot(t / fs, wv_theory(t, types, p), "Color", "#2a78d6", "LineWidth", 2, "DisplayName", "Selected fit");
errorbar(scales, nu2, nu2 - lo, hi - nu2, "o", "Color", "#52514e", "MarkerFaceColor", "#52514e", ...
    "MarkerSize", 4, "DisplayName", "Haar WV, 95% interval");
set(gca, "XScale", "log", "YScale", "log");
ylim([min(lo) / 10, max(hi) * 10]);
grid on;
xlabel("Scale [s]");
ylabel("Wavelet variance [mdps^2]");
title("g" + axisName + " | " + model);
if axisName == "x"
    legend("Location", "southwest");
end
end

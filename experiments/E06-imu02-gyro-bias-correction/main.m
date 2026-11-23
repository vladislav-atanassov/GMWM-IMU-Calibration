% Assess actual gyro correction using only causal, intermittent zero-rate references.
cfg = exp_config();
d = exp_data();
fs = d.fs;
assert(d.lost == 0 && fs == cfg.sample_rate_hz, "Expected gap-free data at the configured sample rate");
assert(string(cfg.sensor) == "gyro", "This experiment uses gyro rate");
nStartup = sample_count(cfg.startup_s, fs);
nUpdate = sample_count(cfg.update_s, fs);
axesNames = ["x", "y", "z"];
sensor = string(cfg.sensor);
e01 = readtable(exp_path("experiments/E01-imu01-haar-gmwm/out/params.csv"), TextType="string");
e04 = readtable(exp_path("experiments/E04-imu01-full-gmwm/out/params.csv"), TextType="string");
models = [profile(e01, "x", fs), profile(e04, "y", fs), profile(e04, "z", fs)];

summary = table();
trials = table();
for horizon = cfg.horizons_s(:).'
    nScore = sample_count(horizon, fs);
    period = nUpdate + nScore;
    n = floor((size(d.gyro, 1) - nStartup) / period);
    assert(n >= 1, "No complete reference and scoring windows for this horizon");
    start = nStartup + nUpdate + (0:n-1).' * period;
    for a = 1:3
        rate = 1000 * (d.gyro(:, a) - d.gyro(1, a)); % center on a startup sample, in mdps
        errors = replay(rate, nStartup, nUpdate, nScore, n, models(a), fs, cfg.initial_bias_sd_dps);
        rmse = sqrt(mean(errors.^2, 1));
        baselines = ["startup" "white" "recent"];
        [best, idx] = min(rmse(1:3));
        reduction = (best - rmse(4)) / best;
        summary = [summary; table(sensor, axesNames(a), horizon, n, rmse(1), rmse(2), rmse(3), ...
            rmse(4), baselines(idx), reduction, 'VariableNames', ...
            ["sensor", "axis", "horizon_s", "trials", "startup_rmse_deg", "white_rmse_deg", ...
             "recent_rmse_deg", "gmwm_rmse_deg", "best_baseline", "gmwm_reduction_vs_best"])]; %#ok<AGROW>
        trials = [trials; table(repmat(sensor, n, 1), repmat(axesNames(a), n, 1), repmat(horizon, n, 1), ...
            d.t0 + start / fs, errors(:, 1), errors(:, 2), errors(:, 3), errors(:, 4), 'VariableNames', ...
            ["sensor", "axis", "horizon_s", "score_start_s", "startup_error_deg", "white_error_deg", ...
             "recent_error_deg", "gmwm_error_deg"])]; %#ok<AGROW>
        fprintf("g%s, %3g s (%2d trials) RMS [deg]: startup %.4f, white %.4f, recent %.4f, GMWM %.4f\n", ...
            axesNames(a), horizon, n, rmse);
    end
end
exp_write("correction.csv", summary);
exp_write("correction_trials.csv", trials);

fig = figure("Visible", "off", "Position", [80 80 1430 460]);
tiles = tiledlayout(fig, 1, 3, "TileSpacing", "compact", "Padding", "compact");
for a = 1:3
    nexttile;
    rows = summary(summary.axis == axesNames(a), :);
    loglog(rows.horizon_s, rows.startup_rmse_deg, "o:", Color="#697077", DisplayName="Startup only");
    hold on;
    loglog(rows.horizon_s, rows.white_rmse_deg, "v--", Color="#94613c", DisplayName="All reference samples");
    loglog(rows.horizon_s, rows.recent_rmse_deg, "s--", Color="#6458a1", DisplayName="Latest reference");
    loglog(rows.horizon_s, rows.gmwm_rmse_deg, "d-", Color="#15798a", LineWidth=1.7, DisplayName="GMWM tracker");
    grid on;
    title("g" + axesNames(a));
    xlabel("Time without reference [s]");
    ylabel("Endpoint angle RMSE [deg]");
    if a == 1
        legend(Location="northwest");
    end
end
title(tiles, "E06 | Stationary gyro bias correction on imu_static_02", Interpreter="none");
exp_figure(fig, "gyro_correction");

function n = sample_count(seconds, fs)
n = seconds * fs;
assert(n >= 1 && n == round(n), "Each duration must contain a positive whole number of samples");
end

function model = profile(params, axisName, fs)
rows = params(params.sensor == "gyro" & params.axis == axisName, :);
density2 = rows.value(rows.term == "WN" & rows.parameter == "density")^2;
K = rows.value(rows.term == "RW" & rows.parameter == "K");
phi = [];
variance = [];
for term = unique(rows.term(rows.parameter == "tc")).'
    tc = rows.value(rows.term == term & rows.parameter == "tc");
    sd = rows.value(rows.term == term & rows.parameter == "std");
    f = exp(-1 / (fs * tc));
    if tc < 1/fs
        density2 = density2 + (2 / fs) * sd^2 * (1 + f) / (1 - f);
    else
        phi(end+1, 1) = f; %#ok<AGROW>
        variance(end+1, 1) = sd^2; %#ok<AGROW>
    end
end
model = struct("f", [1; phi], "gm_variance", variance, "q_rw", K^2 / fs, ...
               "R", density2 * fs / 2);
end

function errors = replay(rate, nStartup, nUpdate, nScore, n, model, fs, initialSd)
startup = rate(1:nStartup);
startupBias = mean(startup);
sumReference = sum(startup);
nReference = nStartup;
f = model.f;
decay = f.^nScore;
steps = [nScore; f(2:end) .* (1 - decay(2:end)) ./ (1 - f(2:end))];
q = diag([model.q_rw; model.gm_variance .* (1 - f(2:end).^2)]);
qGap = diag([nScore * model.q_rw; model.gm_variance .* (1 - decay(2:end).^2)]);
meanBias = zeros(size(f));
covBias = diag([(1000 * initialSd)^2; model.gm_variance]);
[meanBias, covBias] = learn_bias(meanBias, covBias, startup, f, q, model.R);

errors = zeros(n, 4);
for k = 1:n
    start = nStartup + (k - 1) * (nUpdate + nScore);
    reference = rate(start + (1:nUpdate));
    sumReference = sumReference + sum(reference);
    nReference = nReference + nUpdate;
    [meanBias, covBias] = learn_bias(meanBias, covBias, reference, f, q, model.R);

    correction = [nScore * startupBias, nScore * sumReference / nReference, ...
                  nScore * mean(reference), steps.' * meanBias];
    measured = sum(rate(start + nUpdate + (1:nScore)));
    errors(k, :) = (measured - correction) / (1000 * fs);

    % Advance the bias across the scored interval using the model alone.
    meanBias = decay .* meanBias;
    covBias = covBias .* (decay * decay.') + qGap;
end
end

function [meanBias, covBias] = learn_bias(meanBias, covBias, reference, f, q, R)
F2 = f * f.';
for rate = reference.'
    meanBias = f .* meanBias;
    covBias = covBias .* F2 + q;
    cross = sum(covBias, 2);
    variance = sum(cross) + R;
    meanBias = meanBias + (cross / variance) * (rate - sum(meanBias));
    covBias = covBias - (cross * cross.') / variance;
end
end

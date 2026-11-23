% Test uncertainty predictions for open-loop gyro drift on a recording
% separate from the one used to fit the GMWM profile.
cfg = exp_config();
d = exp_data();
assert(d.lost == 0, "Drift integration requires a contiguous recording");
assert(string(cfg.sensor) == "gyro", "This experiment uses gyro rate");
fs = d.fs;
assert(fs == cfg.sample_rate_hz, "The profile is defined for the recorded sample rate");
nBias = cfg.bias_s * fs;
assert(nBias >= 1 && nBias == round(nBias), "The bias period must contain a whole number of samples");

e01 = readtable(exp_path("experiments/E01-imu01-haar-gmwm/out/params.csv"), TextType="string");
e04 = readtable(exp_path("experiments/E04-imu01-full-gmwm/out/params.csv"), TextType="string");
axesNames = ["x", "y", "z"];
sensor = string(cfg.sensor);
datasheet = struct("density", cfg.datasheet_noise_mdps_sqrt_hz, "tc", [], "sigma", [], "K", 0);
models = [profile(e01, "x", fs), profile(e04, "y", fs), profile(e04, "z", fs)];
integral = [zeros(1, 3); cumsum(d.gyro - d.gyro(1, :), 1)];
summary = table();
trials = table();
for duration = cfg.horizons_s(:).'
    nTest = duration * fs;
    assert(nTest >= 1 && nTest == round(nTest), "The forecast must contain a whole number of samples");
    block = nBias + nTest;
    n = floor(size(d.gyro, 1) / block);
    assert(n >= 1, "A complete bias and forecast period must fit in the recording");
    start = (0:n-1).' * block;
    biasEnd = start + nBias + 1;
    bias = (integral(biasEnd, :) - integral(start + 1, :)) / nBias;
    drift = (integral(start + block + 1, :) - integral(biasEnd, :) - nTest * bias) / fs;

    % Drift is a linear contrast of all the samples in the trial. The
    % startup estimate contributes uncertainty and can correlate with the
    % subsequent gyro errors.
    w = [-repmat(nTest / nBias, nBias, 1); ones(nTest, 1)] / fs;
    reference = drift_sd(w, datasheet, fs);
    for a = 1:3
        fitted = drift_sd(w, models(a), fs);
        residual = drift(:, a);
        observed = sqrt(mean(residual.^2));
        k95 = sqrt(2) * erfcinv(0.05);
        coverage = mean(abs(residual) <= k95 * [reference, fitted], 1);
        gain = log(reference / fitted) + (observed^2 / 2) * (1/reference^2 - 1/fitted^2);
        summary = [summary; table(sensor, axesNames(a), duration, n, observed, reference, fitted, ...
            coverage(1), coverage(2), gain, 'VariableNames', ...
            ["sensor", "axis", "horizon_s", "trials", "observed_rms_deg", "datasheet_sd_deg", ...
             "gmwm_sd_deg", "datasheet_coverage", "gmwm_coverage", "gmwm_log_score_gain"])]; %#ok<AGROW>
        trials = [trials; table(repmat(sensor, n, 1), repmat(axesNames(a), n, 1), repmat(duration, n, 1), ...
            d.t0 + start/fs, bias(:, a) + d.gyro(1, a), residual, 'VariableNames', ...
            ["sensor", "axis", "horizon_s", "bias_start_s", "startup_bias_dps", "drift_deg"])]; %#ok<AGROW>
        fprintf("g%s at %3g s, n=%2d: observed RMS %.4f deg, datasheet SD %.4f, GMWM SD %.4f, gain %+.3f\n", ...
            axesNames(a), duration, n, observed, reference, fitted, gain);
    end
end

exp_write("drift.csv", summary);
exp_write("drift_trials.csv", trials);
fig = figure("Visible", "off", "Position", [80 80 1430 460]);
tiles = tiledlayout(fig, 1, 3, "TileSpacing", "compact", "Padding", "compact");
for a = 1:3
    nexttile;
    rows = summary(summary.axis == axesNames(a), :);
    loglog(rows.horizon_s, rows.observed_rms_deg, "ko-", LineWidth=1.5, DisplayName="Observed RMS");
    hold on;
    loglog(rows.horizon_s, rows.datasheet_sd_deg, "s--", Color="#94613c", LineWidth=1.5, DisplayName="Datasheet white noise");
    loglog(rows.horizon_s, rows.gmwm_sd_deg, "d--", Color="#15798a", LineWidth=1.5, DisplayName="GMWM profile");
    grid on;
    title("g" + axesNames(a));
    xlabel("Integration time [s]");
    ylabel("Endpoint drift [deg]");
    if a == 1
        legend(Location="northwest");
    end
end
title(tiles, "E05 | Stationary gyro drift on imu_static_02", Interpreter="none");
exp_figure(fig, "gyro_drift");

function model = profile(params, axisName, fs)
rows = params(params.sensor == "gyro" & params.axis == axisName, :);
model = struct("density", rows.value(rows.term == "WN" & rows.parameter == "density"), ...
    "tc", [], "sigma", [], "K", rows.value(rows.term == "RW" & rows.parameter == "K"));
for term = unique(rows.term(rows.parameter == "tc")).'
    tc = rows.value(rows.term == term & rows.parameter == "tc");
    sigma = rows.value(rows.term == term & rows.parameter == "std");
    if tc < 1/fs
        % Preserve the fast AR(1) term's zero-frequency power.
        phi = exp(-1 / (fs * tc));
        densitySq = (2 / fs) * sigma^2 * (1 + phi) / (1 - phi);
        model.density = sqrt(model.density^2 + densitySq);
    else
        model.tc(end+1) = tc;
        model.sigma(end+1) = sigma;
    end
end
end

function deviation = drift_sd(w, model, fs)
variance = (model.density^2 * fs/2) * sum(w.^2);
walk = cumsum(w, "reverse");
variance = variance + (model.K^2 / fs) * sum(walk(2:end).^2);
for k = 1:numel(model.tc)
    phi = exp(-1 / (fs * model.tc(k)));
    % Backwards impulse weights for the stationary initial state and
    % subsequent innovations, with no dense covariance matrix.
    gm = filter(1, [1, -phi], flipud(w));
    stationaryVariance = model.sigma(k)^2;
    variance = variance + stationaryVariance * ...
        (gm(end)^2 + (1 - phi^2) * sum(gm(1:end-1).^2));
end
deviation = sqrt(variance) / 1000; % millidegrees to degrees
end

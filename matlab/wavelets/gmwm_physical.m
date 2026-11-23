function [P, parts] = gmwm_physical(p, types, fs, C)
% Gyro parameters per sample to the experiment units. C, if supplied, is the
% covariance in log correlation times and log coefficients from gmwm_log_cov.
if nargin < 4
    C = nan(numel(p));
end
first = cumsum([1, 1 + (types(1:end-1) == "AR1")]);
gm = first(types == "AR1");
[~, order] = sort(p(gm));
rows = table();
parts = struct("type", {}, "p", {}, "label", {});

for k = first(types == "WN")
    d = sqrt(2 * p(k) / fs); % one-sided density: Haar WV is D^2 / (2 T)
    rows = [rows; parameter("WN", "density", d, "mdps/sqrt(Hz)", k, 0.5)]; %#ok<AGROW>
    parts(end+1) = struct("type", "WN", "p", p(k), "label", "white noise"); %#ok<AGROW>
end
for g = 1:numel(gm)
    k = gm(order(g));
    phi = p(k);
    tc = -1 / (fs * log(phi));
    stationary = -expm1(2 * log(phi)); % 1 - phi^2
    sd = sqrt(p(k+1) / stationary);
    name = "GM" + g;
    rows = [rows; parameter(name, "tc", tc, "s", k, 1); ...
            parameter(name, "std", sd, "mdps", k:k+1, [-phi^2 * log(phi) / stationary; 0.5])]; %#ok<AGROW>
    parts(end+1) = struct("type", "AR1", "p", p(k:k+1), "label", sprintf("%s, tc %.3g s", name, tc)); %#ok<AGROW>
end
for k = first(types == "RW")
    K = sqrt(p(k) * fs); % its standard deviation grows as K sqrt(t)
    rows = [rows; parameter("RW", "K", K, "mdps/sqrt(s)", k, 0.5)]; %#ok<AGROW>
    parts(end+1) = struct("type", "RW", "p", p(k), "label", "random walk"); %#ok<AGROW>
end
P = rows;

    function row = parameter(term, name, value, unit, indices, derivative)
        variance = derivative.' * C(indices, indices) * derivative;
        ci = [nan, nan];
        if isfinite(variance)
            offset = norminv(0.975) * sqrt(max(variance, 0));
            ci = value * exp([-offset, offset]);
        end
        row = table(term, name, value, unit, ci(1), ci(2), ...
            'VariableNames', ["term" "parameter" "value" "unit" "ci_low" "ci_high"]);
    end
end

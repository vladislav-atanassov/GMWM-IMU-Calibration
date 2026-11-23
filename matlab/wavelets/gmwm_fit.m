function [p, obj] = gmwm_fit(nu2hat, tau, v, types, p0)
% Fit the model in wv_theory's parameter order. v is a vector of WV estimate
% variances or their full covariance matrix. For fixed AR1 correlation times,
% solve the nonnegative variance coefficients by weighted least squares.
% Optional rows of p0 supply the AR1 starts in the same parameter order.
% Otherwise search a log-time grid and refine the best grid points.
tau = tau(:);
types = string(types(:).');
assert(~isempty(types) && all(ismember(types, ["WN", "QN", "RW", "DR", "AR1"])), ...
    "Unsupported wavelet variance model");
isAR = types == "AR1";
nAR = nnz(isAR);
first = cumsum([1, 1 + isAR(1:end-1)]);
phiIdx = first(isAR);
linearIdx = first(~isAR);
drift = types(~isAR) == "DR";

whiten = gmwm_whiten(v);
y = whiten(nu2hat(:));
linear = zeros(numel(tau), numel(linearIdx));
linearTypes = types(~isAR);
for k = 1:numel(linearTypes)
    linear(:, k) = whiten(wv_theory(tau, linearTypes(k), 1));
end

u = zeros(1, 0);
if nAR > 0
    lower = log(-1 / log(realmin));
    upper = log(max(tau));
    if nargin >= 5 && ~isempty(p0)
        phiStart = max(realmin, min(exp(-1 / max(tau)), p0(:, phiIdx)));
        starts = log(-1 ./ log(phiStart));
        starts = sort(max(lower, min(upper, starts)), 2);
    else
        nGrid = max(48, nAR);
        while nGrid > nAR && gammaln(nGrid + 1) - gammaln(nAR + 1) - gammaln(nGrid - nAR + 1) > log(4000)
            nGrid = nGrid - 1;
        end
        grid = linspace(log(0.1), upper, nGrid);
        grid(1) = lower;
        columns = ar_columns(grid);
        combinations = nchoosek(1:nGrid, nAR);
        scores = zeros(size(combinations, 1), 1);
        for k = 1:numel(scores)
            r = project([linear, columns(:, combinations(k, :))], y);
            scores(k) = r.' * r;
        end
        [~, order] = mink(scores, min(5, numel(scores)));
        starts = reshape(grid(combinations(order, :)), numel(order), nAR);
    end

    opts = optimoptions("lsqnonlin", "Display", "off", "FunctionTolerance", 1e-12, ...
                        "StepTolerance", 1e-10, "OptimalityTolerance", 1e-10);
    best = inf;
    for k = 1:size(starts, 1)
        start = starts(k, :);
        [candidate, score] = lsqnonlin(@profile, start, ...
            repmat(lower, 1, nAR), repmat(upper, 1, nAR), opts);
        if score < best
            u = candidate;
            best = score;
        end
    end
    u = sort(u);
end

[~, beta] = project([linear, ar_columns(u)], y);
p = zeros(1, numel(types) + nAR);
p(linearIdx) = beta(1:numel(linearIdx));
p(linearIdx(drift)) = sqrt(p(linearIdx(drift))); % drift enters as omega squared
p(phiIdx) = exp(-exp(-u));
p(phiIdx + 1) = beta(numel(linearIdx) + 1:end);
r = whiten(nu2hat(:) - wv_theory(tau, types, p));
obj = r.' * r;

    function A = ar_columns(logTimes)
        A = zeros(numel(tau), numel(logTimes));
        for j = 1:numel(logTimes)
            phi = exp(-exp(-logTimes(j)));
            A(:, j) = whiten(wv_theory(tau, "AR1", [phi, 1]));
        end
    end

    function r = profile(logTimes)
        r = project([linear, ar_columns(logTimes)], y);
    end
end

function [r, beta] = project(A, y)
% A very fast AR1 is indistinguishable from white noise. Two AR1 columns
% can also coincide as their trial times converge. Keep the first such
% column because splitting its coefficient does not change the fit.
scale = vecnorm(A);
keep = find(scale > 0);
normalized = A(:, keep) ./ scale(keep);
uniqueColumn = true(1, numel(keep));
for k = 2:numel(keep)
    previous = normalized(:, 1:k-1);
    uniqueColumn(k) = all(vecnorm(previous(:, uniqueColumn(1:k-1)) - normalized(:, k)) > 1e-9);
end
keep = keep(uniqueColumn);
beta = zeros(size(A, 2), 1);
r = y;
if isempty(keep)
    return;
end
targetScale = max(norm(y), realmin);
persistent opts
if isempty(opts)
    opts = optimset("Display", "off", "TolX", 1e-12);
end
[weights, ~, ~, exitflag] = lsqnonneg(normalized(:, uniqueColumn), y / targetScale, opts);
assert(exitflag > 0, "The nonnegative wavelet variance solve did not converge");
beta(keep) = weights .* (targetScale ./ scale(keep).');
r = y - A * beta;
end

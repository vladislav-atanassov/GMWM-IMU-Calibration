function result = gmwm_select(nu2, tau, v, models, N, B, seed, workers)
% Refit candidate models with a common full WV covariance and rank by WIC.
% Bootstrap from the diagonal-weight fit of the last (reference) model.
% Sharing its draws and weights makes the prediction losses comparable.
J = numel(tau);
assert(B > J, "The bootstrap needs more replicates than wavelet scales");
reference = models{end};
pilot = gmwm_fit(nu2, tau, v, reference);
bootWV = zeros(J, B);
parfor (b = 1:B, workers)
    stream = RandStream("mrg32k3a", "Seed", seed);
    stream.Substream = b;
    bootWV(:, b) = haar_wvar(simulate(reference, pilot, N, stream), J);
end
V = cov(bootWV.');
whiten = gmwm_whiten(V);
boot = whiten(bootWV);
boot = boot - mean(boot, 2);

fits = cell(size(models));
loss = zeros(size(models));
penaltySamples = zeros(B, numel(models));
for m = 1:numel(models)
    types = models{m};
    [p, loss(m)] = gmwm_fit(nu2, tau, V, types);
    fits{m} = p;
    predicted = zeros(J, B);
    starts = bootstrap_starts(p, types, tau);
    parfor (b = 1:B, workers)
        bp = gmwm_fit(bootWV(:, b), tau, V, types, starts);
        predicted(:, b) = wv_theory(tau, types, bp);
    end
    pred = whiten(predicted);
    pred = pred - mean(pred, 2);
    % Twice the trace of the bootstrap cross-covariance between empirical
    % and fitted WV, after whitening both. cov uses B-1 as its denominator.
    penaltySamples(:, m) = (2 * B / (B - 1)) * sum(boot .* pred, 1).';
end
optimism = mean(penaltySamples, 1);
wic = loss + optimism;
[~, best] = min(wic);
deltaSE = std(penaltySamples - penaltySamples(:, best), 0, 1) / sqrt(B);
result = struct("best", best, "fits", {fits}, "V", V, "loss", loss, ...
                "optimism", optimism, "wic", wic, "deltaSE", deltaSE);
end

function starts = bootstrap_starts(p, types, tau)
% The observed fit and dispersed starts cover nearby basins and let
% terms re-enter when their observed fit is on a zero-variance boundary.
first = cumsum([1, 1 + (types(1:end-1) == "AR1")]);
idx = first(types == "AR1");
starts = repmat(p, 4, 1);
for row = 2:4
    exponents = linspace(0, 1, numel(idx) + 2);
    exponents = min(1, max(0, exponents(2:end-1) + 0.26 * (row - 3)));
    times = 0.1 * (max(tau) / 0.1).^exponents;
    starts(row, idx) = exp(-1 ./ times);
end
end

function x = simulate(types, p, N, stream)
x = zeros(N, 1);
k = 1;
for type = types
    if type == "AR1"
        phi = p(k);
        v2 = p(k + 1);
        if v2 > 0
            state = phi * sqrt(v2 / (1 - phi^2)) * randn(stream);
            x = x + filter(sqrt(v2), [1, -phi], randn(stream, N, 1), state);
        end
        k = k + 2;
        continue;
    end
    if p(k) > 0
        switch type
            case "WN"
                x = x + sqrt(p(k)) * randn(stream, N, 1);
            case "QN"
                x = x + sqrt(p(k)) * diff(randn(stream, N + 1, 1));
            case "RW"
                x = x + sqrt(p(k)) * cumsum(randn(stream, N, 1));
            case "DR"
                x = x + p(k) * (1:N).';
        end
    end
    k = k + 1;
end
end

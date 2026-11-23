function C = gmwm_log_cov(tau, V, types, p)
% Local GMM parameter covariance with efficient (inverse-V) weighting.
% Use log correlation times and log positive coefficients for conditioning.
% Parameters on a boundary, and the time of a zero-variance AR1, have no
% regular Wald interval. Remaining intervals condition on the active set.
first = cumsum([1, 1 + (types(1:end-1) == "AR1")]);
idx = first(types == "AR1");
times = -1 ./ log(p(idx));
active = p > 0;
active(idx) = p(idx + 1) > 0 & p(idx) > 10 * realmin & times < (1 - 1e-6) * max(tau);
which = find(active);
C = nan(numel(p));
if isempty(which)
    return;
end

whiten = gmwm_whiten(V);
step = 1e-4;
A = zeros(numel(tau), numel(which));
for c = 1:numel(which)
    k = which(c);
    low = p;
    high = p;
    if ismember(k, idx)
        low(k) = exp(log(p(k)) * exp(step));
        high(k) = exp(log(p(k)) * exp(-step));
    else
        low(k) = p(k) * exp(-step);
        high(k) = p(k) * exp(step);
    end
    A(:, c) = whiten(wv_theory(tau, types, high) - wv_theory(tau, types, low)) / (2 * step);
end

[~, S, Q] = svd(A, "econ");
s = diag(S);
if numel(s) < numel(which) || s(end) <= sqrt(eps) * s(1)
    warning("The active wavelet model is locally rank deficient. Skipping Wald intervals.");
    return;
end
C(which, which) = (Q ./ (s.'.^2)) * Q.';
end

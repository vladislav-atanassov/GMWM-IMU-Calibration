function whiten = gmwm_whiten(v)
% Transform WV residuals (or columns) so their squared norm uses inv(V).
if isvector(v)
    assert(all(isfinite(v) & v > 0), "Wavelet variances must be finite and positive");
    sd = sqrt(v(:));
    whiten = @(x) x ./ sd;
else
    assert(issymmetric(v) && all(isfinite(v), "all"), "Wavelet covariance must be finite and symmetric");
    % Factor the correlation matrix so large differences in scale do not
    % affect the numerics of the Cholesky factorization.
    sd = sqrt(diag(v));
    L = chol(v ./ (sd * sd.'), "lower");
    whiten = @(x) L \ (x ./ sd);
end
end

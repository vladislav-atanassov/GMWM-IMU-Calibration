function [p, obj] = gmwm_fit(nu2hat, tau, v, types, p0)
% GMWM: the parameters p of the model types (layout as in wv_theory) whose
% wavelet variance best fits nu2hat, weighted by 1 ./ v, starting from p0 > 0
n   = 1 + (types == "AR1");
phi = cumsum([1, n(1:end-1)]);
phi = phi(types == "AR1");                % where each AR1 phi sits in p
f = @(z) sum((nu2hat - wv_theory(tau, types, to_p(z, phi))).^2 ./ v);
z = log(p0);
z(phi) = log(p0(phi) ./ (1 - p0(phi)));
opts = optimset("MaxFunEvals", 2e4, "MaxIter", 2e4, "TolX", 1e-10, "TolFun", 1e-12);
for k = 1:4                               % Nelder-Mead restarts
    z = fminsearch(f, z, opts);
end
p = to_p(z, phi);
obj = f(z);
end

% Searching over z keeps every model valid: variances exp(z) > 0, 0 < phi < 1
function p = to_p(z, phi)
p = exp(z);
p(phi) = 1 ./ (1 + exp(-z(phi)));
end

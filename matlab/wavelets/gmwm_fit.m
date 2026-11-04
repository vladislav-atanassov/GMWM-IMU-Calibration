function [p, obj] = gmwm_fit(nu2hat, tau, v, types, p0)
% GMWM: the parameters p of the model types (layout as in wv_theory) whose
% wavelet variance best fits nu2hat, weighted by 1 ./ v. p0 holds starting values
% > 0, one start per row (gmwm_start gives several): Nelder-Mead finds different
% local minima from different starts, so it fits from each and keeps the lowest
% objective. Each AR1's correlation time stays under the coarsest scale, tau(end)
% samples: a slower one looks like a random walk at every scale, so the fit could
% trade one for the other freely
n   = 1 + (types == "AR1");
phi = cumsum([1, n(1:end-1)]);
phi = phi(types == "AR1");                % where each AR1 phi sits in p
phi_max = exp(-1 / tau(end));
f = @(z) sum((nu2hat - wv_theory(tau, types, to_p(z, phi, phi_max))).^2 ./ v);
opts = optimset("MaxFunEvals", 2e4, "MaxIter", 2e4, "TolX", 1e-10, "TolFun", 1e-12);
obj = inf;
for r = 1:size(p0, 1)
    z = log(p0(r, :));
    s = min(p0(r, phi) / phi_max, 1 - 1e-9); % a start beyond the bound moves just under it
    z(phi) = log(s ./ (1 - s));
    for k = 1:4                           % Nelder-Mead restarts
        z = fminsearch(f, z, opts);
    end
    if f(z) < obj
        obj = f(z);
        p = to_p(z, phi, phi_max);
    end
end
end

% Searching over z keeps every model valid: variances exp(z) > 0, 0 < phi < phi_max
function p = to_p(z, phi, phi_max)
p = exp(z);
p(phi) = phi_max ./ (1 + exp(-z(phi)));
end

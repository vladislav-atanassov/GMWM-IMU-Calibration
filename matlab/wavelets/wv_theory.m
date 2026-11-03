function nu2 = wv_theory(tau, types, p)
% Haar wavelet variance at the scales tau of a sum of independent processes.
% p holds the parameters of each type in turn, per sample:
%   WN   white noise          sigma^2
%   QN   quantization noise   Q^2
%   RW   random walk          gamma^2
%   DR   drift                omega
%   AR1  Gauss-Markov         phi, v^2  (X_t = phi X_(t-1) + e_t, Var e_t = v^2)
tau = tau(:);
nu2 = zeros(size(tau));
k = 1;
for type = types
    switch type
        case "WN"
            nu2 = nu2 + p(k) ./ tau;
        case "QN"
            nu2 = nu2 + 6 * p(k) ./ tau.^2;
        case "RW"
            nu2 = nu2 + p(k) * (tau.^2 + 2) ./ (12 * tau);
        case "DR"
            nu2 = nu2 + p(k)^2 * tau.^2 / 16;
        case "AR1"
            nu2 = nu2 + arrayfun(@(t) ar1(t, p(k), p(k+1)), tau);
            k = k + 1;
    end
    k = k + 1;
end
end

% The closed form cancels when m (1 - phi) << 1, so small scales use the lag sum
function nu2 = ar1(tau, phi, v2)
m = tau / 2;
if m > 4096
    nu2 = 2 * v2 * (m*(1 - phi^2) - 3*phi + 4*phi^(m+1) - phi^(2*m+1)) / (tau^2 * (1 - phi)^2 * (1 - phi^2));
else
    h = (1:2*m-1)';
    R = (h <= m) .* (2*m - 3*h) - (h > m) .* (2*m - h); % autocorrelation of the Haar filter
    nu2 = 2 * v2 * sum(R .* expm1(h * log(phi))) / (tau^2 * -expm1(2 * log(phi)));
end
end

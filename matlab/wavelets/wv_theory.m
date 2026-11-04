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

% The closed form's numerator m (1 - phi^2) - 3 phi + 4 phi^(m+1) - phi^(2m+1) is about
% (2/3) (m l)^3 with l = -log(phi), out of terms of size 1, so it cancels when m l is small:
% whatever the scale, once the correlation time is long next to it. There it sums the
% numerator's Taylor series in l instead, whose terms 0 to 2 vanish exactly and the rest
% do not cancel
function nu2 = ar1(tau, phi, v2)
m = tau / 2;
l = -log(phi);
if m * l > 0.1
    num = -m * expm1(-2*l) - 3*phi + 4*phi^(m+1) - phi^(2*m+1);
else
    num = 0;
    for k = 3:40
        term = (-1)^k / factorial(k) * (4*((m+1)*l)^k - ((2*m+1)*l)^k - m*(2*l)^k - 3*l^k);
        num = num + term;
        if abs(term) <= 1e-17 * abs(num)
            break;
        end
    end
end
nu2 = 2 * v2 * num / (tau^2 * expm1(-l)^2 * -expm1(-2*l)); % / (tau^2 (1 - phi)^2 (1 - phi^2))
end

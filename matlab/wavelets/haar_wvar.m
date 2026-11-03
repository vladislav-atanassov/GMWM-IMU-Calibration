function [nu2, tau, v] = haar_wvar(x, J)
% Haar wavelet variance nu2 of x at the scales tau = 2^j, j = 1..J, and the
% variance v of each estimate, which weights the GMWM fit
x   = x(:);
N   = numel(x);
S   = [0; cumsum(x - mean(x))];
tau = 2.^(1:J)';
nu2 = zeros(J, 1);
v   = zeros(J, 1);
for j = 1:J
    m = tau(j) / 2;
    t = (2*m:N)';
    w = (S(t+1) - 2*S(t-m+1) + S(t-2*m+1)) / tau(j); % (newest m samples - the m before) / tau
    M = numel(w);
    nu2(j) = mean(w.^2);
    s = ifft(abs(fft(w, 2^nextpow2(2*M))).^2) / M;   % autocovariance of w
    s = real(s(1:M));
    v(j) = 2 * (s(1)^2/2 + sum(s(2:end).^2)) / M;
end
end

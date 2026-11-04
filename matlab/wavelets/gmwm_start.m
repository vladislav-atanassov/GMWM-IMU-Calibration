function p0 = gmwm_start(nu2hat, tau, v, types, k)
% Starting values for gmwm_fit from the wavelet variance alone. The AR1
% correlation times are tried on a grid of scales, and the k (default 8) with
% the lowest objective come back as rows, best first, since the fit's answer
% depends on where it starts
if nargin < 5
    k = 8;
end
grid = nchoosek(tau(2:2:end-1)', sum(types == "AR1")); % rows of increasing tc [samples]
P   = [];
obj = [];
for row = 1:size(grid, 1)
    p = [];
    a = 0;
    for type = types
        switch type
            case "WN"
                p(end+1) = nu2hat(1) * tau(1); %#ok<AGROW>
            case "QN"
                p(end+1) = nu2hat(1) * tau(1)^2 / 6; %#ok<AGROW>
            case "RW"
                p(end+1) = 12 * nu2hat(end) / tau(end); %#ok<AGROW>
            case "DR"
                p(end+1) = 4 * sqrt(nu2hat(end)) / tau(end); %#ok<AGROW>
            case "AR1"
                a = a + 1;
                tc = grid(row, a);
                phi = exp(-1 / tc);
                p(end+1:end+2) = [phi, 4 * nu2hat(tau == tc) * (1 - phi^2)];
        end
    end
    P(end+1, :) = p; %#ok<AGROW>
    obj(end+1) = sum((nu2hat - wv_theory(tau, types, p)).^2 ./ v); %#ok<AGROW>
end
[~, order] = sort(obj);
p0 = P(order(1:min(k, end)), :);
end

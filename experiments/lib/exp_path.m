function p = exp_path(relative)
% A path in the repository, e.g. addpath(exp_path("matlab/wavelets"))
p = fullfile(getenv("EXP_ROOT"), relative);
end

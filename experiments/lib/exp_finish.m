function exp_finish()
% run.py calls this after main.m: records the MATLAB version for run.json
env = struct("language", "MATLAB", "matlab", version);
writelines(jsonencode(env), fullfile(getenv("EXP_OUT"), "env.json"));
end

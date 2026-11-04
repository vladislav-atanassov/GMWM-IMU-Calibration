function cfg = exp_config()
% The running experiment's config.json, as a struct. Lists of strings come back as cell arrays
cfg = jsondecode(fileread(getenv("EXP_CONFIG")));
end

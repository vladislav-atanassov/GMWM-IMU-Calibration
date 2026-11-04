function d = exp_data()
% The running experiment's data: the window of its dataset that run.py decoded once into
% data/cache/, the same samples for every language. Returns a struct with fields:
%   dataset   name in data/README.md
%   window_s  the window kept, "from-to" in seconds since the log's first sample
%   fs        nominal sample rate [Hz]
%   t0        time of the first sample [s] since the log's first sample
%   gyro      N x 3 angular rate [dps], axes x y z
%   accel     N x 3 acceleration [g]
%   lost      blocks lost within the window; gyro and accel run straight across the gaps
h   = jsondecode(fileread(getenv("EXP_DATA")));
fid = fopen(fullfile(fileparts(getenv("EXP_DATA")), h.samples_file), "r", "ieee-le");
raw = fread(fid, [numel(h.columns) inf], "*int16").'; % one sample per row
fclose(fid);
assert(size(raw, 1) == h.samples, "The cached samples do not match their header");

d.dataset  = string(h.dataset);
d.window_s = string(h.window_s);
d.fs       = h.fs;
d.t0       = h.t0_s;
d.gyro     = double(raw(:, 1:3)) * h.gyro_scale;
d.accel    = double(raw(:, 4:6)) * h.accel_scale;
d.lost     = h.lost_blocks;
end

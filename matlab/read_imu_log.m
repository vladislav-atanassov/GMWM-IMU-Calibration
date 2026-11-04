function imu = read_imu_log(file, window)
% Read a log from `python -m gmwm record` into physical units. The file holds
% the XIAO's LSM6DS3TR-C stream packets back to back, as sent: the header is in
% firmware/common/stream/stream_packet.h and the payload in the XIAO's
% include/Imu/imu_sampler.h. file can also be those bytes, as a uint8 vector.
% window, optional: [from to] in seconds since the log's first sample, to keep
% only that part, e.g. [2.8 9.5] * 3600. It keeps whole blocks only, so it
% rounds inward by up to one block (32 samples, 0.31 s at 104 Hz). Default: all.
% Returns a struct with fields:
%   t0           time of the first sample kept [s], since the log's first sample
%   fs           nominal sample rate [Hz], from the IMU's ODR setting
%   gyro         N x 3 angular rate [dps], axes x y z
%   accel        N x 3 acceleration [g]
%   gyro_scale   one gyro code [dps], the quantization step
%   accel_scale  one accelerometer code [g]
%   temp         temperature [degC], one per block, read as the block completed
%   temp_k       the sample each temp was read after
%   seq          block numbers
%   lost         blocks missing between the first and the last kept. gyro and accel
%                run straight across the gaps, so check this is 0 before a fit

if isa(file, "uint8")
    bytes = file(:);
    file  = "the packets"; % for the messages
else
    fid = fopen(file, "r");
    assert(fid >= 0, "Cannot open %s", file);
    bytes = fread(fid, inf, "*uint8");
    fclose(fid);
end
assert(numel(bytes) >= 12, "No packets in %s", file);

% Every packet in a log has the same length, so one packet per column
L = 12 + double(typecast(bytes(7:8), "uint16"));
k = floor(numel(bytes) / L);
if k * L < numel(bytes)
    warning("%s: the last %d bytes are an incomplete packet; ignored", file, numel(bytes) - k * L);
end
P = reshape(bytes(1:k*L), L, k);
assert(all(P(1:4, :) == uint8([0xDE; 0xC0; 0xDE; 0xC0]), "all"), ...
       "%s: not every packet is where expected. Is it a log from gmwm record?", file);
assert(all(field(P, 5, "uint16") == 2), "%s: not LSM6DS3TR-C packets (source 2)", file);

% Settings, as the IMU ran them; datasheet Tables 3, 51, 54
ctrl1_xl = unique(P(13, :));
ctrl2_g  = unique(P(14, :));
assert(isscalar(ctrl1_xl) && isscalar(ctrl2_g), "%s: the IMU settings change within the log", file);
odr_hz = [12.5 26 52 104 208 416 833 1660 3330 6660];
imu.fs          = odr_hz(bitshift(ctrl2_g, -4));
imu.gyro_scale  = scale_for(bitand(ctrl2_g, 0x0E), [0x2 0x0 0x4 0x8 0xC], [4.375 8.75 17.5 35 70] * 1e-3);
imu.accel_scale = scale_for(bitand(ctrl1_xl, 0x0C), [0x0 0x8 0xC 0x4], [0.061 0.122 0.244 0.488] * 1e-3);

seq = double(field(P, 9, "uint32")).';
assert(all(diff(seq) > 0), "%s: the sequence restarts, so the board reset during the log", file);

% Keep the blocks wholly inside window. Time follows seq, so a lost block still
% takes up its time and the blocks after it keep their place
if nargin < 2
    window = [0 inf];
end
S     = (L - 16) / 12;          % samples per block
first = (seq - seq(1)) * S;     % samples in the log before each block
keep  = first >= window(1) * imu.fs & first + S <= window(2) * imu.fs;
assert(any(keep), "%s: no whole block within %g..%g s", file, window(1), window(2));
P = P(:, keep);
k = nnz(keep);
imu.t0 = first(find(keep, 1)) / imu.fs;

raw = reshape(double(typecast(reshape(P(17:end, :), 1, []), "int16")), 6, []).'; % [gx gy gz ax ay az] per row
imu.gyro   = raw(:, 1:3) * imu.gyro_scale;
imu.accel  = raw(:, 4:6) * imu.accel_scale;
imu.temp   = 25 + double(field(P, 15, "int16")).' / 256;
imu.temp_k = ((1:k) * S).';
imu.seq    = seq(keep);

steps = diff(imu.seq);
imu.lost = sum(steps - 1);
if imu.lost > 0
    warning("%s: %d blocks lost in %d gaps", file, imu.lost, nnz(steps > 1));
end
end

% One value of type from every packet, starting at byte offset (1-based)
function x = field(P, offset, type)
n = numel(typecast(zeros(1, 1, type), "uint8"));
x = typecast(reshape(P(offset:offset+n-1, :), 1, []), type);
end

function v = scale_for(key, keys, values)
i = find(keys == key, 1);
assert(~isempty(i), "Unknown full-scale setting 0x%02X", key);
v = values(i);
end

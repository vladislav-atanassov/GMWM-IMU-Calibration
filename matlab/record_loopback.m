% Step 1: record the DAC-to-ADC loopback and plot the noisy signal over the
% clean one.

port  = "COM4"; % ST-LINK virtual COM port, see serialportlist
count = 40;     % packets to record; each has 256 frames (0.256 s at 1 kHz)
fs    = 1000;   % sample rate, EMULATOR_FS_HZ in app_config.h

packets = read_packets(port, count);

% The emulator's payload is [clean, noisy] uint16 pairs
samples = double(typecast([packets.payload], "uint16"));
clean   = samples(1:2:end);
noisy   = samples(2:2:end);

t = (0:numel(clean) - 1) / fs;
plot(t, noisy, t, clean);
legend("noisy", "clean");
xlabel("Time [s]");
ylabel("ADC code");

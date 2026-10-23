function packets = read_packets(port, count)
% Read count packets from the H7's stream over the ST-LINK virtual COM port.
% Returns a struct array with the header fields source and seq, and payload
% as raw bytes for the caller to decode. Packet format is in stream.h.

device = serialport(port, 921600);
flush(device);

packets = struct("source", cell(1, count), "seq", [], "payload", []);
for k = 1:count
    waitForMagic(device);
    packets(k).source  = read(device, 1, "uint16");
    nbytes             = read(device, 1, "uint16");
    packets(k).seq     = read(device, 1, "uint32");
    packets(k).payload = uint8(read(device, nbytes, "uint8"));
end
end

% Read bytes until the last four are the magic 0xC0DEC0DE, sent low byte first
function waitForMagic(device)
last4 = zeros(1, 4);
while ~isequal(last4, [0xDE 0xC0 0xDE 0xC0])
    last4 = [last4(2:4), read(device, 1, "uint8")];
end
end

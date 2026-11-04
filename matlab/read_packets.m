function packets = read_packets(port, count)
% Read count packets from a board's stream: the Nucleo over the ST-LINK virtual
% COM port, or the XIAO over USB (which ignores the baud rate). Returns a struct
% array with the header fields source and seq, and payload as raw bytes for the
% caller to decode. Packet format is in firmware/common/stream/stream_packet.h.

device = serialport(port, 921600);
pause(0.5); % packets a board buffered while the port was closed arrive at once; drop them
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
    b = read(device, 1, "uint8");
    assert(~isempty(b), "No data from the board: is it streaming, and did the PC stay awake?");
    last4 = [last4(2:4), b];
end
end

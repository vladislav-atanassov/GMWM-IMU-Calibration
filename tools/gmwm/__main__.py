#!/usr/bin/env python3
"""GMWM CLI: build, clean, and flash the NUCLEO-H755ZI-Q; monitor and record either board's stream."""

import argparse
import ctypes
import os
import re
import shutil
import statistics
import struct
import subprocess
import sys
import time
from pathlib import Path

import serial
import serial.tools.list_ports

_HERE = Path(__file__).parent

DEFAULT_BAUD = 921600  # the Nucleo's USART3; the XIAO's USB CDC port ignores it
PRESET = "Debug"
CORES = ("CM7", "CM4")
ZEPHYR_USB_ID = (0x2FE3, 0x0004)  # the XIAO's Zephyr CDC ACM port

# Packet header from firmware/common/stream/stream_packet.h, little-endian:
#   uint32 magic, uint16 source, uint16 length, uint32 seq
STREAM_MAGIC = struct.pack("<I", 0xC0DEC0DE)
STREAM_HEADER = struct.Struct("<IHHI")
STREAM_SRC_EMULATOR = 1
STREAM_SRC_LSM6DS3TRC = 2

# LSM6DS3TR-C payload (imu_payload_t in the XIAO's imu_sampler.h): uint8 CTRL1_XL,
# uint8 CTRL2_G, int16 temperature, then frames of [gx gy gz ax ay az] int16
IMU_HEADER = struct.Struct("<BBh")
IMU_AXES = 6
# Decoded from the register values each packet carries, per the datasheet's Tables 3, 51, 54
IMU_ODR_HZ = {1: 12.5, 2: 26, 3: 52, 4: 104, 5: 208, 6: 416, 7: 833, 8: 1660, 9: 3330, 10: 6660}
IMU_GYRO_DPS_PER_LSB = {0x2: 4.375e-3, 0x0: 8.75e-3, 0x4: 17.5e-3, 0x8: 35e-3, 0xC: 70e-3}  # CTRL2_G & 0x0E
IMU_ACCEL_G_PER_LSB = {0x0: 0.061e-3, 0x8: 0.122e-3, 0xC: 0.244e-3, 0x4: 0.488e-3}  # CTRL1_XL & 0x0C
IMU_TEMP_LSB_PER_DEGC = 256  # 0 LSB = 25 degC


def _project_root() -> Path:
    return _HERE.parent.parent


def _firmware_dir() -> Path:
    return _project_root() / "firmware" / "imu-emulator" / "nucleo-h755zi-q"


def _elf(core: str) -> Path:
    return _firmware_dir() / core / "build" / f"GMWM-IMU-Calibration_{core}.elf"


def _find_programmer() -> str:
    if path := shutil.which("STM32_Programmer_CLI"):
        return path
    program_files = Path(os.environ.get("ProgramFiles", r"C:\Program Files"))
    candidates = [program_files / "STMicroelectronics/STM32Cube/STM32CubeProgrammer/bin/STM32_Programmer_CLI.exe"]
    candidates += sorted(
        Path("C:/ST").glob("STM32CubeIDE_*/STM32CubeIDE/plugins/*cubeprogrammer*/tools/bin/STM32_Programmer_CLI.exe"),
        reverse=True,
    )
    for candidate in candidates:
        if candidate.exists():
            return str(candidate)
    print("[!] STM32_Programmer_CLI not found. Install STM32CubeProgrammer or add it to PATH.")
    sys.exit(1)


def _ensure_configured():
    if not (_firmware_dir() / "build" / PRESET / "CMakeCache.txt").exists():
        print(f"[*] Build dir not found, configuring preset '{PRESET}'...")
        result = subprocess.run(["cmake", "--preset", PRESET], cwd=str(_firmware_dir()))
        if result.returncode != 0:
            sys.exit(result.returncode)


def _build():
    """Build both cores; the top-level preset runs each core's CMake project."""
    _ensure_configured()
    result = subprocess.run(["cmake", "--build", "--preset", PRESET], cwd=str(_firmware_dir()))
    if result.returncode != 0:
        sys.exit(result.returncode)


def _flash():
    """Write and verify both cores' ELFs over SWD, then reset the board."""
    cmd = [_find_programmer(), "-c", "port=SWD"]
    for core in CORES:
        cmd += ["-w", str(_elf(core)), "-v"]
    cmd.append("-hardRst")
    result = subprocess.run(cmd)
    if result.returncode != 0:
        sys.exit(result.returncode)


def _is_board_port(port) -> bool:
    """The Nucleo's ST-LINK or the XIAO's Zephyr USB port."""
    if (port.vid, port.pid) == ZEPHYR_USB_ID:
        return True
    desc = (port.description or "").lower()
    mfr = (port.manufacturer or "").lower()
    return "stlink" in desc or "stm32" in desc or "stlink" in mfr or "stm" in mfr


def find_serial_port() -> str | None:
    """The one connected board's port, or None when there are none or several."""
    boards = [port.device for port in serial.tools.list_ports.comports() if _is_board_port(port)]
    if len(boards) > 1:
        print(f"[!] Several boards connected ({', '.join(boards)}).")
    return boards[0] if len(boards) == 1 else None


def _open_port(args) -> serial.Serial:
    port = args.port or find_serial_port()
    if not port:
        print("[!] Pick the board's port with -p/--port (e.g. -p COM12).")
        sys.exit(1)
    try:
        return serial.Serial(port, args.baud_rate, timeout=0.5)
    except serial.SerialException as e:
        print(f"[!] Cannot open {port} (is MATLAB or another monitor using it?): {e}")
        sys.exit(1)


def read_packets(ser):
    """Yield (source, seq, payload) for each stream packet, or None after a read that timed out.

    A packet only counts once the next magic follows its payload, so a magic that
    happens to appear inside the payload is not taken for a packet start.
    """
    buf = bytearray()
    while True:
        chunk = ser.read(ser.in_waiting or 1)
        if not chunk:
            yield None
            continue
        buf += chunk
        while True:
            start = buf.find(STREAM_MAGIC)
            if start < 0:
                del buf[:-3]  # keep a magic that may be split across reads
                break
            del buf[:start]
            if len(buf) < STREAM_HEADER.size:
                break
            _, source, length, seq = STREAM_HEADER.unpack_from(buf)
            end = STREAM_HEADER.size + length
            if len(buf) < end + len(STREAM_MAGIC):
                break
            if buf[end:end + len(STREAM_MAGIC)] != STREAM_MAGIC:
                del buf[:1]
                continue
            yield source, seq, bytes(buf[STREAM_HEADER.size:end])
            del buf[:end]


def decode_imu(payload: bytes) -> dict | None:
    """The LSM6DS3TR-C payload in physical units, or None when its settings are not recognised."""
    ctrl1_xl, ctrl2_g, temp_raw = IMU_HEADER.unpack_from(payload)
    odr = IMU_ODR_HZ.get(ctrl2_g >> 4)
    dps = IMU_GYRO_DPS_PER_LSB.get(ctrl2_g & 0x0E)
    g = IMU_ACCEL_G_PER_LSB.get(ctrl1_xl & 0x0C)
    n = (len(payload) - IMU_HEADER.size) // (2 * IMU_AXES)
    if None in (odr, dps, g) or IMU_ODR_HZ.get(ctrl1_xl >> 4) != odr:
        return None
    raw = struct.unpack_from(f"<{n * IMU_AXES}h", payload, IMU_HEADER.size)
    return {
        "fs": odr,
        "frames": n,
        "gyro_dps": [[raw[k * IMU_AXES + a] * dps for k in range(n)] for a in range(3)],
        "accel_g": [[raw[k * IMU_AXES + 3 + a] * g for k in range(n)] for a in range(3)],
        "temp_c": 25 + temp_raw / IMU_TEMP_LSB_PER_DEGC,
    }


def describe_packet(source: int, seq: int, payload: bytes) -> str:
    if source == STREAM_SRC_EMULATOR:
        samples = struct.unpack(f"<{len(payload) // 2}H", payload)
        clean, noisy = samples[0::2], samples[1::2]
        noise = [n - c for c, n in zip(clean, noisy)]
        return (f"seq {seq:7d}  emulator  {len(clean)} frames  clean {min(clean):5d}..{max(clean):5d}  "
                f"noise mean {statistics.fmean(noise):+8.1f}  std {statistics.pstdev(noise):7.1f}")
    if source == STREAM_SRC_LSM6DS3TRC and (imu := decode_imu(payload)):
        gyro = " ".join(f"{statistics.fmean(axis):+8.3f}" for axis in imu["gyro_dps"])
        accel = " ".join(f"{statistics.fmean(axis):+7.4f}" for axis in imu["accel_g"])
        return (f"seq {seq:7d}  imu  {imu['frames']} frames at {imu['fs']:g} Hz  "
                f"gyro mean [dps] {gyro}  accel mean [g] {accel}  {imu['temp_c']:6.2f} degC")
    return f"seq {seq:7d}  source {source}  {len(payload)} bytes"


def _parse_duration(text: str) -> float:
    """Seconds from a duration like 3h, 90m, 45s, or 1h30m."""
    parts = re.fullmatch(r"(?:(\d+(?:\.\d+)?)h)?(?:(\d+(?:\.\d+)?)m)?(?:(\d+(?:\.\d+)?)s)?", text.strip())
    if not text.strip() or not parts:
        raise argparse.ArgumentTypeError(f"not a duration like 3h, 90m, 45s or 1h30m: {text!r}")
    h, m, s = (float(p) if p else 0.0 for p in parts.groups())
    return 3600 * h + 60 * m + s


def _format_elapsed(seconds: float) -> str:
    m, s = divmod(int(seconds), 60)
    h, m = divmod(m, 60)
    return f"{h:d}:{m:02d}:{s:02d}"


def _keep_awake(on: bool):
    """Stop Windows from sleeping while recording: sleep stops the USB stream."""
    if sys.platform == "win32":
        es_continuous, es_system_required = 0x80000000, 0x00000001
        set_state = ctypes.windll.kernel32.SetThreadExecutionState
        set_state.argtypes = [ctypes.c_uint32]  # the flags pass 2^31, too big for the default int
        set_state.restype = ctypes.c_uint32
        if not set_state(es_continuous | (es_system_required if on else 0)) and on:
            print("[!] Could not keep the PC awake: stop it sleeping for the recording.")


# ---- Subcommand handlers ----

def cmd_build(args):
    _build()


def cmd_clean(args):
    build_dirs = [_firmware_dir() / "build"] + [_firmware_dir() / core / "build" for core in CORES]
    existing = [d for d in build_dirs if d.exists()]
    if not existing:
        print("[*] Nothing to clean.")
        return
    for build_dir in existing:
        print(f"[*] Removing {build_dir}...")
        shutil.rmtree(build_dir)
    print("[+] Done.")


def cmd_flash(args):
    _build()
    _flash()


def cmd_monitor(args):
    ser = _open_port(args)
    print(f"[*] Monitoring {ser.port}. Press Ctrl+C to exit.")
    last_seq = None
    try:
        for packet in read_packets(ser):
            if packet is None:
                continue
            source, seq, payload = packet
            if last_seq is not None and seq != last_seq + 1:
                if seq > last_seq:
                    print(f"[!] Lost {seq - last_seq - 1} blocks")
                else:
                    print("[*] Sequence restarted (board reset)")
            last_seq = seq
            print(describe_packet(source, seq, payload), flush=True)
    except KeyboardInterrupt:
        print("\n[*] Monitor closed.")
    except serial.SerialException as e:
        print(f"[!] Serial read error: {e}")
    finally:
        ser.close()


def cmd_flash_monitor(args):
    cmd_flash(args)
    cmd_monitor(args)


def cmd_record(args):
    """Append every stream packet to a file as it arrives, so a crash keeps what came before."""
    out = Path(args.output)
    if out.exists():
        print(f"[!] {out} exists: pick a new name.")
        sys.exit(1)
    out.parent.mkdir(parents=True, exist_ok=True)

    ser = _open_port(args)
    # The board drops what it cannot send while the port is closed, but its buffer can
    # still hold stale packets from before. Let them arrive, then throw them away.
    time.sleep(0.5)
    ser.reset_input_buffer()

    duration = args.duration
    print(f"[*] Recording {ser.port} to {out}"
          + (f" for {_format_elapsed(duration)}" if duration else "") + ". Press Ctrl+C to stop.")
    _keep_awake(True)

    packets = frames = lost = 0
    first_seq = last_seq = None
    t_first = t_last = t_report = t_data = time.monotonic()
    fs = temp_c = None
    try:
        with open(out, "xb") as f:
            for packet in read_packets(ser):
                now = time.monotonic()
                if packet is None:
                    if now - t_data > 5:
                        print("[!] No data for 5 s: is the board streaming?")
                        t_data = now
                    continue
                source, seq, payload = packet
                t_data = now

                f.write(STREAM_HEADER.pack(0xC0DEC0DE, source, len(payload), seq) + payload)
                f.flush()

                if last_seq is None:
                    first_seq, t_first = seq, now
                elif seq > last_seq + 1:
                    lost += seq - last_seq - 1
                    print(f"[!] {_format_elapsed(now - t_first)}  lost {seq - last_seq - 1} blocks")
                elif seq <= last_seq:
                    print(f"[!] {_format_elapsed(now - t_first)}  sequence restarted: the board reset, "
                          "so the record no longer runs from one power-up")
                last_seq, t_last = seq, now
                packets += 1

                if source == STREAM_SRC_LSM6DS3TRC and (imu := decode_imu(payload)):
                    frames += imu["frames"]
                    fs, temp_c = imu["fs"], imu["temp_c"]

                if now - t_report >= 10:
                    t_report = now
                    status = f"{frames:,} samples" if fs else f"{packets:,} packets"
                    temp = f"  {temp_c:.2f} degC" if temp_c is not None else ""
                    print(f"[*] {_format_elapsed(now - t_first)}  {status}  lost {lost} blocks{temp}")

                if duration and now - t_first >= duration:
                    break
    except KeyboardInterrupt:
        print("\n[*] Stopped.")
    except serial.SerialException as e:
        print(f"[!] Serial read error, recording ends here: {e}")
    finally:
        _keep_awake(False)
        ser.close()

    print(f"[+] {packets:,} packets in {out}, seq {first_seq}..{last_seq}, lost {lost} blocks")
    if fs and packets > 1 and t_last > t_first and last_seq > first_seq:
        # Blocks leave as the IMU fills them, so the PC clock can time the IMU's. The first
        # block's samples were taken before t_first, and lost blocks were taken too.
        per_block = frames / packets
        measured = (last_seq - first_seq) * per_block / (t_last - t_first)
        print(f"[+] {frames:,} samples, {frames / fs / 3600:.2f} h at the nominal {fs:g} Hz. "
              f"Measured against the PC clock: {measured:.3f} Hz ({100 * (measured / fs - 1):+.2f}%)")


# ---- Entry point ----

def _add_serial_args(p):
    p.add_argument("-p", "--port", default=None, help="Serial port (auto-detected if omitted)")
    p.add_argument("-b", "--baud-rate", type=int, default=DEFAULT_BAUD,
                   help=f"Baud rate (default: {DEFAULT_BAUD}; the XIAO ignores it)")


def main():
    parser = argparse.ArgumentParser(
        prog="gmwm",
        description="GMWM build, clean, flash, monitor, and record CLI",
    )
    sub = parser.add_subparsers(dest="command", required=True)

    p_build = sub.add_parser("build", help=f"Build both Nucleo cores ({PRESET})")
    p_build.set_defaults(func=cmd_build)

    p_clean = sub.add_parser("clean", help="Remove the Nucleo build directories")
    p_clean.set_defaults(func=cmd_clean)

    p_flash = sub.add_parser("flash", help="Build, then flash both Nucleo cores over SWD")
    p_flash.set_defaults(func=cmd_flash)

    p_monitor = sub.add_parser("monitor", help="Decode the board's stream, one line per block")
    _add_serial_args(p_monitor)
    p_monitor.set_defaults(func=cmd_monitor)

    p_flash_monitor = sub.add_parser("flash-monitor", help="Build, flash, then monitor the Nucleo")
    _add_serial_args(p_flash_monitor)
    p_flash_monitor.set_defaults(func=cmd_flash_monitor)

    p_record = sub.add_parser("record", help="Save the board's stream packets to a file")
    p_record.add_argument("output", help="New file for the packets, e.g. data/imu_static_01.bin")
    p_record.add_argument("-t", "--duration", type=_parse_duration, default=None,
                          help="How long to record, e.g. 3h, 90m, 1h30m (default: until Ctrl+C)")
    _add_serial_args(p_record)
    p_record.set_defaults(func=cmd_record)

    # Keep our lines in order with the cmake/programmer output when piped
    sys.stdout.reconfigure(line_buffering=True)
    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()

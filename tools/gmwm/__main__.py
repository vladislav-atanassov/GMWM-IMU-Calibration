#!/usr/bin/env python3
"""GMWM CLI — build, clean, flash, and monitor the NUCLEO-H755ZI-Q firmware."""

import argparse
import os
import shutil
import statistics
import struct
import subprocess
import sys
from pathlib import Path

import serial
import serial.tools.list_ports

_HERE = Path(__file__).parent

DEFAULT_BAUD = 921600
PRESET = "Debug"
CORES = ("CM7", "CM4")

# Packet header from App/Stream/stream.h, little-endian:
#   uint32 magic, uint16 source, uint16 length, uint32 seq
STREAM_MAGIC = struct.pack("<I", 0xC0DEC0DE)
STREAM_HEADER = struct.Struct("<IHHI")
STREAM_SRC_EMULATOR = 1


def _project_root() -> Path:
    return _HERE.parent.parent


def _firmware_dir() -> Path:
    return _project_root() / "firmware" / "GMWM-IMU-Calibration"


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


def find_serial_port() -> str | None:
    for port in serial.tools.list_ports.comports():
        desc = (port.description or "").lower()
        mfr = (port.manufacturer or "").lower()
        if "stlink" in desc or "stm32" in desc or "stlink" in mfr or "stm" in mfr:
            return port.device
    ports = serial.tools.list_ports.comports()
    return ports[0].device if len(ports) == 1 else None


def read_packets(ser):
    """Yield (source, seq, payload) for each stream packet.

    A packet only counts once the next magic follows its payload, so a magic that
    happens to appear inside the 16-bit ADC data is not taken for a packet start.
    """
    buf = bytearray()
    while True:
        buf += ser.read(ser.in_waiting or 1)
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


def describe_packet(source: int, seq: int, payload: bytes) -> str:
    if source == STREAM_SRC_EMULATOR:
        samples = struct.unpack(f"<{len(payload) // 2}H", payload)
        clean, noisy = samples[0::2], samples[1::2]
        noise = [n - c for c, n in zip(clean, noisy)]
        return (f"seq {seq:7d}  emulator  {len(clean)} frames  clean {min(clean):5d}..{max(clean):5d}  "
                f"noise mean {statistics.fmean(noise):+8.1f}  std {statistics.pstdev(noise):7.1f}")
    return f"seq {seq:7d}  source {source}  {len(payload)} bytes"


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
    port = args.port or find_serial_port()
    if not port:
        print("[!] No serial port found. Specify -p/--port (e.g. -p COM4).")
        sys.exit(1)
    baud = args.baud_rate
    print(f"[*] Opening stream monitor on {port} at {baud} baud. Press Ctrl+C to exit.")
    try:
        ser = serial.Serial(port, baud, timeout=0.5)
    except serial.SerialException as e:
        print(f"[!] Cannot open {port} (is MATLAB or another monitor using it?): {e}")
        sys.exit(1)
    last_seq = None
    try:
        for source, seq, payload in read_packets(ser):
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


# ---- Entry point ----

def _add_serial_args(p):
    p.add_argument("-p", "--port", default=None, help="Serial port (auto-detected if omitted)")
    p.add_argument("-b", "--baud-rate", type=int, default=DEFAULT_BAUD,
                   help=f"Baud rate (default: {DEFAULT_BAUD})")


def main():
    parser = argparse.ArgumentParser(
        prog="gmwm",
        description="GMWM build, clean, flash, and monitor CLI",
    )
    sub = parser.add_subparsers(dest="command", required=True)

    p_build = sub.add_parser("build", help=f"Build both cores ({PRESET})")
    p_build.set_defaults(func=cmd_build)

    p_clean = sub.add_parser("clean", help="Remove the build directories")
    p_clean.set_defaults(func=cmd_clean)

    p_flash = sub.add_parser("flash", help="Build, then flash both cores over SWD")
    p_flash.set_defaults(func=cmd_flash)

    p_monitor = sub.add_parser("monitor", help="Decode the USART3 stream, one line per block")
    _add_serial_args(p_monitor)
    p_monitor.set_defaults(func=cmd_monitor)

    p_flash_monitor = sub.add_parser("flash-monitor", help="Build, flash, then monitor")
    _add_serial_args(p_flash_monitor)
    p_flash_monitor.set_defaults(func=cmd_flash_monitor)

    # Keep our lines in order with the cmake/programmer output when piped
    sys.stdout.reconfigure(line_buffering=True)
    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Run an experiment, or rebuild the results pages from the experiments' outputs.

    python experiments/run.py E01             run one experiment (its ID or full folder name)
    python experiments/run.py --all           run every experiment
    python experiments/run.py --report        only rebuild RESULTS.md and the index in experiments/README.md
    python experiments/run.py --check         is everything ready to commit? (the pre-commit hook runs this)

experiments/README.md describes an experiment folder, what its entry script gets, and what
it must write.
"""

import argparse
import csv
import datetime
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

EXPERIMENTS = Path(__file__).resolve().parent
ROOT = EXPERIMENTS.parent
LIB = EXPERIMENTS / "lib"
DATA = ROOT / "data"
CACHE = DATA / "cache"
RESULTS = ROOT / "RESULTS.md"
INDEX = EXPERIMENTS / "README.md"
INDEX_START, INDEX_END = "<!-- index:start -->", "<!-- index:end -->"

# Entry script name -> command; the working directory is the experiment folder
ENTRIES = {
    "main.m": lambda: [_tool("matlab"), "-batch", f"addpath('{LIB.as_posix()}'); main"],
}

# Only what varies from row to row: the experiment, its data and its method are in config.json
COLUMNS = {
    "params.csv": ["sensor", "axis", "term", "parameter", "value", "unit", "ci_low", "ci_high"],
    "wv.csv": ["sensor", "axis", "scale_s", "nu2", "ci_low", "ci_high", "nu2_model"],
    "fit.csv": ["sensor", "axis", "objective", "scales", "seconds"],
}
# One unit per quantity and sensor, so results compare without conversions (see experiments/README.md)
UNITS = {
    "gyro": {"density": "mdps/sqrt(Hz)", "tc": "s", "std": "mdps", "K": "mdps/sqrt(s)", "nu2": "mdps^2"},
    "accel": {"density": "ug/sqrt(Hz)", "tc": "s", "std": "ug", "K": "ug/sqrt(s)", "nu2": "ug^2"},
}


class ExperimentError(Exception):
    pass


def _tool(name: str) -> str:
    path = shutil.which(name)
    if not path:
        raise ExperimentError(f"{name} is not on PATH")
    return path


def _git(*args: str) -> str:
    return subprocess.run(["git", *args], cwd=ROOT, capture_output=True, text=True, check=True).stdout.strip()


def _sha256(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def _text_sha256(path: Path) -> str:
    """SHA-256 of a text file with CRLF read as LF, so git's line-ending conversion on checkout
    does not look like a change."""
    return hashlib.sha256(path.read_bytes().replace(b"\r\n", b"\n")).hexdigest()


def _rel(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def _exp_id(exp: Path) -> str:
    return exp.name.split("-")[0]


def _config(exp: Path) -> dict:
    return json.loads((exp / "config.json").read_text(encoding="utf-8"))


def _run_info(exp: Path) -> dict | None:
    path = exp / "out" / "run.json"
    return json.loads(path.read_text(encoding="utf-8")) if path.is_file() else None


# ---- Data ----

def datasets() -> dict:
    """The rows of the table in data/README.md, by the Dataset column."""
    rows, header = {}, None
    for line in (DATA / "README.md").read_text(encoding="utf-8").splitlines():
        if not line.startswith("|"):
            header = None
            continue
        cells = [c.strip().strip("`") for c in line.strip().strip("|").split("|")]
        if header is None:
            header = [c.lower() for c in cells]
        elif not set(line) <= set("|-: "):
            row = dict(zip(header, cells))
            if row.get("dataset"):
                rows[row["dataset"]] = row
    return rows


def decode_window(path: Path, window_s: list) -> tuple[dict, bytes]:
    """The samples of a gmwm record log within window_s, as read_imu_log.m reads them.

    Keeps whole blocks only, timed by seq so a lost block keeps its place in time. Returns
    the header for the cache and the samples: int16 raw codes, [gx gy gz ax ay az] per sample.
    """
    # Here, not at the top, so --check runs without the gmwm package (and pyserial) installed
    from gmwm.__main__ import (IMU_ACCEL_G_PER_LSB, IMU_GYRO_DPS_PER_LSB, IMU_ODR_HZ, STREAM_HEADER, STREAM_MAGIC,
                               STREAM_SRC_LSM6DS3TRC)

    data = path.read_bytes()
    _, _, length, _ = STREAM_HEADER.unpack_from(data, 0)
    size = STREAM_HEADER.size + length
    k = len(data) // size
    if k * size != len(data):
        print(f"[!] {path.name}: the last {len(data) - k * size} bytes are an incomplete packet; ignored")

    seqs, ctrl = [], set()
    for i in range(k):
        _, source, n, seq = STREAM_HEADER.unpack_from(data, i * size)
        if data[i * size:i * size + 4] != STREAM_MAGIC or source != STREAM_SRC_LSM6DS3TRC or n != length:
            raise ExperimentError(f"{path.name}: packet {i} is not an LSM6DS3TR-C packet of {length} bytes")
        seqs.append(seq)
        ctrl.add(data[i * size + 12:i * size + 14])
    if len(ctrl) != 1:
        raise ExperimentError(f"{path.name}: the IMU settings change within the log")
    if any(b <= a for a, b in zip(seqs, seqs[1:])):
        raise ExperimentError(f"{path.name}: the sequence restarts, so the board reset during the log")
    ctrl1_xl, ctrl2_g = next(iter(ctrl))
    fs = IMU_ODR_HZ[ctrl2_g >> 4]

    per_block = (length - 4) // 12
    lo, hi = window_s[0] * fs, window_s[1] * fs
    keep = [i for i, s in enumerate(seqs) if (s - seqs[0]) * per_block >= lo and (s - seqs[0] + 1) * per_block <= hi]
    if not keep:
        raise ExperimentError(f"{path.name}: no whole block within {window_s[0]:g}..{window_s[1]:g} s")
    samples = b"".join(data[i * size + STREAM_HEADER.size + 4:(i + 1) * size] for i in keep)
    n = len(keep) * per_block
    t0 = (seqs[keep[0]] - seqs[0]) * per_block / fs
    header = {
        "format": "int16 little-endian raw codes, one sample after another, columns as listed",
        "columns": ["gx", "gy", "gz", "ax", "ay", "az"],
        "samples": n,
        "fs": fs,
        "gyro_scale": IMU_GYRO_DPS_PER_LSB[ctrl2_g & 0x0E],
        "accel_scale": IMU_ACCEL_G_PER_LSB[ctrl1_xl & 0x0C],
        "t0_s": t0,
        "window_s": f"{t0:g}-{t0 + n / fs:g}",
        "lost_blocks": sum(seqs[b] - seqs[a] - 1 for a, b in zip(keep, keep[1:])),
    }
    return header, samples


def prepare_data(cfg: dict) -> Path:
    """Checks the dataset against data/README.md and decodes its window once into data/cache/."""
    name = cfg["dataset"]
    row = datasets().get(name)
    if row is None:
        raise ExperimentError(f"dataset {name} is not in data/README.md")
    path = DATA / row["file"]
    if not path.is_file():
        raise ExperimentError(f"{_rel(path)} is missing: see data/README.md for how to get it")
    sha = _sha256(path)
    if sha != row["sha-256"]:
        raise ExperimentError(f"{_rel(path)} does not match its SHA-256 in data/README.md")

    window_s = [h * 3600 for h in cfg["window_h"]] if "window_h" in cfg else [0, float("inf")]
    tag = "all" if "window_h" not in cfg else "-".join(f"{w:g}" for w in window_s)
    head_path = CACHE / f"{name}_{tag}.json"
    if head_path.is_file():
        header = json.loads(head_path.read_text(encoding="utf-8"))
        if header.get("source_sha256") == sha and (CACHE / header["samples_file"]).is_file():
            return head_path

    print(f"[*] Decoding {path.name}, window {tag} s, into {_rel(CACHE)}/")
    header, samples = decode_window(path, window_s)
    header = {"dataset": name, "source_sha256": sha, "samples_file": head_path.with_suffix(".i16").name, **header}
    CACHE.mkdir(parents=True, exist_ok=True)
    (CACHE / header["samples_file"]).write_bytes(samples)
    head_path.write_text(json.dumps(header, indent=2), encoding="utf-8")
    return head_path


# ---- What a run depends on ----

def code_files(exp: Path) -> list[Path]:
    """The code a run depends on: the experiment's entry script, the helpers in lib/, and every
    repository path the entry script names with exp_path(...)."""
    roots = [LIB]
    for entry in ENTRIES:
        if (exp / entry).is_file():
            roots.append(exp / entry)
            text = (exp / entry).read_text(encoding="utf-8")
            roots += [ROOT / p for p in re.findall(r"""exp_path\(\s*["']([^"']+)["']""", text)]
    files = set()
    for root in roots:
        candidates = [root] if root.is_file() else root.rglob("*")
        files.update(p for p in candidates
                     if p.is_file() and "__pycache__" not in p.parts and p.suffix not in (".asv", ".pyc"))
    return sorted(files)


def inputs(exp: Path) -> dict:
    """Everything a run's outputs follow from, by path: SHA-256 of its config and code, and the
    dataset's checksum as data/README.md declares it (run.py checks the file against it)."""
    files = [exp / "config.json"] + code_files(exp)
    found = {_rel(p): _text_sha256(p) for p in files}
    row = datasets().get(_config(exp).get("dataset"))
    if row:
        found[f"data/{row['file']}"] = row["sha-256"]
    return found


def stale_reasons(exp: Path) -> list[str]:
    """Why the outputs in out/ do not follow from the experiment's inputs; empty when they do."""
    info = _run_info(exp)
    if info is None:
        return ["never run"]
    if "inputs" not in info:
        return ["run.json has no inputs"]
    now = inputs(exp)
    changed = sorted(p for p in set(now) | set(info["inputs"]) if now.get(p) != info["inputs"].get(p))
    return [f"changed since the run: {', '.join(changed)}"] if changed else []


# ---- Running ----

def find_experiment(name: str) -> Path:
    matches = [p for p in EXPERIMENTS.iterdir() if p.is_dir() and (p.name == name or p.name.startswith(name + "-"))]
    if len(matches) != 1:
        raise ExperimentError(f"no single experiment folder matches {name!r}")
    return matches[0]


def all_experiments() -> list[Path]:
    return sorted(p for p in EXPERIMENTS.iterdir() if (p / "config.json").is_file())


def check_outputs(out: Path):
    """Every output has the agreed columns and units, so the report can compare it with the others."""
    if not (out / "params.csv").is_file():
        raise ExperimentError("the run wrote no params.csv")
    for name, columns in COLUMNS.items():
        path = out / name
        if not path.is_file():
            continue
        with open(path, newline="", encoding="utf-8") as f:
            reader = csv.DictReader(f)
            if reader.fieldnames != columns:
                raise ExperimentError(f"{name} columns are {reader.fieldnames}, expected {columns}")
            rows = list(reader)
        if not rows:
            raise ExperimentError(f"{name} is empty")
        for r in rows:
            units = UNITS.get(r["sensor"])
            if units is None:
                raise ExperimentError(f"{name}: unknown sensor {r['sensor']!r}")
            if name == "params.csv" and units.get(r["parameter"]) != r["unit"]:
                raise ExperimentError(f"{name}: {r['sensor']} {r['parameter']} in {r['unit']!r}, "
                                      f"expected {units.get(r['parameter'])!r}")


def run(exp: Path, force: bool):
    cfg = _config(exp)
    if cfg.get("status") not in ("draft", "final"):
        raise ExperimentError("config.json status must be draft or final")
    final = cfg["status"] == "final"
    entries = [e for e in ENTRIES if (exp / e).is_file()]
    if len(entries) != 1:
        raise ExperimentError(f"{exp.name} needs exactly one entry script of {', '.join(ENTRIES)}")
    entry = entries[0]

    used = inputs(exp)
    out = exp / "out"
    if final:
        local = [p for p in used if not p.startswith("data/")]
        if _git("status", "--porcelain", "--", *local):
            raise ExperimentError("a final run needs its config and code committed, so a commit holds exactly "
                                  "what it ran; commit them first")
        if not force and not stale_reasons(exp):
            raise ExperimentError(f"{_rel(out)} already holds this final run; --force runs it again")

    head_path = prepare_data(cfg)

    stage = exp / "out.tmp"
    if stage.exists():
        shutil.rmtree(stage)  # left by a run that failed
    stage.mkdir()
    env = {**os.environ, "EXP_ID": _exp_id(exp), "EXP_ROOT": str(ROOT),
           "EXP_CONFIG": str(exp / "config.json"), "EXP_DATA": str(head_path), "EXP_OUT": str(stage)}

    print(f"[*] {exp.name}: {entry}, {cfg['status']} run")
    start = time.monotonic()
    with open(stage / "log.txt", "w", encoding="utf-8") as log:
        proc = subprocess.Popen(ENTRIES[entry](), cwd=exp, env=env, stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT)
        for raw in proc.stdout:
            line = raw.decode("utf-8", errors="replace").rstrip("\r\n")
            print(f"    {line}")
            log.write(line + "\n")
        proc.wait()
    seconds = time.monotonic() - start
    if proc.returncode != 0:
        raise ExperimentError(f"{entry} failed (exit {proc.returncode}); its output is in {_rel(stage)}/log.txt")

    check_outputs(stage)

    run_info = {
        "date": datetime.datetime.now().astimezone().isoformat(timespec="seconds"),
        "seconds": round(seconds, 1),
        "base_commit": _git("rev-parse", "HEAD"),
        "inputs": used,
    }
    (stage / "run.json").write_text(json.dumps(run_info, indent=2) + "\n", encoding="utf-8", newline="\n")

    if out.exists():
        shutil.rmtree(out)  # git keeps the outputs of earlier runs
    stage.rename(out)
    print(f"[+] {exp.name}: done in {seconds:.0f} s, outputs in {_rel(out)}/")


# ---- Report ----

def _read_csv(path: Path) -> list[dict]:
    if not path.is_file():
        return []
    with open(path, newline="", encoding="utf-8") as f:
        return list(csv.DictReader(f))


def _num(text: str) -> str:
    try:
        return f"{float(text):.3g}"
    except ValueError:
        return text


def _readme_facts(exp: Path) -> tuple[str, str]:
    """The experiment README's title and its **Conclusion:** line."""
    title, conclusion = exp.name, ""
    readme = exp / "README.md"
    if readme.is_file():
        for line in readme.read_text(encoding="utf-8").splitlines():
            if line.startswith("# ") and title == exp.name:
                title = line[2:].strip()
            elif line.startswith("**Conclusion:**"):
                conclusion = line[len("**Conclusion:**"):].strip()
    return title, conclusion


def _window(cfg: dict) -> str:
    return f"{cfg['window_h'][0]:g} to {cfg['window_h'][1]:g} h" if "window_h" in cfg else "whole log"


def build_report() -> tuple[str, str]:
    """RESULTS.md and experiments/README.md as they should read, from every experiment's out/."""
    runs = []
    for exp in all_experiments():
        cfg, info = _config(exp), _run_info(exp)
        current = info is not None and not stale_reasons(exp)
        runs.append((exp, cfg, info, current, _read_csv(exp / "out/params.csv"), _read_csv(exp / "out/fit.csv")))

    # Index
    rows = ["| ID | Experiment | Data | Status | Last run | Conclusion |", "| --- | --- | --- | --- | --- | --- |"]
    for exp, cfg, info, current, _, _ in runs:
        title, conclusion = _readme_facts(exp)
        last = f"{info['date'][:10]}, {'current' if current else 'stale'}" if info else "not run"
        rows.append(f"| [{_exp_id(exp)}]({exp.name}/) | {title} | {cfg['dataset']}, {_window(cfg)} | {cfg['status']} "
                    f"| {last} | {conclusion} |")
    text = INDEX.read_text(encoding="utf-8")
    a, b = text.index(INDEX_START) + len(INDEX_START), text.index(INDEX_END)
    index = text[:a] + "\n" + "\n".join(rows) + "\n" + text[b:]

    # Results: one section per dataset, window and sensor; one column per experiment
    groups = {}
    for exp, cfg, info, current, params, fits in runs:
        for r in params + fits:
            key = (cfg["dataset"], _window(cfg), r["sensor"])
            col = groups.setdefault(key, {}).setdefault(exp, {"cfg": cfg, "current": current, "params": [], "fits": []})
            col["params" if "term" in r else "fits"].append(r)

    lines = ["# Results", "",
             "Generated by `python experiments/run.py --report` from each experiment's `out/`; do not edit by hand.",
             "How the experiments run, and the units: [experiments/README.md](experiments/README.md).", ""]
    for (dataset, window, sensor), cols in sorted(groups.items()):
        exps = sorted(cols)
        lines += [f"## {dataset}, {window}: {sensor}", ""]
        heads = []
        for exp in exps:
            c = cols[exp]
            note = "" if c["cfg"]["status"] == "final" and c["current"] else \
                " (stale)" if not c["current"] else " (draft)"
            heads.append(f"[{_exp_id(exp)}](experiments/{exp.name}/) {c['cfg'].get('method', '')}{note}")
        lines += ["| Axis | Term | Parameter | Unit | " + " | ".join(heads) + " |",
                  "| --- | --- | --- | --- | " + " | ".join("---:" for _ in exps) + " |"]
        keys = []
        for exp in exps:
            for r in cols[exp]["params"]:
                k = (r["axis"], r["term"], r["parameter"], r["unit"])
                if k not in keys:
                    keys.append(k)
        for k in keys:
            cells = []
            for exp in exps:
                r = next((r for r in cols[exp]["params"] if (r["axis"], r["term"], r["parameter"], r["unit"]) == k),
                         None)
                cell = ""
                if r:
                    cell = _num(r["value"])
                    if r["ci_low"] and r["ci_high"]:
                        cell += f" [{_num(r['ci_low'])}, {_num(r['ci_high'])}]"
                cells.append(cell)
            lines.append(f"| {' | '.join(k)} | " + " | ".join(cells) + " |")
        lines += ["", "| Axis | Fit | " + " | ".join(f"[{_exp_id(e)}](experiments/{e.name}/)" for e in exps) + " |",
                  "| --- | --- | " + " | ".join("---:" for _ in exps) + " |"]
        for axis in sorted({r["axis"] for exp in exps for r in cols[exp]["fits"]}):
            for field, label in (("objective", "objective"), ("scales", "scales"), ("seconds", "run time [s]")):
                cells = [next((_num(r[field]) for r in cols[exp]["fits"] if r["axis"] == axis), "") for exp in exps]
                lines.append(f"| {axis} | {label} | " + " | ".join(cells) + " |")
        lines.append("")
        for exp in exps:
            for png in sorted((exp / "out").glob(f"{sensor}*.png")):
                lines += [f"**{_exp_id(exp)}:** `{png.name}`", "", f"![{exp.name} {png.stem}]({_rel(png)})", ""]
    return "\n".join(lines), index


def report():
    """Rebuilds RESULTS.md and the index in experiments/README.md."""
    results, index = build_report()
    RESULTS.write_text(results, encoding="utf-8", newline="\n")
    INDEX.write_text(index, encoding="utf-8", newline="\n")
    print(f"[+] Rebuilt {_rel(RESULTS)} and the index in {_rel(INDEX)}")


def check() -> bool:
    """Is the working tree ready to commit? Prints what is not, and returns False when something
    blocks: a final experiment whose outputs do not follow from its inputs, a README without
    its title or conclusion, or results pages that need rebuilding. A stale draft only warns."""
    errors, warnings = [], []
    for exp in all_experiments():
        title, conclusion = _readme_facts(exp)
        if not title.startswith(f"{_exp_id(exp)}:"):
            errors.append(f"{exp.name}: README.md needs a title line '# {_exp_id(exp)}: ...'")
        if not conclusion:
            errors.append(f"{exp.name}: README.md needs a line starting with **Conclusion:**")
        final = _config(exp).get("status") == "final"
        for reason in stale_reasons(exp):
            (errors if final else warnings).append(f"{exp.name}: {reason}. Rerun: python experiments/run.py "
                                                   f"{_exp_id(exp)}")

    results, index = build_report()
    on_disk = RESULTS.read_text(encoding="utf-8") if RESULTS.is_file() else ""
    if results != on_disk or index != INDEX.read_text(encoding="utf-8"):
        errors.append("RESULTS.md or the index in experiments/README.md is out of date. "
                      "Rebuild: python experiments/run.py --report")

    for e in errors:
        print(f"[!] {e}")
    for w in warnings:
        print(f"[~] {w}")
    if errors:
        print(f"[!] Experiments: {len(errors)} problem(s) block a commit")
    else:
        print("[+] Experiments: ready to commit" + (f", with {len(warnings)} warning(s) on drafts" if warnings else ""))
    return not errors


def main():
    parser = argparse.ArgumentParser(description="Run experiments and rebuild the results pages")
    parser.add_argument("experiment", nargs="?", help="Experiment ID (E01) or folder name")
    parser.add_argument("--all", action="store_true", help="Run every experiment")
    parser.add_argument("--report", action="store_true", help="Only rebuild RESULTS.md and the index")
    parser.add_argument("--check", action="store_true", help="Only check that everything is ready to commit")
    parser.add_argument("--force", action="store_true", help="Run a final experiment again although it is current")
    args = parser.parse_args()
    if not (args.experiment or args.all or args.report or args.check):
        parser.error("name an experiment, or pass --all, --report or --check")

    sys.stdout.reconfigure(line_buffering=True)
    if args.check:
        sys.exit(0 if check() else 1)
    try:
        if not args.report:
            for exp in all_experiments() if args.all else [find_experiment(args.experiment)]:
                run(exp, args.force)
        report()
    except ExperimentError as e:
        print(f"[!] {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()

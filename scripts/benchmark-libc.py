#!/usr/bin/env python3
"""Compare lmnum binaries on the same numerical DSL program.

The benchmark deliberately runs an already compiled simulation bytecode file,
so rendering, lmscript compilation, network installation, and lmplot are not
part of the libc comparison.  Each run must complete successfully; lmnum's
own numerical assertions therefore remain part of the measurement gate.
"""

from __future__ import annotations

import argparse
import json
import os
import platform
import resource
import shutil
import subprocess
import sys
import time
from pathlib import Path


def command_output(command: list[str]) -> str:
    try:
        result = subprocess.run(command, check=False, capture_output=True, text=True, timeout=10)
    except (OSError, subprocess.TimeoutExpired) as exc:
        return str(exc)
    return (result.stdout + result.stderr).strip()


def one_run(binary: Path, dsl: Path, timeout_s: float) -> tuple[float, int, str]:
    started = time.perf_counter()
    try:
        result = subprocess.run(
            [str(binary), "--dsl", str(dsl)],
            check=False,
            capture_output=True,
            text=True,
            timeout=timeout_s,
            env=os.environ.copy(),
        )
    except subprocess.TimeoutExpired as exc:
        elapsed = time.perf_counter() - started
        return elapsed, 124, f"timeout after {timeout_s:g}s: {exc}"
    elapsed = time.perf_counter() - started
    output = (result.stdout + result.stderr).strip()
    return elapsed, result.returncode, output


def measure(binary: Path, dsl: Path, warmups: int, repeats: int, timeout_s: float) -> dict[str, object]:
    warmup_times: list[float] = []
    for _ in range(warmups):
        elapsed, code, output = one_run(binary, dsl, timeout_s)
        if code != 0:
            raise RuntimeError(f"{binary}: warmup failed with exit {code}: {output[-1000:]}")
        warmup_times.append(elapsed)
    measured: list[float] = []
    output = ""
    for _ in range(repeats):
        elapsed, code, output = one_run(binary, dsl, timeout_s)
        if code != 0:
            raise RuntimeError(f"{binary}: measured run failed with exit {code}: {output[-1000:]}")
        measured.append(elapsed)
    ordered = sorted(measured)
    median = ordered[len(ordered) // 2]
    return {
        "binary": str(binary),
        "version": command_output([str(binary), "--version"]),
        "warmup_seconds": warmup_times,
        "seconds": measured,
        "median_seconds": median,
        "assertions_and_output_tail": output[-1000:],
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--glibc", type=Path, required=True, help="glibc-linked baseline binary")
    parser.add_argument("--musl", type=Path, required=True, help="musl-linked binary")
    parser.add_argument("--dsl", type=Path, required=True, help="compiled numerical simulation bytecode")
    parser.add_argument("--output", type=Path, required=True, help="JSON result path")
    parser.add_argument("--warmups", type=int, default=2)
    parser.add_argument("--repeats", type=int, default=5)
    parser.add_argument("--timeout", type=float, default=120.0)
    args = parser.parse_args()
    if args.warmups < 0 or args.repeats < 3 or args.timeout <= 0:
        parser.error("warmups must be nonnegative, repeats must be at least 3, timeout must be positive")
    for path in (args.glibc, args.musl, args.dsl):
        if not path.is_file():
            parser.error(f"missing file: {path}")
    result: dict[str, object] = {
        "program": str(args.dsl),
        "purpose": "same-machine libc comparison of numerical lmnum execution only",
        "excluded": ["lmscript compilation", "lmplot/lmdraw rendering", "network installation"],
        "host": {
            "platform": platform.platform(),
            "machine": platform.machine(),
            "python": sys.version,
            "compiler": command_output(["cc", "--version"]) if shutil.which("cc") else "unavailable",
            "glibc_toolchain": command_output(["ldd", "--version"]) if shutil.which("ldd") else "unavailable",
            "musl_toolchain": command_output(["musl-gcc", "--version"]) if shutil.which("musl-gcc") else "container binary; musl-gcc unavailable on host",
            "file_glibc": command_output(["file", str(args.glibc)]),
            "file_musl": command_output(["file", str(args.musl)]),
        },
        "settings": {"warmups": args.warmups, "repeats": args.repeats, "timeout_seconds": args.timeout},
        "limits": {
            "LMNUM_MAX_MEMORY_MB": os.environ.get("LMNUM_MAX_MEMORY_MB", "4096 (default)"),
            "virtual_memory_limit_bytes": resource.getrlimit(resource.RLIMIT_AS)[0],
            "per_run_timeout_seconds": args.timeout,
        },
    }
    try:
        result["glibc"] = measure(args.glibc, args.dsl, args.warmups, args.repeats, args.timeout)
        result["musl"] = measure(args.musl, args.dsl, args.warmups, args.repeats, args.timeout)
    except RuntimeError as exc:
        print(str(exc), file=sys.stderr)
        return 1
    glibc_time = float(result["glibc"]["median_seconds"])  # type: ignore[index]
    musl_time = float(result["musl"]["median_seconds"])  # type: ignore[index]
    result["musl_vs_glibc"] = {
        "ratio": musl_time / glibc_time,
        "regression_percent": (musl_time / glibc_time - 1.0) * 100.0,
        "mimalloc_threshold_percent": 20.0,
        "mimalloc_needed": musl_time > glibc_time * 1.20,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(result["musl_vs_glibc"], indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""Compile one gallery simulation block into libc benchmark bytecode.

Only the first ``sim = _dsl_`` block is retained.  The draw block and all
outer lmscript commands are intentionally excluded so the resulting fixture
contains numerical assertions but no rendering or network activity.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
import tempfile
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--timeout", type=float, default=60.0)
    args = parser.parse_args()
    source = args.source.resolve()
    output = args.output.resolve()
    if not source.is_file():
        parser.error(f"missing source: {source}")
    text = source.read_text(encoding="utf-8")
    lines = text.splitlines(keepends=True)
    try:
        first = next(i for i, line in enumerate(lines) if "sim = _dsl_" in line)
        last = next(i for i in range(first, len(lines)) if lines[i].strip() == "end _dsl_")
    except StopIteration:
        parser.error(f"no complete sim _dsl_ block in {source}")
    schema = Path(__file__).resolve().parents[1] / "schema" / "lmnum.dsl.json"
    block = "sim = _dsl_ schema=" + json.dumps(str(schema)) + ";\n" + "".join(lines[first + 1 : last + 1])
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="lmnum-libc-prepare-") as work:
        wrapper = Path(work) / "simulation.lms"
        wrapper.write_text(block + "\nsavedsl(sim, " + json.dumps(str(output)) + ");\n", encoding="utf-8")
        try:
            result = subprocess.run(
                ["lmscript", str(wrapper)],
                check=False,
                capture_output=True,
                text=True,
                timeout=args.timeout,
                cwd=work,
            )
        except (OSError, subprocess.TimeoutExpired) as exc:
            parser.error(f"lmscript failed: {exc}")
        if result.returncode != 0 or not output.is_file():
            print(result.stdout, end="")
            print(result.stderr, end="")
            return result.returncode or 1
    manifest = {
        "source": str(source),
        "source_sha256": hashlib.sha256(source.read_bytes()).hexdigest(),
        "fixture": str(output),
        "fixture_sha256": hashlib.sha256(output.read_bytes()).hexdigest(),
        "block": {"first_line": first + 1, "last_line": last + 1},
        "binding": "repository schema; no host lookup or install",
        "excluded": ["draw _dsl_ block", "outer lmscript commands", "lmplot", "network installation"],
    }
    manifest_path = output.with_suffix(output.suffix + ".manifest.json")
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(manifest, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

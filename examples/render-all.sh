#!/usr/bin/env bash
# Regenerate every picture in docs/images from the gallery examples (needs lmscript, compatible lmplot on PATH, ffmpeg for the GIF).
# Each example writes images/*.png in the current directory; this script runs them from the repo root and copies the results.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
export PATH="$PWD/build:$PATH"
lmplot --lmcode-schema --json >/dev/null || { echo "compatible lmplot required on PATH" >&2; exit 1; }
lmdraw --lmcode-schema --json >/dev/null || { echo "compatible lmdraw required on PATH" >&2; exit 1; }
mkdir -p docs/images
for src in examples/gallery/*.lms; do
  echo "== $src"
  timeout 300 lmscript "$src"
done
cp images/*.png images/*.gif docs/images/
ls -la docs/images

#!/usr/bin/env bash
# Refresh the README preview after a test run with the combo example: ./test.sh && scripts/update-renders.sh
set -eu
cd "$(dirname "${BASH_SOURCE[0]}")/.."
cp build/examples/lorenz.png examples/renders/lorenz.png

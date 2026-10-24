#!/usr/bin/env bash
# Run the complete Linux build and test inside the pinned native-architecture
# Alpine image. The source tree is mounted so build/ and fetched dependencies
# are available to the following packaging step.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="${LMNUM_MUSL_IMAGE:-lmnum-musl:3.23-20261023}"

command -v docker >/dev/null 2>&1 || {
  echo "error: Docker is required for the Linux musl build" >&2
  exit 2
}

timeout 1800 docker build --pull=false -f "$HERE/Dockerfile.musl" -t "$IMAGE" "$HERE"
timeout 1800 docker run --rm \
  --mount "type=bind,src=$HERE,dst=/workspace" \
  --env LMNUM_TEST_NETWORK="${LMNUM_TEST_NETWORK:-1}" \
  --env GITHUB_TOKEN="${GITHUB_TOKEN:-}" \
  "$IMAGE" -lc '
    set -euo pipefail
    printf "Alpine %s\\n" "$(cat /etc/alpine-release)"
    gcc --version | head -1
    apk info --who-owns /usr/lib/libc.a
    apk info --who-owns /usr/lib/libm.a
    git config --global --add safe.directory "*"
    npm i -g @lmctl-ai/lmctl@0.2.369
    scripts/select-compiler.sh | tee compiler.txt
    grep -q lmscript compiler.txt
    BUILD_DIR="${LMNUM_MUSL_BUILD_DIR:-build-musl}" \
      LMNUM_REQUIRE_MUSL=1 ./test.sh
  '

file "$HERE/${LMNUM_MUSL_BUILD_DIR:-build-musl}/lmnum" | grep -E 'statically linked|static-pie linked'
if command -v ldd >/dev/null 2>&1; then
  ldd "$HERE/${LMNUM_MUSL_BUILD_DIR:-build-musl}/lmnum" 2>&1 | grep -q 'not a dynamic executable'
fi

#!/usr/bin/env bash
# Native-architecture Alpine build, then a runtime smoke with no container libc.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="${LMNUM_MUSL_IMAGE:-lmnum-musl:3.23-20261023}"
MUSL_BUILD_DIR="${LMNUM_MUSL_BUILD_DIR:-build-musl}"
command -v docker >/dev/null 2>&1 || { echo "Docker is required for the musl release build" >&2; exit 2; }

timeout 1800 docker build --pull=false -f "$HERE/Dockerfile.musl" -t "$IMAGE" "$HERE"
timeout 1800 docker run --rm --init \
  --mount "type=bind,src=$HERE,dst=/workspace" \
  --env LMNUM_TEST_NETWORK="${LMNUM_TEST_NETWORK:-1}" \
  --env LMNUM_MUSL_BUILD_DIR="$MUSL_BUILD_DIR" \
  --env LMNUM_USE_MIMALLOC="${LMNUM_USE_MIMALLOC:-ON}" \
  --env LMNUM_HOST_UID="$(id -u)" --env LMNUM_HOST_GID="$(id -g)" \
  --env GITHUB_TOKEN \
  "$IMAGE" -lc '
    set -euo pipefail
    mkdir -p "$LMNUM_MUSL_BUILD_DIR"
    {
      grep "^FROM " Dockerfile.musl
      printf "Alpine %s\n" "$(cat /etc/alpine-release)"
      timeout 15 gcc --version
      timeout 15 gcc -dumpmachine
      timeout 15 node --version
      timeout 15 npm --version
      timeout 15 apk info --who-owns /usr/lib/libc.a
      timeout 15 apk info --who-owns /usr/lib/libm.a
      timeout 15 c++ -print-file-name=libstdc++.a
      timeout 15 apk info --who-owns /usr/lib/libstdc++.a
    } | tee "$LMNUM_MUSL_BUILD_DIR/musl-provenance.txt"
    timeout 15 git config --global --add safe.directory "*"
    timeout 180 npm i -g @lmctl-ai/lmctl@0.2.369
    timeout 180 scripts/select-compiler.sh | tee compiler.txt
    grep -q lmscript compiler.txt
    tool_dir="$(timeout 300 scripts/fetch-musl-test-tools.sh)"
    export PATH="$tool_dir:$PATH"
    BUILD_DIR="$LMNUM_MUSL_BUILD_DIR" LMNUM_REQUIRE_MUSL=1 timeout 1500 ./test.sh
    grep -F "/usr/lib/libc.a" "$LMNUM_MUSL_BUILD_DIR/lmnum.map" | head -8 || true
    case "$LMNUM_USE_MIMALLOC" in
      ON|1|TRUE|on|true)
        timeout 30 nm --defined-only "$LMNUM_MUSL_BUILD_DIR/mimalloc/CMakeFiles/mimalloc-obj.dir/src/static.c.o" > "$LMNUM_MUSL_BUILD_DIR/mimalloc-symbols.txt"
        if grep -Eq " _Z(n|d)" "$LMNUM_MUSL_BUILD_DIR/mimalloc-symbols.txt"; then
          echo "mimalloc must not bypass the counted C++ operators" >&2; exit 1
        fi
        for symbol in malloc free calloc realloc posix_memalign malloc_usable_size; do
          grep -Eq " [TW] $symbol\$" "$LMNUM_MUSL_BUILD_DIR/mimalloc-symbols.txt"
        done
        timeout 30 nm -C --defined-only "$LMNUM_MUSL_BUILD_DIR/CMakeFiles/lmnum.dir/cpp/memory_budget.cpp.o" > "$LMNUM_MUSL_BUILD_DIR/counted-new-symbols.txt"
        grep -q "operator new" "$LMNUM_MUSL_BUILD_DIR/counted-new-symbols.txt"
        ;;
    esac
    # Host-side benchmark compilation must be able to create output files.
    timeout 60 chown -R "$LMNUM_HOST_UID:$LMNUM_HOST_GID" "$LMNUM_MUSL_BUILD_DIR"
  '

timeout 360 "$HERE/scripts/check-linux-static.sh" \
  "$HERE/$MUSL_BUILD_DIR/lmnum" "$HERE/build/static-smoke.dslb"

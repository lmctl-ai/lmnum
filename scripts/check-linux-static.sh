#!/usr/bin/env bash
# Verify a Linux release host has no dynamic loader or shared-library needs.
# Usage: check-linux-static.sh HOST [SMOKE_BYTECODE]
set -euo pipefail

HOST=${1:?usage: check-linux-static.sh HOST [SMOKE_BYTECODE]}
SMOKE=${2:-}
[ -f "$HOST" ] || { echo "static check: missing host $HOST" >&2; exit 2; }
[ -x "$HOST" ] || { echo "static check: host is not executable: $HOST" >&2; exit 2; }

file_out="$(timeout 20 file -L "$HOST")"
echo "$file_out"
echo "$file_out" | grep -Eiq 'statically linked|static-pie linked' || {
  echo "static check: file did not report a static executable" >&2
  exit 1
}

if command -v readelf >/dev/null 2>&1; then
  program_headers="$(timeout 20 readelf -l "$HOST")"
  dynamic_section="$(timeout 20 readelf -d "$HOST")"
  printf '%s\n' "$program_headers" | grep -q 'INTERP' && {
    echo "static check: PT_INTERP is present" >&2
    exit 1
  } || :
  printf '%s\n' "$dynamic_section" | grep -q 'NEEDED' && {
    echo "static check: DT_NEEDED is present" >&2
    exit 1
  } || :
else
  echo "static check: readelf unavailable; file result is the loader check" >&2
fi

# ldd is diagnostic rather than a portable oracle: glibc and musl use different
# text and exit statuses for a static binary. Capture both without assuming
# either spelling, and reject only a concrete shared-object dependency.
if command -v ldd >/dev/null 2>&1; then
  set +e
  ldd_out="$(timeout 20 ldd "$HOST" 2>&1)"
  ldd_status=$?
  set -e
  printf '%s\n' "$ldd_out"
  # A static executable is reported differently by glibc and musl. The
  # diagnostics "not a dynamic executable" and "not a valid dynamic program"
  # are both expected. Reject only a concrete shared-object mapping; ELF
  # metadata above remains authoritative for the loader and DT_NEEDED checks.
  if printf '%s\n' "$ldd_out" | grep -Eiq '=>[[:space:]]+(/|[A-Za-z]:\\).*\.so([.[:space:]]|$)'; then
    echo "static check: ldd reported a shared-library dependency" >&2
    exit 1
  fi
  echo "static check: ldd diagnostic captured (exit $ldd_status)"
else
  echo "static check: ldd unavailable; readelf checks are authoritative"
fi

version="$(timeout 30 "$HOST" --version)"
echo "$version"
case "$version" in
  "lmnum "*) : ;;
  *) echo "static check: unexpected --version output" >&2; exit 1;;
esac

if [ -n "$SMOKE" ]; then
  [ -f "$SMOKE" ] || { echo "static check: missing smoke bytecode $SMOKE" >&2; exit 2; }
  smoke_out="$(mktemp "${TMPDIR:-/tmp}/lmnum-static-smoke.XXXXXX")"
  trap 'rm -f "$smoke_out"' EXIT
  timeout 120 "$HOST" --dsl "$SMOKE" >"$smoke_out"
  grep -q '"ok": true' "$smoke_out" || {
    echo "static check: smoke fixture did not report JSON ok" >&2
    cat "$smoke_out" >&2
    exit 1
  }
  echo "static check: runtime smoke passed"
fi

# A host build cannot assume access to the builder's Docker socket. When a
# daemon is available, use a FROM scratch image so this checks the binary with
# no Alpine root filesystem or runtime libraries. In the Alpine build
# container the daemon probe fails and this check is intentionally skipped.
if [ -z "$SMOKE" ]; then
  echo "static check: scratch-container smoke skipped (no smoke bytecode)"
elif ! command -v docker >/dev/null 2>&1; then
  echo "static check: scratch-container smoke skipped (Docker unavailable)"
elif ! timeout 15 docker info >/dev/null 2>&1; then
  echo "static check: scratch-container smoke skipped (Docker daemon unavailable)"
else
  scratch_dir="$(mktemp -d "${TMPDIR:-/tmp}/lmnum-static-image.XXXXXX")"
  scratch_tag="lmnum-static-smoke-$$"
  cleanup_scratch() {
    timeout 30 docker image rm "$scratch_tag" >/dev/null 2>&1 || true
    rm -rf "$scratch_dir"
  }
  trap 'cleanup_scratch; rm -f "$smoke_out" 2>/dev/null || true' EXIT
  cp "$HOST" "$scratch_dir/lmnum"
  cp "$SMOKE" "$scratch_dir/smoke.dslb"
  printf '%s\n' \
    'FROM scratch' \
    'COPY lmnum /lmnum' \
    'COPY smoke.dslb /smoke.dslb' \
    'ENTRYPOINT ["/lmnum"]' >"$scratch_dir/Dockerfile"
  timeout 120 docker build --pull=false --no-cache -t "$scratch_tag" "$scratch_dir" >/dev/null
  timeout 30 docker run --rm --network none --read-only "$scratch_tag" --version
  timeout 120 docker run --rm --network none --read-only "$scratch_tag" --dsl /smoke.dslb >"$smoke_out"
  grep -q '"ok": true' "$smoke_out" || {
    echo "static check: scratch fixture did not report JSON ok" >&2
    cat "$smoke_out" >&2
    exit 1
  }
  echo "static check: FROM scratch runtime smoke passed"
fi

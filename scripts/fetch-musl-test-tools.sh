#!/usr/bin/env bash
# Rendering tools are build-only; pin static versions that run in pure Alpine.
set -euo pipefail
case "$(uname -m)" in x86_64) arch=x64;; aarch64) arch=arm64;; *) exit 2;; esac
root="$(cd "$(dirname "$0")/.." && pwd)"
dir="$root/.ci-tools/linux-$arch"
mkdir -p "$dir"
while read -r tool architecture digest; do
  [ "$architecture" = "$arch" ] || continue
  target="$dir/$tool"
  if ! printf '%s  %s\n' "$digest" "$target" | sha256sum -c - >/dev/null 2>&1; then
    timeout 120 curl --fail --location --retry 3 --retry-all-errors --connect-timeout 15 --max-time 100 \
      "https://github.com/lmctl-ai/$tool/releases/download/v0.1.0/$tool-linux-$arch" -o "$target"
  fi
  printf '%s  %s\n' "$digest" "$target" | sha256sum -c - >&2
  chmod +x "$target"
  timeout 15 file "$target" >&2
  if timeout 15 readelf -lW "$target" | grep -q INTERP; then
    echo "Build-only renderer unexpectedly needs a dynamic loader" >&2; exit 1
  fi
  if [ "$tool" = lmplot ]; then
    timeout 20 "$target" --version >&2
  else
    timeout 20 "$target" --dsl-signatures >/dev/null
  fi
done < "$root/scripts/musl-test-tools.lock"
printf '%s\n' "$dir"

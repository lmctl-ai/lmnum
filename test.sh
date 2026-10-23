#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE"
BUILD_DIR="${BUILD_DIR:-build}"
HOST="$BUILD_DIR/lmnum"
UNAME_S="$(uname -s)"
case "$UNAME_S" in MINGW*|MSYS*|CYGWIN*) HOST="$HOST.exe";; esac
WORK="$(mktemp -d "${TMPDIR:-/tmp}/lmnum-test-XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
ROOT="$HERE"
# Native Windows tools (node, the host) cannot address git-bash /tmp or /d/a paths.
case "$UNAME_S" in MINGW*|MSYS*|CYGWIN*) WORK="$(cd "$WORK" && pwd -W | tr '\\' '/')"; ROOT="$(pwd -W | tr '\\' '/')";; esac
pass=0
ok(){ pass=$((pass+1)); echo "ok $pass - $1"; }
fail(){ echo "FAIL: $*" >&2; exit 1; }
sha(){ if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -c1-64; else shasum -a 256 "$1" | cut -c1-64; fi; }

# lmscript resolves cli="lmnum" on PATH first, so programs bind to the binary under test.
export PATH="$(cd "$BUILD_DIR" 2>/dev/null && pwd || echo "$HERE/$BUILD_DIR"):$PATH"
LMSCRIPT="$(scripts/select-compiler.sh)"
scripts/sync-sdk.sh --verify >/dev/null || fail "SDK header pin mismatch"
ok "SDK header matches sdk.lock"
scripts/sync-deps.sh --verify >/dev/null || fail "third_party pin mismatch"
ok "third_party matches deps.lock"

GEN=""
command -v ninja >/dev/null 2>&1 && GEN="-G Ninja"
# shellcheck disable=SC2086
cmake -S . -B "$BUILD_DIR" $GEN -DCMAKE_BUILD_TYPE=Release >/dev/null
cmake --build "$BUILD_DIR" >"$WORK/build.log" 2>&1 || { tail -40 "$WORK/build.log" >&2; fail "build"; }
ok "build"

want_version="lmnum $(sed -n 's/^project(lmnum VERSION \([0-9.]*\).*/\1/p' CMakeLists.txt)"
[ "$("$HOST" --version)" = "$want_version" ] || fail "--version is not exactly '$want_version'"
ok "--version prints exactly '$want_version'"
python3 scripts/gen-schema.py >/dev/null && git diff --quiet -- schema/lmnum.dsl.json 2>/dev/null || [ ! -e .git ] || fail "schema/lmnum.dsl.json is stale: run scripts/gen-schema.py"
ok "schema matches the registrations in cpp/main.cpp"
"$HOST" --dsl-schema --json >"$WORK/schema.json" || fail "embedded schema print"
cmp -s "$WORK/schema.json" schema/lmnum.dsl.json || fail "embedded schema differs from schema/lmnum.dsl.json"
ok "--dsl-schema --json prints byte-identical embedded schema bytes"
diff -u <("$LMSCRIPT" --dsl-signatures schema/lmnum.dsl.json) <("$HOST" --dsl-signatures) || fail "host/compiler signatures differ"
ok "host registry matches compiler signatures"
"$HOST" --notices | grep -q "SUNDIALS" || fail "--notices missing third-party text"
ok "--notices prints the third-party license texts"

case "$UNAME_S" in
  Linux) if ldd "$HOST" >/dev/null 2>&1; then fail "executable is dynamically linked"; fi; ok "executable is fully static (no dynamic loader)";;
  Darwin) bad="$(otool -L "$HOST" | tail -n +2 | grep -v -E '/usr/lib/(libSystem|libc\+\+|libresolv)' || true)"
          [ -z "$bad" ] || fail "non-system dylib dependencies: $bad"; ok "only system libraries linked";;
  MINGW*|MSYS*|CYGWIN*)
    if command -v objdump >/dev/null 2>&1; then
      bad="$(objdump -p "$HOST" | grep 'DLL Name' | grep -i -E 'libstdc|libgcc|winpthread|libgomp' || true)"
      [ -z "$bad" ] || fail "MinGW runtime DLLs are imported: $bad"
      ok "no MinGW runtime DLL imports"
    else ok "static-link check skipped (no objdump)"; fi;;
  *) ok "static-link check skipped on $UNAME_S";;
esac

# Programs: compile every test and example, run them (they assert their own numbers).
mkdir -p build/examples
n=0
for src in tests/*.lms examples/*.lms; do
  name="$(basename "$src" .lms)"
  "$LMSCRIPT" "$src" "build/$name.dslb" >"$WORK/$name.log" 2>&1 || { cat "$WORK/$name.log" >&2; fail "$name compile"; }
  n=$((n+1))
done
ok "$n programs compile as bytecode v5"
for src in tests/*.lms examples/*.lms; do
  name="$(basename "$src" .lms)"
  "$HOST" --dsl "build/$name.dslb" >"$WORK/$name.out" 2>"$WORK/$name.err" || { cat "$WORK/$name.out" "$WORK/$name.err" >&2; fail "$name run"; }
  grep -q '"ok": true' "$WORK/$name.out" || { cat "$WORK/$name.out" >&2; fail "$name did not report ok"; }
done
ok "$n programs run and pass their own assertions"

# Determinism: the CSV files the examples write are identical on rerun.
for f in build/examples/*.csv; do echo "$(sha "$f") $f"; done >"$WORK/before.txt"
for src in examples/*.lms; do
  name="$(basename "$src" .lms)"
  "$HOST" --dsl "build/$name.dslb" >/dev/null 2>&1 || fail "$name rerun"
done
for f in build/examples/*.csv; do echo "$(sha "$f") $f"; done >"$WORK/after.txt"
cmp -s "$WORK/before.txt" "$WORK/after.txt" || fail "result files differ on rerun"
ok "all $(wc -l <"$WORK/after.txt" | tr -d ' ') result files are byte-identical on rerun"

nerr=0
# Error paths: each snippet must fail the run with exit 3 and a message naming the problem.
expect_error() { # name, snippet, expected message fragment
  nerr=$((nerr+1))
  cat >"$WORK/$1.lms" <<LMS
p = _dsl_ cli="lmnum";
$2
end _dsl_
savedsl(p, "$WORK/$1.dslb");
LMS
  "$LMSCRIPT" "$WORK/$1.lms" >/dev/null 2>"$WORK/$1.cerr" || { cat "$WORK/$1.cerr" >&2; fail "$1 compile"; }
  set +e; out="$("$HOST" --dsl "$WORK/$1.dslb" 2>/dev/null)"; code=$?; set -e
  [ "$code" = 3 ] || fail "$1: exit code $code, expected 3 ($out)"
  echo "$out" | grep -q "$3" || fail "$1: message lacks '$3': $out"
}
expect_error singular 'let m = num.parse("1 2; 2 4"); let x = m.inverse();' "singular"
expect_error index 'let m = num.matrix(2, 2); let x = m.get(2, 0);' "outside 2x2"
expect_error shapes 'let m = num.matrix(2, 2).add(num.matrix(3, 3));' "differ"
expect_error badexpr 'let x = num.eval("2 +* 3");' "expression"
expect_error unknown 'let x = num.eval("foo + 1");' "unknown name"
expect_error bracket 'let x = num.root("x^2 + 1", "x", 0.0, 1.0);' "bracket"
expect_error noeq 'let o = num.ode(2); let s = o.solve(0.0, 1.0, 5);' "rhs"
expect_error assertfail 'num.assert_close(1.0, 2.0, 0.1);' "assert_close failed"
# Inputs that used to give a wrong answer (or a crash) without an error.
expect_error nearsingular 'let x = num.parse("1 2 3; 4 5 6; 7 8 9").solve(num.parse("1; 1; 2"));' "singular"
expect_error nonsym 'let e = num.parse("1 5; 2 2").eig_sym();' "not symmetric"
expect_error unsorted 'let v = num.interp(num.parse("0; 2; 1"), num.parse("0; 2; 1"), 1.5);' "strictly increasing"
expect_error rootnan 'let x = num.root("sqrt(x - 2)", "x", 0.0, 3.0);' "NaN"
expect_error tinybracket 'let x = num.root("1e-200*(x + 1)", "x", 0.0, 1.0);' "bracket"
expect_error infintegral 'let x = num.integrate("1/x", "x", -1.0, 1.0);' "not finite"
expect_error negsize 'let m = num.random(-1, 3, 1);' "bad size"
expect_error nantext 'let m = num.parse("nan 1");' "finite"
expect_error emptymean 'let x = num.matrix(0, 3).mean();' "empty"
expect_error badtol 'let o = num.ode(1).tol(-1.0, 0.0);' "Ode.tol"
expect_error badsystol 'let x = num.system(1).eq(0, "x0^2 - 2").solve(num.parse("1"), -1.0);' "tolerance"
expect_error nosolution 'let x = num.system(1).eq(0, "x0^2 + 1").solve(num.parse("1"), 0.0000000001);' "nlsolve"
expect_error manypoints 'let o = num.ode(1).rhs(0, "-y0").init(0, 1.0); let s = o.solve(0.0, 1.0, 4294967299);' "points"
expect_error badnumber 'let x = num.eval("1e999");' "bad number"
ok "errors stop the program with exit 3 and a clear message ($nerr cases)"

# README gallery: every linked example and image exists, images are valid PNG/GIF within the size limits.
magic_ok() { # file
  case "$1" in
    *.png) [ "$(head -c 8 "$1" | od -An -tx1 | tr -d ' \n')" = "89504e470d0a1a0a" ];;
    *.gif) [ "$(head -c 4 "$1")" = "GIF8" ];;
    *) return 1;;
  esac
}
nimg=0
for img in $(grep -oE 'docs/images/[A-Za-z0-9_.-]+\.(png|gif)' README.md | sort -u); do
  [ -f "$img" ] || fail "README references missing image $img"
  magic_ok "$img" || fail "$img is not a valid PNG/GIF"
  size=$(wc -c <"$img" | tr -d ' ')
  case "$img" in *.gif) limit=3000000;; *) limit=300000;; esac
  [ "$size" -le "$limit" ] || fail "$img is $size bytes (limit $limit)"
  nimg=$((nimg+1))
done
[ "$nimg" -ge 6 ] || fail "README gallery shows only $nimg images"
for ex in $(grep -o '(examples/[A-Za-z0-9_/.-]*\.lms)' README.md | tr -d '()' | sort -u); do
  [ -f "$ex" ] || fail "README links missing example $ex"
done
ok "README gallery: $nimg images valid and within size limits, every linked example exists"

# Gallery examples: lmnum computes, lmplot draws (needs lmplot on PATH, or network for install=; the GIF needs ffmpeg).
if command -v lmplot >/dev/null 2>&1 || [ "${LMNUM_TEST_NETWORK:-}" = 1 ]; then
  ng=0
  for src in examples/gallery/*.lms; do
    name="$(basename "$src" .lms)"
    if [ "$name" = lorenz_anim ] && ! command -v ffmpeg >/dev/null 2>&1; then echo "note: $name skipped (no ffmpeg on PATH)"; continue; fi
    timeout 300 "$LMSCRIPT" "$src" >"$WORK/gallery-$name.log" 2>&1 || { cat "$WORK/gallery-$name.log" >&2; fail "gallery example $name"; }
    ng=$((ng+1))
  done
  for img in images/*.png images/*.gif; do
    [ -s "$img" ] || continue
    magic_ok "$img" || fail "$img is not a valid PNG/GIF"
  done
  ok "$ng gallery examples run and wrote valid images (docs/images are refreshed by examples/render-all.sh)"
else
  ok "gallery examples skipped (no lmplot on PATH, LMNUM_TEST_NETWORK unset): docs/images not regenerated"
fi

set +e; "$HOST" --dsl "$WORK/does-not-exist.dslb" >/dev/null 2>&1; code=$?; set -e
[ "$code" = 3 ] || fail "missing bytecode exit code $code, expected 3"
set +e; "$HOST" >/dev/null 2>&1; code=$?; set -e
[ "$code" = 2 ] || fail "usage exit code $code, expected 2"
ok "usage and load errors use exit codes 2 and 3"

echo "all $pass checks passed"

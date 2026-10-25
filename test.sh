#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE"
BUILD_DIR="${BUILD_DIR:-build}"
HOST="$BUILD_DIR/lmnum"
UNAME_S="$(uname -s)"
if [ -x /usr/bin/timeout ]; then TIMEOUT=/usr/bin/timeout
elif [ -x /usr/bin/timeout.exe ]; then TIMEOUT=/usr/bin/timeout.exe
elif command -v gtimeout >/dev/null 2>&1; then TIMEOUT="$(command -v gtimeout)"
else TIMEOUT="$(command -v timeout)"; fi
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
LMSCRIPT="$("$TIMEOUT" 180 scripts/select-compiler.sh)"
"$TIMEOUT" 30 scripts/sync-sdk.sh --verify >/dev/null || fail "SDK header pin mismatch"
ok "SDK header matches sdk.lock"
"$TIMEOUT" 30 scripts/sync-deps.sh --verify >/dev/null || fail "third_party pin mismatch"
ok "third_party matches deps.lock"

GEN=""
command -v ninja >/dev/null 2>&1 && GEN="-G Ninja"
# shellcheck disable=SC2086
"$TIMEOUT" 1200 cmake -S . -B "$BUILD_DIR" $GEN -DCMAKE_BUILD_TYPE=Release >/dev/null
"$TIMEOUT" 1200 cmake --build "$BUILD_DIR" --parallel "${BUILD_JOBS:-2}" >"$WORK/build.log" 2>&1 || { tail -40 "$WORK/build.log" >&2; fail "build"; }
ok "build"

want_version="lmnum $(sed -n 's/^project(lmnum VERSION \([0-9.]*\).*/\1/p' CMakeLists.txt)"
[ "$("$TIMEOUT" 180 "$HOST" --version)" = "$want_version" ] || fail "--version is not exactly '$want_version'"
ok "--version prints exactly '$want_version'"
"$TIMEOUT" 30 python3 scripts/gen-schema.py >/dev/null && git diff --quiet -- schema/lmnum.dsl.json 2>/dev/null || [ ! -e .git ] || fail "schema/lmnum.dsl.json is stale: run scripts/gen-schema.py"
ok "schema matches the registrations in cpp/main.cpp"
"$TIMEOUT" 180 "$HOST" --dsl-schema --json >"$WORK/schema.json" || fail "embedded schema print"
cmp -s "$WORK/schema.json" schema/lmnum.dsl.json || fail "embedded schema differs from schema/lmnum.dsl.json"
ok "--dsl-schema --json prints byte-identical embedded schema bytes"
diff -u <("$TIMEOUT" 300 "$LMSCRIPT" --dsl-signatures schema/lmnum.dsl.json) <("$TIMEOUT" 180 "$HOST" --dsl-signatures) || fail "host/compiler signatures differ"
ok "host registry matches compiler signatures"
"$TIMEOUT" 180 "$HOST" --notices > "$WORK/notices"
cmp THIRD_PARTY_NOTICES "$WORK/notices" || fail "embedded notices differ"
grep -q "dynamically linked to the system glibc (LGPL-2.1)" "$WORK/notices" || fail "dynamic glibc notice missing"
ok "--notices matches the complete third-party license texts"

case "$UNAME_S" in
  Linux)
    "$TIMEOUT" 60 python3 scripts/check-linux-linkage.py "$HOST" || fail "Linux glibc dependency policy"
    printf '#include <iostream>\nint main() { std::cout << "test"; }\n' > "$WORK/linkage.cpp"
    "$TIMEOUT" 30 c++ "$WORK/linkage.cpp" -o "$WORK/shared-runtime"
    if "$TIMEOUT" 60 python3 scripts/check-linux-linkage.py "$WORK/shared-runtime" > "$WORK/linkage.err" 2>&1; then
      fail "linkage audit accepted a shared C++ runtime"
    fi
    grep -q 'libstdc++' "$WORK/linkage.err" || fail "wrong shared-runtime rejection"
    "$TIMEOUT" 30 c++ "$WORK/linkage.cpp" -static -o "$WORK/fully-static"
    if "$TIMEOUT" 60 python3 scripts/check-linux-linkage.py "$WORK/fully-static" > "$WORK/static.err" 2>&1; then
      fail "linkage audit accepted a fully static Linux binary"
    fi
    ok "dynamic glibc allowlist and <=2.35 symbols; rejects shared C++ and fully static binaries";;
  Darwin) bad="$("$TIMEOUT" 30 otool -L "$HOST" | tail -n +2 | grep -v -E '/usr/lib/(libSystem|libc\+\+|libresolv)' || true)"
          [ -z "$bad" ] || fail "non-system dylib dependencies: $bad"; ok "only system libraries linked";;
  MINGW*|MSYS*|CYGWIN*)
    if command -v objdump >/dev/null 2>&1; then
      bad="$("$TIMEOUT" 30 objdump -p "$HOST" | grep 'DLL Name' | grep -i -E 'libstdc|libgcc|winpthread|libgomp' || true)"
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
  "$TIMEOUT" 300 "$LMSCRIPT" "$src" "build/$name.dslb" >"$WORK/$name.log" 2>&1 || { cat "$WORK/$name.log" >&2; fail "$name compile"; }
  n=$((n+1))
done
ok "$n programs compile as bytecode v5"
for src in tests/*.lms examples/*.lms; do
  name="$(basename "$src" .lms)"
  "$TIMEOUT" 180 "$HOST" --dsl "build/$name.dslb" >"$WORK/$name.out" 2>"$WORK/$name.err" || { cat "$WORK/$name.out" "$WORK/$name.err" >&2; fail "$name run"; }
  grep -q '"ok": true' "$WORK/$name.out" || { cat "$WORK/$name.out" >&2; fail "$name did not report ok"; }
done
ok "$n programs run and pass their own assertions"

# Determinism: the CSV files the examples write are identical on rerun.
for f in build/examples/*.csv; do echo "$(sha "$f") $f"; done >"$WORK/before.txt"
for src in examples/*.lms; do
  name="$(basename "$src" .lms)"
  "$TIMEOUT" 180 "$HOST" --dsl "build/$name.dslb" >/dev/null 2>&1 || fail "$name rerun"
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
  "$TIMEOUT" 300 "$LMSCRIPT" "$WORK/$1.lms" >/dev/null 2>"$WORK/$1.cerr" || { cat "$WORK/$1.cerr" >&2; fail "$1 compile"; }
  set +e; out="$("$TIMEOUT" 180 "$HOST" --dsl "$WORK/$1.dslb" 2>/dev/null)"; code=$?; set -e
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
expect_error shadowparam 'let o = num.ode(1).param("t", 2.0).rhs(0, "-t*y0").init(0, 1.0); let s = o.solve(0.0, 1.0, 3);' "name of a variable"
expect_error badnumber 'let x = num.eval("1e999");' "bad number"
# NaN/inf results, bad shapes and non-positive-definite input used to pass through silently.
expect_error evalnan 'let x = num.eval("sqrt(-1)");' "NaN"
expect_error funcinf 'let x = num.func("1/x", "x").eval(0.0);' "infinite"
expect_error mapnan 'let m = num.parse("1 -1").map(num.func("log(x)", "x"));' "NaN"
expect_error polyshape 'let c = num.polyfit(num.parse("1 2; 3 4"), num.parse("1 2; 3 4"), 1);' "vector"
expect_error interpshape 'let v = num.interp(num.parse("1 2; 3 4"), num.parse("1 2; 3 4"), 1.5);' "vector"
expect_error notpd 'let l = num.parse("1 2; 2 1").cholesky();' "positive definite"
expect_error blockrange 'let b = num.identity(3).block(2, 0, 2, 2);' "outside"
expect_error badinttol 'let x = num.integrate_tol("x", "x", 0.0, 1.0, 0.0);' "tolerance"
ok "errors stop the program with exit 3 and a clear message ($nerr cases)"

# Memory budget: a runaway allocation loop stops with a run error (exit 3, message on stderr and in
# the JSON line) instead of exhausting the machine. A small budget everywhere; on Linux also the
# default 4096 MiB under a 6 GiB address-space limit (ulimit only here, never in the host).
cat >"$WORK/runaway.lms" <<LMS
p = _dsl_ cli="lmnum";
let i = 0;
while (i < 1000000) {
  let m = num.random(1000, 1000, i);
  i = i + 1;
}
end _dsl_
savedsl(p, "$WORK/runaway.dslb");
LMS
"$TIMEOUT" 300 "$LMSCRIPT" "$WORK/runaway.lms" >/dev/null || fail "runaway.lms compile"
set +e; out="$(LMNUM_MAX_MEMORY_MB=64 "$TIMEOUT" 180 "$HOST" --dsl "$WORK/runaway.dslb" 2>"$WORK/runaway.err")"; code=$?; set -e
[ "$code" = 3 ] || fail "runaway loop under LMNUM_MAX_MEMORY_MB=64: exit $code, expected 3 ($out)"
echo "$out" | grep -q "memory budget exceeded" || fail "runaway loop: JSON lacks the budget message: $out"
grep -q "LMNUM_MAX_MEMORY_MB" "$WORK/runaway.err" || fail "runaway loop: no budget message on stderr"
set +e; LMNUM_MAX_MEMORY_MB=-5 "$TIMEOUT" 180 "$HOST" --dsl "$WORK/runaway.dslb" >/dev/null 2>"$WORK/badenv.err"; code=$?; set -e
[ "$code" = 2 ] && grep -q "positive whole number" "$WORK/badenv.err" || fail "bad LMNUM_MAX_MEMORY_MB: exit $code"
if [ "$UNAME_S" = Linux ]; then
  set +e; out="$(ulimit -v 6291456; "$TIMEOUT" 180 "$HOST" --dsl "$WORK/runaway.dslb" 2>/dev/null)"; code=$?; set -e
  [ "$code" = 3 ] && echo "$out" | grep -q "limit 4096 MiB" || fail "runaway loop with the default budget under ulimit -v 6 GiB: exit $code ($out)"
  ok "memory budget: runaway loop stops at 64 MiB and at the default 4096 MiB (under ulimit -v 6 GiB)"
else
  ok "memory budget: runaway loop stops at LMNUM_MAX_MEMORY_MB=64 (default-budget run is Linux-only)"
fi

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
    "$TIMEOUT" 300 "$LMSCRIPT" "$src" >"$WORK/gallery-$name.log" 2>&1 || { cat "$WORK/gallery-$name.log" >&2; fail "gallery example $name"; }
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

# --dry-run runs the program but writes no files.
cat >"$WORK/dry.lms" <<LMS
p = _dsl_ cli="lmnum";
num.identity(2).save_csv("$WORK/dry.csv");
end _dsl_
savedsl(p, "$WORK/dry.dslb");
LMS
"$TIMEOUT" 300 "$LMSCRIPT" "$WORK/dry.lms" >/dev/null || fail "dry.lms compile"
"$TIMEOUT" 180 "$HOST" --dry-run --dsl "$WORK/dry.dslb" >/dev/null 2>"$WORK/dry.err" || fail "dry run"
[ ! -e "$WORK/dry.csv" ] || fail "--dry-run wrote a file"
grep -q "would write" "$WORK/dry.err" || fail "--dry-run did not report the skipped write"
"$TIMEOUT" 180 "$HOST" --dsl "$WORK/dry.dslb" >/dev/null || fail "real run"
[ -s "$WORK/dry.csv" ] || fail "save_csv wrote nothing"
ok "--dry-run reports save_csv without writing; a real run writes"

set +e; "$TIMEOUT" 180 "$HOST" --dsl "$WORK/does-not-exist.dslb" >/dev/null 2>&1; code=$?; set -e
[ "$code" = 3 ] || fail "missing bytecode exit code $code, expected 3"
set +e; "$TIMEOUT" 180 "$HOST" >/dev/null 2>&1; code=$?; set -e
[ "$code" = 2 ] || fail "usage exit code $code, expected 2"
ok "usage and load errors use exit codes 2 and 3"

# The published compiler injects std; the host embeds only its own schema bytes.
"$LMSCRIPT" --dsl-signatures schema/lmnum.dsl.json --without-std > "$WORK/std-host-only.sig"
"$LMSCRIPT" --dsl-signatures cpp/std/lmcode-std.schema.json > "$WORK/std-builtins.sig"
"$HOST" --dsl-signatures > "$WORK/std-registry.sig"
python3 - "$WORK" <<'PYSTD'
import pathlib,sys,json
w=pathlib.Path(sys.argv[1])
read=lambda name:set((w/name).read_text().splitlines())
assert read('std-registry.sig')-read('std-builtins.sig') == read('std-host-only.sig'), 'host-only registry drift'
schema=str(pathlib.Path('schema/lmnum.dsl.json').resolve()).replace('\\','/')
out=str(w/'std-probe.dslb').replace('\\','/')
(w/'std-probe.lms').write_text('p = _lmcode_ schema='+json.dumps(schema)+';\nlet values = str_list().add("abc");\nif (str_len(values.at(0)) != 3) { let bad = int_list().at(0); }\nend _lmcode_\nsavedsl(p, '+json.dumps(out)+');\n')
PYSTD
"$LMSCRIPT" "$WORK/std-probe.lms" > "$WORK/std-probe.log" 2>&1 || { cat "$WORK/std-probe.log"; fail "implicit std compile"; }
"$HOST" --dsl "$WORK/std-probe.dslb" > "$WORK/std-run.log" 2>&1 || { cat "$WORK/std-run.log"; fail "implicit std runtime"; }
ok "host-only signatures and implicit std runtime"

echo "all $pass checks passed"

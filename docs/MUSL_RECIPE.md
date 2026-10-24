# Static musl release recipe — lmnum prototype

Scope: lmnum v0.1.3 only. This follows Lead’s explicit musl prototype request. The shared
PROCEDURE.md Rule 14 changed concurrently to dynamic glibc during the prototype; this
recipe records the explicitly requested musl experiment rather than overriding that file;
other hosts require their own dependency validation before adoption. Never install
libc6-compat/gcompat to disguise a glibc dependency in the product.

## Container and native architecture

Use native ubuntu-24.04 for linux-x64 and ubuntu-24.04-arm for linux-arm64. No QEMU or
cross compilation is needed. The digest below is an OCI multiarchitecture index with
amd64 and arm64/v8 images, not an amd64-only manifest. Exact lmnum Dockerfile:

```dockerfile
# Alpine 3.23.7 multi-architecture base is pinned; APK revisions are recorded in provenance.
FROM alpine@sha256:ff7f0c727dd796aa36787bfcd9a64bf35a6ce72a73451b3359fde849b6703d63

RUN for attempt in 1 2 3 4 5; do \
      apk update && \
      apk add --no-cache \
        bash binutils ca-certificates build-base cmake coreutils curl ffmpeg findutils \
        file git ninja nodejs npm python3 tar unzip zip && exit 0; \
      sleep 5; \
    done; \
    exit 1

WORKDIR /workspace
ENTRYPOINT ["/bin/bash"]
```

Alpine 3.23 provides Node >=24.15 required by the compiler package. Alpine 3.22's Node22
is unsupported. build-base includes GCC/G++ and musl-dev; g++ pulls libstdc++-dev and its
static archive. binutils supplies readelf/nm, coreutils supplies timeout, ffmpeg serves
only the gallery animation tests. ca-certificates is necessary for HTTPS installs.
The base and dependency source commits are pinned; apk repositories roll within v3.23.
Record `apk info --who-owns /usr/lib/libc.a /usr/lib/libm.a /usr/lib/libstdc++.a`, compiler
version/triple, node/npm versions and the FROM digest for every build. Do not describe
this as a hermetic package lock. Prototype: Alpine3.23.7, GCC15.2.0, musl1.2.5-r24.

## Reusable workflow structure

```yaml
strategy:
  fail-fast: false
  matrix:
    include:
      - {os: ubuntu-24.04, name: linux-x64}
      - {os: ubuntu-24.04-arm, name: linux-arm64}
runs-on: ${{ matrix.os }}
steps:
  - uses: actions/checkout@11d5960a326750d5838078e36cf38b85af677262
    with: {persist-credentials: false}
  - name: pinned sources and SDK
    run: |
      timeout 300 scripts/sync-deps.sh
      timeout 30 scripts/sync-sdk.sh --verify
  - name: native musl build, full tests, static scratch smoke
    env:
      LMNUM_TEST_NETWORK: '1'
      GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
    run: timeout 1800 scripts/musl-build.sh
  - uses: actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02
    with:
      name: lmnum-${{ matrix.name }}
      path: build-musl/lmnum
```

Copy/adapt lmnum's scripts/musl-build.sh and scripts/check-linux-static.sh rather than
removing assertions. The wrapper builds the image, mounts sources at /workspace, records
provenance, installs @lmctl-ai/lmctl@0.2.369, runs the whole test.sh inside Alpine, then
runs a host-side scratch container smoke. Runtime SDK compiler and host must agree on DSL
ABI. Native macOS/Windows jobs stay unchanged. Package **build-musl/lmnum**, never a stale
build/lmnum from a prior glibc build. Use separate directories for libc, compiler and CPU.

Docker initially writes as root: pass the invoking UID/GID by environment and chown the
build directory back before leaving the container, otherwise host-side benchmark savedsl
fails EACCES. Do not make output world-writable.

Container flags: --rm --init, explicit bind mount, GITHUB_TOKEN inherited by name (never
printed or interpolated), outer timeout1800, test timeout1500. npm install timeout180,
configure/build timeout1200. Add --pull=false to avoid implicit tag changes with a pinned
digest. Retry bounded network downloads; curl --retry-all-errors handles transient TLS
record errors. Avoid nested unbounded commands and persist logs when a timeout occurs.

## CMake and proof of the linked libc

Use -DCMAKE_BUILD_TYPE=Release -DLMNUM_FULL_STATIC=ON -DLMNUM_REQUIRE_MUSL=ON;
lmnum's final link uses -static -static-libgcc -static-libstdc++ and
-Wl,-Map,<build-dir>/lmnum.map. All SUNDIALS libraries are static; Eigen is headers-only
with EIGEN_MPL2_ONLY. The REQUIRE_MUSL C compile probe includes features.h and rejects
__GLIBC__; clear its cache every configure. This prevents silently building on Ubuntu.
Map evidence must show /usr/lib/libc.a owned by musl-dev. Do not infer libc identity from
`file` alone. A developer glibc comparison must explicitly disable the policy guard and
mimalloc; it is not a release build.

Check:

```sh
timeout 15 file build-musl/lmnum
timeout 15 readelf -lW build-musl/lmnum
timeout 15 readelf -dW build-musl/lmnum
timeout 15 ldd build-musl/lmnum
timeout 360 scripts/check-linux-static.sh build-musl/lmnum build/static-smoke.dslb
```

Require no PT_INTERP and no DT_NEEDED; file must say static or static-pie. Alpine GCC15
produces static PIE under -static, which is valid. glibc ldd may say statically linked with
exit0; musl ldd may list itself for a static PIE. Do not reject solely on ldd exit status or
an ld-musl line. Reject actual shared-library mappings. Scratch validation copies only
the executable and bytecode, uses --network none --read-only, checks version and executes
an Eigen solve and a CVODE decay assertion. This proves absence of userspace runtime
loader/library requirements. Preserve ELF link map and APK ownership as musl provenance.

## Gallery helpers are build tools

Latest lmplot v0.2.1 was glibc-dynamic during this prototype; executing it in pure Alpine
fails ENOENT because its ELF interpreter is missing. Do not add glibc to the product build.
For validation only, scripts/fetch-musl-test-tools.sh fetches lmplot v0.1.0 and lmdraw v0.2.4 fully
static release tools, SHA256-pinned for each architecture in scripts/musl-test-tools.lock,
and places them on PATH before test.sh. They are neither linked nor shipped with lmnum.
lmdraw v0.1.0 is unsuitable: it predates the --dsl-schema query. Probe both --version and
--dsl-schema --json when updating these pins. These helper pins are specific to the lmnum gallery API; revalidate for another host.

Pinned build-tool hashes:

```text
lmplot v0.1.0 x64 f8d5331a0006ca5354fc340864dba060c78062b234710b20b851ff361c5d0dbe
lmplot v0.1.0 arm64 7ecbb73a1fbc1326a12f958a3cf3e3fb9285462731c8142b88dcc1ec1d1ed079
lmdraw v0.2.4 x64 9075aa102d6cef3704e37a6c382800065488cbf55ac73203ab2f4e567d8d854e
lmdraw v0.2.4 arm64 4c02aa31623ccb4ea4aa6d6690cb053730533c90cc591e97318a9bb96415b267
```

## Performance and allocator decision

Profile actual numerical examples first. Monte Carlo is lmnum's heaviest (25 gallery
numerical blocks profiled). scripts/prepare-libc-benchmark.py binds the local schema and
compiles once without rendering or host lookup; scripts/benchmark-libc.py alternates AB/BA
in isolated temporary directories with CPU affinity, warmups, per-run timeout, binary/fixture
hashes and JSON output. Baseline is the official glibc v0.1.2 release, not a different local
GCC build. Local seven-pair measurements: plain musl +3.6338%, musl+mimalloc -11.1137%.
The initial GCC14 Alpine3.22 trial exceeded20% (+23.7%), so mimalloc was tested and retained
for the better final result. These compare complete toolchains; they do not isolate libc.
CI records five pairs independently on x64 and arm64 in musl-proof artifacts.
Native main CI 40058347391: x64 glibc 14.7104s vs musl+mimalloc 13.1061s (-10.9064%);
arm64 glibc 14.6284s vs musl+mimalloc 15.5115s (+6.0366%). Both are below 20% regression.
Tagged release CI 40059374569 measured x64 -7.1323% (12.2545s vs 11.3805s) and
arm64 +6.7320% (14.5231s vs 15.5008s). Run-to-run timing variation is expected.

Reproduce on native x64 after the container build (use linux-arm64 on ARM):

```sh
mkdir -p /tmp/lmnum-glibc-v012
timeout 120 gh release download v0.1.2 -R lmctl-ai/lmnum -p lmnum-linux-x64 -p SHA256SUMS -D /tmp/lmnum-glibc-v012
(cd /tmp/lmnum-glibc-v012 && grep '  lmnum-linux-x64$' SHA256SUMS | sha256sum -c -)
chmod +x /tmp/lmnum-glibc-v012/lmnum-linux-x64
timeout 120 python3 scripts/prepare-libc-benchmark.py --source examples/gallery/monte_carlo.lms --output build-musl/monte-carlo.dslb
bench_cpu="$(python3 -c 'import os; print(max(os.sched_getaffinity(0)))')"
timeout 1800 python3 scripts/benchmark-libc.py --glibc /tmp/lmnum-glibc-v012/lmnum-linux-x64 --musl build-musl/lmnum --dsl build-musl/monte-carlo.dslb --output build-musl/libc-benchmark.json --warmups 2 --repeats 7 --timeout 90 --cpu "$bench_cpu"
```

mimalloc v3.6.0 (MIT), commit b18ab4eef383f655e760881b02eff8af02800879, is pinned in
deps.lock and built as a C object target. Do not blindly enable MI_OVERRIDE: even C mode
emits mangled C++ new/delete aliases, conflicting with or bypassing our memory counter.
Copy the pinned source into the build directory; cmake/mimalloc.cmake guards only that
alias section with LMNUM_KEEP_COUNTED_NEW. Link the object target to propagate its flags.
Override malloc/free/calloc/realloc/posix_memalign/malloc_usable_size together. nm proves
all C replacements are present and no mimalloc _Zn/_Zd operators are defined; original
cpp/memory_budget.cpp remains unchanged. The 64 MiB rejection and default4GiB-under6GiB
address-space tests must pass. Do not add allocator environment tuning to hide failures.
Compare raw musl with LMNUM_USE_MIMALLOC=OFF LMNUM_MUSL_BUILD_DIR=build-musl-raw.

## Portability and licensing pitfalls

lmnum is serial: SUNDIALS MPI/OpenMP/pthreads are disabled and Eigen has no -fopenmp.
This prototype makes no worker-thread performance claim. Future threaded hosts must check
musl's smaller default thread stack, set an explicit pthread stack size when needed, and
benchmark contention/allocator workloads. Test locale/iconv/DNS assumptions when relevant;
scratch has no resolver config, certificates, locale packs or user data. Runtime kernel
features remain an OS requirement despite static userspace linkage.

Replace the glibc LGPL notice only after proving the release uses musl; embed musl's full
upstream COPYRIGHT (v1.2.5) and the full mimalloc MIT notice plus the build-copy change.
Retain GCC runtime-exception notices and all mathematical-library notices. Check released
--notices against THIRD_PARTY_NOTICES. No glibc fallback was needed for lmnum; another
host whose dependencies genuinely cannot build on musl must resolve the release policy with Lead and satisfy the selected libc's distribution requirements
rather than silently retaining the old artifacts.

Release gate: five native platform jobs green, tag matches --version, five binary assets
plus licenses/checksums, downloaded ELF/scratch recheck, then lmctl autorun of a public
numerical-only example in an empty directory with a fresh LMSCRIPT_TOOL_CACHE and no
lmnum on PATH. Confirm the cached installation version/hash. No rollout is implied here.

## Prototype completion evidence

Released [lmnum v0.1.3](https://github.com/lmctl-ai/lmnum/releases/tag/v0.1.3).
[Tag CI 40059374569](https://github.com/lmctl-ai/lmnum/actions/runs/40059374569) is green
for all five platforms and publication. Downloaded binary checksums, both Linux ELF
headers, x64 scratch execution, embedded notices and fresh-cache autorun were verified.
Autorun URL: https://raw.githubusercontent.com/lmctl-ai/lmnum/main/examples/ode_stiff.lms
The installed x64 binary SHA256 is b1be73a3f4a636df49d2ba5a81f9da951501dcfc8c95592e8ef4f1c48768ab3e.
Detailed benchmark JSON and install proof are committed in lmnum/durable-memory/.
Stop point: this prototype does not authorize a musl rollout to other repositories.

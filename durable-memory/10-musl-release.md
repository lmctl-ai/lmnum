# Linux musl migration (v0.1.3)

Authority: Lead’s explicit musl prototype instruction. The shared PROCEDURE.md Rule 14
changed concurrently to dynamic glibc; this prototype follows the explicit user request,
not that later file edit. No rollout to other hosts is authorized here.

Both Linux architectures build natively in the
multiarchitecture Alpine 3.23.7 digest pinned in Dockerfile.musl. GCC 15.2, musl 1.2.5,
Node 24, compiler @lmctl-ai/lmctl 0.2.369. APK revisions are recorded in musl-provenance.txt;
APK repositories roll, so the pinned base is not a fully hermetic toolchain.

The full 19-check Linux suite includes 25 rendered gallery programs, numerical assertions,
31 invalid-input cases, 64 MiB accounting rejection and the default 4 GiB budget under a
6 GiB address-space limit. check-linux-static.sh inspects file/readelf/ldd and runs the
matrix+CVODE fixture inside a network-disabled, read-only scratch container.
Static PIE is valid: reject PT_INTERP and DT_NEEDED, not the word PIE or ldd exit status.

## Performance decision

All 25 numerical gallery blocks were profiled; Monte Carlo dominates (about 13 seconds,
next Newton fractal about 3). scripts/prepare-libc-benchmark.py extracts that exact numerical
block, binds the local schema, and compiles once. No renderer/compiler/download is timed.
scripts/benchmark-libc.py alternates AB/BA, private work directories, taskset CPU 3,
two warmups and seven paired measurements, each bounded at 90 seconds.
Baseline: official v0.1.2 linux-x64 release SHA256
65c155bd4601d766e2a8566e3acff8b38339dddb056bb06f4cbddde6e1e843bc.
Fixture SHA256 a44da6435d4b48202e39ed87208f2ceaf5f753ae2faefb525548778e4d7d692d.

An initial Alpine 3.22/GCC14 prototype regressed 23.7%, triggering the requested mimalloc
experiment. With final Alpine 3.23/GCC15, plain musl regressed 3.6338%; musl+mimalloc
improved 11.1137%. Retain the tested allocator for the faster result. This measures complete
release toolchains, not an isolated causal libc comparison. Local host: WSL2 x86_64,
4 available CPUs, GCC11/glibc2.35 host utilities; the baseline was built by release CI.
CI also records five paired samples on each native Linux architecture in musl-proof artifacts.

mimalloc v3.6.0 is pinned in deps.lock. cmake/mimalloc.cmake patches only a separate build
copy of alloc-override.c to suppress its mangled C++ aliases. C malloc/free/realloc/calloc,
posix_memalign and malloc_usable_size are overridden together; original counted C++
new/delete remain unchanged. Symbol checks and budget tests enforce this. No OpenMP or
pthread worker pool is enabled in lmnum; this is not a threaded performance claim.

## Reproduction and pitfalls

Run timeout 1800 scripts/musl-build.sh; use LMNUM_USE_MIMALLOC=OFF and
LMNUM_MUSL_BUILD_DIR=build-musl-raw to compare raw musl. Never share CMake directories
between libc/toolchains/architectures. Full details: [committed recipe](../docs/MUSL_RECIPE.md), mirrored at
/home/mma/repos/dsl/simulation/MUSL_RECIPE.md.

Gallery validation pins build-only lmplot v0.1.0 / lmdraw v0.2.4 static binaries by architecture and
SHA256 in scripts/musl-test-tools.lock. Latest lmplot became glibc-dynamic during this work,
which cannot start inside pure Alpine. These helpers are neither linked nor shipped with
lmnum. No glibc compatibility package is installed. Runtime user gallery helpers remain
independently versioned; numerical-only examples/ode_stiff.lms verifies lmnum autorun alone.

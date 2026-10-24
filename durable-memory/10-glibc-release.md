# v0.1.4: supported Linux system glibc baseline

Authority: revised PROCEDURE.md Rule 14 and GLIBC_DYNAMIC.md. The user explicitly
withdrew all alternate-libc support. Seventeen normal git revert commits undo the
entire prototype without rewriting public history; no optional support lane remains.
Dockerfile.musl, allocator integration/dependency, build/benchmark scripts, support
notices, old durable-memory note and both recipe copies were removed. v0.1.3 remains
historical and unsupported; v0.1.4 supersedes it.

Linux x64 and arm64 build natively on ubuntu-22.04 / ubuntu-22.04-arm. glibc is
dynamic; libstdc++, libgcc and SUNDIALS are static, Eigen remains headers-only.
CMake rejects a non-glibc Linux compiler. macOS uses system libraries and Windows
keeps the static MinGW runtime. --version remains exactly `lmnum 0.1.4`.

scripts/check-linux-linkage.py requires the glibc loader and libc.so.6, accepts
only libc.so.6, libm.so.6, libpthread.so.0, libdl.so.2, librt.so.1 and ld-linux
entries, and checks the symbol-version ceiling <=2.35. test.sh also compiles
negative fixtures to reject a shared C++ runtime and a fully static Linux binary.
The original cpp/memory_budget.cpp allocation accounting remains unchanged.

Local validation passed all 18 groups: six core programs, 31 invalid-input cases,
64 MiB and default 4 GiB budget limits, deterministic CSVs, and all 25 README gallery
programs including the GIF. Local x64 binary: 2,120,888 bytes, with only libm.so.6,
libc.so.6 and ld-linux-x86-64.so.2 as dynamic dependencies. No glibc independence
or fully static Linux portability is promised.

The release contains exactly five platform binary assets. Full MIT and third-party
license notices are embedded and test.sh compares them byte-for-byte. SHA256 hashes
are published in release notes rather than a sixth asset; download verification
uses those hashes. Main CI reference: https://github.com/lmctl-ai/lmnum/actions/runs/40060573250.
The final installation check runs four README gallery URLs from separate empty
working directories and caches, with no lmnum on PATH and GITHUB_TOKEN obtained
from gh auth token, checks version and release hash, and validates each PNG.

## Published and verified

[v0.1.4](https://github.com/lmctl-ai/lmnum/releases/tag/v0.1.4) is public and latest, with
exactly five binary assets. The [tag workflow](https://github.com/lmctl-ai/lmnum/actions/runs/40061802771)
passed all five platform jobs and publication. v0.1.3's title and notes also explicitly
mark it unsupported and link to v0.1.4; its historical tag and assets were preserved.

All five downloaded assets match the SHA256 hashes in the release notes. Both downloaded
Linux binaries pass the loader/NEEDED allowlist and <=2.35 symbol ceiling. Published x64
is 2,120,888 bytes; ARM64 is 1,944,488 bytes. The x64 embedded notices match source exactly.
The installed x64 SHA256 is 940dcd57c720bb5f422f811dd6076693b5e85a935fb0acb6af6a264f76505aeb.

Four public README autoruns passed in independent empty directories and caches:
predator_prey, van_der_pol, orbital and linear_regression. Every run used GITHUB_TOKEN
from gh auth token, had no lmnum on PATH, installed version0.1.4 matching the published
asset hash, passed its numerical assertions and wrote a valid images/<name>.png.
See autorun-v014.json and release-v014.json for the proof. No open implementation items.

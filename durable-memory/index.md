# lmnum durable memory

`lmnum` is a static, dependency-free lmscript `_dsl_` host embedding Eigen and SUNDIALS for numerical linear algebra, ODE/DAE integration, optimization, and root finding.
Repository: https://github.com/lmctl-ai/lmnum.

## 60-second takeover

```sh
cmake -S . -B build                   # Configure CMake build
cmake --build build --parallel 4      # Build binary at build/lmnum
./test.sh                             # Run verification test suite
```

## Document map

| File | Contents |
| --- | --- |
| [01-purpose-and-place.md](01-purpose-and-place.md) | Scope, numeric computation role, and relation to sibling math hosts |
| [02-libraries-and-licenses.md](02-libraries-and-licenses.md) | Eigen, SUNDIALS, BSD/Apache licensing, and build flags |
| [03-schema-v0.md](03-schema-v0.md) | `num` API conventions, vector/matrix operations, and schema |
| [04-expressions.md](04-expressions.md) | Embedded expression evaluation engine for numerical arguments |
| [05-build-run-test.md](05-build-run-test.md) | Measurements, build performance, and test.sh verification |
| [06-ci.md](06-ci.md) | GitHub Actions CI matrix (5 platforms) and build workflows |
| [07-examples.md](07-examples.md) | Numerical examples, Lorenz attractor, Lotka-Volterra benchmarks |
| [08-open-items.md](08-open-items.md) | Roadmap, planned solvers, and open issues |
| [09-resource-limits.md](09-resource-limits.md) | Memory budget allocation (`LMNUM_MAX_MEMORY_MB`) and size caps |
| [10-glibc-release.md](10-glibc-release.md) | Dynamic glibc baseline (>= 2.35), link audit, release verification |
| [autorun-v014.json](autorun-v014.json) | v0.1.4 fresh-directory autorun verification manifest |
| [release-v014.json](release-v014.json) | v0.1.4 release assets, hashes, and platform binary sizes |

## SDK pin and sync

The vendored SDK header is pinned via `sdk.lock` pointing to `https://github.com/lmctl-ai/lmcode-cpp`:
```sh
scripts/sync-sdk.sh                   # Refetches pinned cpp/dslvm.hpp and verifies sha256
```

## Adding an example or function

### Adding an example
1. Create `examples/<name>.lms` using `_dsl_ cli="lmnum" install="github:lmctl-ai/lmnum@latest"`.
2. Run script: `build/lmnum run examples/<name>.lms` or via `lmscript`.
3. Add the example to `./test.sh` test run list.
4. Save visual output to `docs/images/<name>.png` and update `README.md` demo table with `lmctl autorun` command.

### Adding a host function
1. Declare function/method in `schema/lmnum.dsl.json`.
2. Register and implement the function in C++ source under `src/` using `dslvm::Registry`.
3. Rebuild and verify schema synchronization with `cmake --build build` and `./test.sh`.

## Releases

Releases are triggered automatically on push of a `v*` tag. The release workflow builds across Linux x64/arm64, macOS x64/arm64, and Windows x64, publishing platform binaries with `SHA256SUMS`, `LICENSE`, and `THIRD_PARTY_NOTICES`.

Compiler >=0.2.420 resolves std from the pinned SDK bundle by default; host schema bytes remain host-only, with full and `--without-std` parity plus a standard-only runtime probe in `test.sh`.

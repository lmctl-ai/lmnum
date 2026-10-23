# Resource limits

Why: host objects live in arenas until exit (no `free`), so a DSL loop that keeps creating
matrices grows without bound. On 2026-10-23 a runaway lmnum process reached 16 GB RSS and filled
the 24 GB WSL machine before the OOM killer stopped it.

- **Total memory budget**, default 4096 MiB, set with `LMNUM_MAX_MEMORY_MB` (positive whole MiB;
  anything else exits 2 with the usage text). Shown in the usage message.
- `cpp/memory_budget.{hpp,cpp}` (identical copy in every lm* host) replaces the global
  `operator new`/`delete` and counts block sizes from the C allocator (`malloc_usable_size`,
  `malloc_size`, `_msize`). Eigen matrices use `malloc`, so `Host::mat` charges `rows*cols*8`
  bytes when a matrix enters the arena, and `need_dims` checks the budget before allocating.
- Exceeding it throws `membudget::Exceeded` (a `std::bad_alloc` with a fixed-buffer message);
  the first failure prints `lmnum: memory budget exceeded: ... (set LMNUM_MAX_MEMORY_MB ...)` on
  stderr and the run ends with the usual JSON error, exit 3. 64 MiB of headroom is granted once
  so the error path can still allocate.
- Not covered: Eigen temporaries inside one operation (at most a few objects of the 1e8-entry
  size cap) and SUNDIALS' C allocations during one solve; both are bounded per call.
- No `setrlimit`: RLIMIT_AS is not portable to macOS static builds and would make the host
  itself crash instead of reporting.
- Measured (x86_64 Linux): a loop of `num.random(1000, 1000, i)` stops at 64 MiB in 0.05 s, and at
  the default 4096 MiB after 6 s with 4.1 GB peak RSS (tracked bytes match RSS within ~3%).
  `test.sh` runs both; the default-budget run only on Linux, under `ulimit -v 6291456`.

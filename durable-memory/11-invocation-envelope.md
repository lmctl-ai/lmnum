# Invocation envelope (0.1.5)

SDK lmcode-cpp origin/main 93bddf1; lmscript 0.2.460.
Programs use run_lmcode and check r.ok. The host validates all arguments and
metadata, loads every registered file, then selects/runs/completes parts in order.
One SDK frame reports the invocation. First failure stops later execution.
Exit codes: 0 success; 2 CLI/metadata; 3 load/run; 4 application/output failure.
A reserved MiB is released before serializing failures after budget exhaustion.

Dry mode validates bytecode but executes nothing. The old per-save_csv dry
notification is gone: neither calculations nor file operations run in dry mode.
Standalone --dry-run is rejected if it contradicts real invocation metadata.
Introspection does not consume execution metadata or configure memory budgets.
num.print uses stderr; four gallery data consumers use explicit files read after
r.ok. Renderer calls require compatible binaries on PATH and never install them.

Tests retain numerical assertions, 31 error cases, CSV determinism, memory limits,
linkage negatives, schema and registry parity. Captured private inputs verify v6
and schema hashes and support standalone memory/dry controls. Additional tests
cover framing, builder order, load-before-effects, dry metadata, passive
introspection and all 25 offline gallery calculations (four file handoffs).
The harness explicitly discovers this build's schema before passive --check.

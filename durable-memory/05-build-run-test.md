# Build, run, test

Measured 2026-10-23, x86_64 Linux, 4 cores, GCC, Ninja.

- Clean Release build with SUNDIALS (CVODE, KINSOL) and Eigen: about 25 s. Binary 3.2 MB
  (stripped, `-static`), `ldd`: "not a dynamic executable".
- `./test.sh` (15 checks): sdk pin; deps pin; build; `--version` exactly `lmnum X.Y.Z`; schema
  equals the registrations; embedded schema byte-identical; host registry equals compiler
  signatures; notices; static linking; every program under `tests/` and `examples/` compiles
  and runs and passes its own `assert_close` checks; result CSVs byte-identical on rerun; eight
  error snippets exit 3 with a message naming the problem; usage/load exit codes; the lmnum+lmplot
  pipeline when `lmplot` is on `PATH` or `LMNUM_TEST_NETWORK=1`.
- Tests are lmscript programs asserting numbers with known answers (closed forms, conserved
  quantities, literature values such as the Robertson solution 0.7158 at t=40, the Dottie number
  0.7390851332, the Rosenbrock minimum (1,1)). A floating point difference across platforms
  shows up as an `assert_close` failure with both values.
- Run a program by hand: `lmscript examples/calculus.lms` (compiles, binds to `lmnum` on PATH).

# Open items

- IDA (DAEs) and ARKODE (explicit/IMEX Runge-Kutta, higher order for non-stiff) are not built;
  enabling them is a CMake option plus schema methods.
- Sparse matrices (Eigen Sparse + KLU/SuiteSparse is LGPL/GPL-mixed: needs care), complex matrices,
  FFT (FFTW is GPL; consider PocketFFT, BSD).
- Sensitivities (CVODES) and optimization with gradients (Ceres, BSD-3, needs glog/gflags).
- `Matrix` slicing by ranges, in-place elementwise ops, element-wise `Func` with two variables.
- Objects are never freed; a `release()` or scoped arenas would help long loops.
- Statistics beyond mean/std/min/max, random distributions beyond uniform/normal.

## From the 2026-10-23 review (fixed items are in git log; these remain)

- `Num.polyfit`/`interp` accept any matrix shape and use it flattened (column-major); a 2x2 "x"
  is not an error.
- `Num.load_csv` skips a header only when its first character is a letter; `save_csv` writes
  space-separated values despite the name (lmplot reads both).
- `Num.integrate` has a fixed absolute tolerance (1e-10) and finite bounds only; no infinite
  intervals or user tolerance. `minimize` stops on the simplex function-value spread only.
- `Num.normal` is portable up to last-ulp differences of the platform `log` (uniform draws are
  bit-exact); `tests/known_answers.lms` pins values with 1e-12 tolerance.
- NaN results: `Num.eval("sqrt(-1)")` and `Func.eval` return NaN without error (only
  `assert_close`, `root`, `integrate`, `minimize`, ODE and KINSOL reject non-finite values).
- `test.sh` writes example outputs under the literal `build/` even with `BUILD_DIR` set.

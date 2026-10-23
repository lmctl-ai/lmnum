# Open items

Fixed in 0.1.2: NaN/inf results of `eval`/`Func.eval`/`map` are errors; `polyfit`/`interp` need vectors;
`load_csv` skips any non-numeric first line; `integrate_tol` takes a tolerance; `svd_u/svd_v`, `cholesky`,
`block`, `sorted`, `minimize_path` added for the gallery (SVD compression, correlated Monte Carlo, Nelder-Mead paths).

- IDA (DAEs) and ARKODE (explicit/IMEX Runge-Kutta, higher order for non-stiff) are not built;
  enabling them is a CMake option plus schema methods.
- Sparse matrices (Eigen Sparse + KLU/SuiteSparse is LGPL/GPL-mixed: needs care), complex matrices,
  FFT (FFTW is GPL; consider PocketFFT, BSD).
- Sensitivities (CVODES) and optimization with gradients (Ceres, BSD-3, needs glog/gflags).
- `Matrix` slicing by ranges, in-place elementwise ops, element-wise `Func` with two variables.
- Objects are never freed; a `release()` or scoped arenas would help long loops.
- Statistics beyond mean/std/min/max, random distributions beyond uniform/normal.

## From the 2026-10-23 review (fixed items are in git log; these remain)

- `save_csv` writes space-separated values despite the name (lmplot reads both; changing it would
  break every gallery plot that reads the files without `set datafile separator`).
- `Num.integrate` has finite bounds only (no infinite intervals; substitute x = t/(1-t) in the
  expression). `minimize` stops on the simplex function-value spread only.
- `Num.normal` is portable up to last-ulp differences of the platform `log` (uniform draws are
  bit-exact); `tests/known_answers.lms` pins values with 1e-12 tolerance.
- `test.sh` writes example outputs under the literal `build/` even with `BUILD_DIR` set.

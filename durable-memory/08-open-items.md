# Open items

- IDA (DAEs) and ARKODE (explicit/IMEX Runge-Kutta, higher order for non-stiff) are not built;
  enabling them is a CMake option plus schema methods.
- Sparse matrices (Eigen Sparse + KLU/SuiteSparse is LGPL/GPL-mixed: needs care), complex matrices,
  FFT (FFTW is GPL; consider PocketFFT, BSD).
- Sensitivities (CVODES) and optimization with gradients (Ceres, BSD-3, needs glog/gflags).
- `Matrix` slicing by ranges, in-place elementwise ops, element-wise `Func` with two variables.
- Objects are never freed; a `release()` or scoped arenas would help long loops.
- Statistics beyond mean/std/min/max, random distributions beyond uniform/normal.

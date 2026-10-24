# Libraries and licenses

| library | version (commit) | license | how used |
| --- | --- | --- | --- |
| Eigen | 3.4.0 (`3147391d`) | MPL-2.0 | headers, `EIGEN_MPL2_ONLY` (excludes LGPL/GPL parts) |
| SUNDIALS | 7.2.1 (`2dcb3e01`) | BSD-3-Clause | CVODE, KINSOL, nvecserial, sunmatrixdense, sunlinsoldense, core, built from source by CMake |

Why MIT for lmnum itself: BSD-3 is compatible, and MPL-2.0 is file-level copyleft: the covered
Eigen files are used unmodified and their source is the pinned upstream commit, which the notices
point to. Anything GPL (GSL, FFTW, SuiteSparse's GPL parts, ...) is deliberately avoided; this is
why GSL is not used for special functions or optimization (own Brent, Nelder-Mead and
Gauss-Kronrod live in `cpp/numeric.cpp`).

SUNDIALS is built with `add_subdirectory` and options only: ARKODE, CVODES, IDA, IDAS off; MPI,
OpenMP, LAPACK, KLU, pthreads off; 64-bit index; examples off. Library targets
`sundials_*_static` are linked, as are the other third-party libraries. Linux release binaries use
dynamic system glibc 2.35 or newer and static libstdc++/libgcc; macOS and Windows retain their
platform-specific runtime policy. Result: a single executable with no third-party shared-library
dependencies.

`THIRD_PARTY_NOTICES` is generated once from the upstream license files (BSD text, NOTICE, full
MPL-2.0 text) and embedded in the binary (`lmnum --notices`). Bump a pin: edit `deps.lock`, run
`scripts/sync-deps.sh`, regenerate the notices if upstream license text changed.

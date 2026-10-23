# lmnum

**Numerical computing for lmscript in one static executable: Eigen, SUNDIALS, integration, root finding, optimization and fitting.**

| | | |
| :---: | :---: | :---: |
| <img src="docs/images/lorenz.gif" width="300"><br>Lorenz butterfly, animated<br><sub><code>lmctl autorun https://raw.githubusercontent.com/lmctl-ai/lmnum/main/examples/gallery/lorenz_anim.lms</code></sub> | <img src="docs/images/predator_prey.png" width="300"><br>Predator-prey cycles: time series and conserved orbits<br><sub><code>lmctl autorun https://raw.githubusercontent.com/lmctl-ai/lmnum/main/examples/gallery/predator_prey.lms</code></sub> | <img src="docs/images/van_der_pol.png" width="300"><br>Van der Pol: every start reaches the limit cycle<br><sub><code>lmctl autorun https://raw.githubusercontent.com/lmctl-ai/lmnum/main/examples/gallery/van_der_pol.lms</code></sub> |
| <img src="docs/images/stiff_kinetics.png" width="300"><br>Stiff Robertson kinetics over 12 decades<br><sub><code>lmctl autorun https://raw.githubusercontent.com/lmctl-ai/lmnum/main/examples/gallery/stiff_kinetics.lms</code></sub> | <img src="docs/images/heat_diffusion.png" width="300"><br>Heat equation: CVODE points on the exact curves<br><sub><code>lmctl autorun https://raw.githubusercontent.com/lmctl-ai/lmnum/main/examples/gallery/heat_diffusion.lms</code></sub> | <img src="docs/images/newton_fractal.png" width="300"><br>Newton fractal: root-finding basins of z^3 = 1<br><sub><code>lmctl autorun https://raw.githubusercontent.com/lmctl-ai/lmnum/main/examples/gallery/newton_fractal.lms</code></sub> |
| <img src="docs/images/polyfit_overfit.png" width="300"><br>Polynomial fits: underfit, good fit, overfit<br><sub><code>lmctl autorun https://raw.githubusercontent.com/lmctl-ai/lmnum/main/examples/gallery/polyfit_overfit.lms</code></sub> | <img src="docs/images/pca_ellipse.png" width="300"><br>PCA of a seeded cloud via symmetric eigendecomposition<br><sub><code>lmctl autorun https://raw.githubusercontent.com/lmctl-ai/lmnum/main/examples/gallery/pca_ellipse.lms</code></sub> | <img src="docs/images/lorenz_attractor.png" width="300"><br>Lorenz attractor, x-z projection coloured by time<br><sub><code>lmctl autorun https://raw.githubusercontent.com/lmctl-ai/lmnum/main/examples/gallery/lorenz_attractor.lms</code></sub> |

Each command runs the example from any empty directory: lmnum computes, [lmplot](https://github.com/lmctl-ai/lmplot) draws,
and the picture lands in `images/`. `examples/render-all.sh` regenerates `docs/images/` from a checkout.

Eigen linear algebra, SUNDIALS ODE and nonlinear solvers, integration, root finding, optimization and
fitting, with no Python and no BLAS. It is a scripting
host, not a command-line tool: write an [lmscript](https://lmctl.com/tools/lmscript/skill.html)
`_dsl_` block, compile it, run it with `lmnum --dsl`. One static executable, no shared libraries.

[![CI](https://github.com/lmctl-ai/lmnum/actions/workflows/ci.yml/badge.svg)](https://github.com/lmctl-ai/lmnum/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

```
# lotka-volterra.lms
p = _dsl_ cli="lmnum" install="github:lmctl-ai/lmnum@latest";
let sys = num.ode(2);
sys.param("a", 1.1).param("b", 0.4).param("c", 0.4).param("d", 0.1);
sys.rhs(0, "a*y0 - b*y0*y1").rhs(1, "d*y0*y1 - c*y1");
sys.init(0, 10.0).init(1, 10.0);
let sol = sys.solve(0.0, 60.0, 601);          # rows: t, prey, predators
sol.save_csv("lv.csv");
end _dsl_
savedsl(p, "lv.dslb");
system ${dsl_cli(p)} --dsl lv.dslb;
```

`lmscript lotka-volterra.lms` finds `lmnum` on `PATH` or downloads the release binary for your
platform on first use, compiles against the schema built into it, and runs the program.

## What it does

Functions are passed as expression strings (`"sin(x)*exp(-k*t)"`, variables and parameters named
in the call) because the DSL has no closures. The expression language is described in
[durable-memory/04-expressions.md](durable-memory/04-expressions.md).

| `num.` | |
| --- | --- |
| `matrix` `identity` `parse` `linspace` `random` `normal` `load_csv` | build matrices (deterministic seeds) |
| `ode(n)` → `.rhs .init .param .tol .stiff .solve` | CVODE: Adams or BDF (stiff), dense Newton; returns `t, y0..yn` |
| `system(n)` → `.eq .solve` | KINSOL: nonlinear systems F(x) = 0 |
| `integrate` `root` `minimize` | adaptive Gauss-Kronrod, Brent, Nelder-Mead |
| `polyfit` `polyval` `interp` | least-squares polynomials, linear interpolation |
| `func(expr, vars)` → `.eval .eval2`, `Matrix.map` | evaluate expressions |
| `eval(expr)` `assert_close` `print` `version` | constants, checks, output |

`Matrix` methods: `rows cols get set copy add sub mul hadamard scale shift transpose inverse det
trace norm solve lstsq eig_sym eigvec_sym svd_values col row hstack vstack sum mean min max std map
to_text save_csv`. Schema and rules: [durable-memory/03-schema-v0.md](durable-memory/03-schema-v0.md).

Combine it with other hosts in one script: [examples/gallery/lorenz_attractor.lms](examples/gallery/lorenz_attractor.lms)
integrates the Lorenz system with lmnum and draws it with [lmplot](https://github.com/lmctl-ai/lmplot)
(two `_dsl_` blocks, two hosts).

## Examples

| Program | Shows | Run it |
| --- | --- | --- |
| [linear_algebra.lms](examples/linear_algebra.lms) | solve, inverse, determinant, eigenvalues, SVD, least squares, each asserted | `lmctl autorun https://raw.githubusercontent.com/lmctl-ai/lmnum/main/examples/linear_algebra.lms` |
| [ode_lotka_volterra.lms](examples/ode_lotka_volterra.lms) | predator-prey, conserved quantity checked along 601 points | `lmctl autorun https://raw.githubusercontent.com/lmctl-ai/lmnum/main/examples/ode_lotka_volterra.lms` |
| [ode_stiff.lms](examples/ode_stiff.lms) | Robertson kinetics with BDF | `lmctl autorun https://raw.githubusercontent.com/lmctl-ai/lmnum/main/examples/ode_stiff.lms` |
| [calculus.lms](examples/calculus.lms) | integration, roots, Rosenbrock minimum, nonlinear system, fits | `lmctl autorun https://raw.githubusercontent.com/lmctl-ai/lmnum/main/examples/calculus.lms` |
| [gallery/predator_prey.lms](examples/gallery/predator_prey.lms) | five Lotka-Volterra orbits, conserved quantity H asserted | `lmctl autorun https://raw.githubusercontent.com/lmctl-ai/lmnum/main/examples/gallery/predator_prey.lms` |
| [gallery/van_der_pol.lms](examples/gallery/van_der_pol.lms) | limit cycle amplitude 2.0 from six starting points | `lmctl autorun https://raw.githubusercontent.com/lmctl-ai/lmnum/main/examples/gallery/van_der_pol.lms` |
| [gallery/stiff_kinetics.lms](examples/gallery/stiff_kinetics.lms) | Robertson kinetics restarted decade by decade, mass conserved | `lmctl autorun https://raw.githubusercontent.com/lmctl-ai/lmnum/main/examples/gallery/stiff_kinetics.lms` |
| [gallery/heat_diffusion.lms](examples/gallery/heat_diffusion.lms) | 59-point stiff ODE system checked against the exact two-mode solution | `lmctl autorun https://raw.githubusercontent.com/lmctl-ai/lmnum/main/examples/gallery/heat_diffusion.lms` |
| [gallery/newton_fractal.lms](examples/gallery/newton_fractal.lms) | 160 000 Newton iterations written in lmscript loops | `lmctl autorun https://raw.githubusercontent.com/lmctl-ai/lmnum/main/examples/gallery/newton_fractal.lms` |
| [gallery/polyfit_overfit.lms](examples/gallery/polyfit_overfit.lms) | seeded noise, `polyfit` of degree 1, 3, 9 | `lmctl autorun https://raw.githubusercontent.com/lmctl-ai/lmnum/main/examples/gallery/polyfit_overfit.lms` |
| [gallery/pca_ellipse.lms](examples/gallery/pca_ellipse.lms) | covariance eigenvalues checked against the population values | `lmctl autorun https://raw.githubusercontent.com/lmctl-ai/lmnum/main/examples/gallery/pca_ellipse.lms` |
| [gallery/lorenz_anim.lms](examples/gallery/lorenz_anim.lms) | 90 frames drawn by lmplot, encoded with ffmpeg | `lmctl autorun https://raw.githubusercontent.com/lmctl-ai/lmnum/main/examples/gallery/lorenz_anim.lms` |

## Build

C++17 compiler, CMake 3.24, git; nothing else.

```sh
scripts/sync-deps.sh            # Eigen and SUNDIALS at the commits in deps.lock
cmake -S . -B build && cmake --build build
./test.sh                       # needs lmscript on PATH
```

Linux builds are fully static; macOS links only system libraries; Windows links the MinGW runtime
statically. `lmnum --notices` prints the license texts of everything inside.

## License

MIT ([LICENSE](LICENSE)). SUNDIALS is BSD-3-Clause; Eigen is MPL-2.0 (used with `EIGEN_MPL2_ONLY`,
unmodified); see [THIRD_PARTY_NOTICES](THIRD_PARTY_NOTICES).

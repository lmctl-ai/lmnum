# lmnum

**Numerical computing for lmscript in one static executable: Eigen, SUNDIALS, integration, root finding, optimization and fitting.**

[![CI](https://github.com/lmctl-ai/lmnum/actions/workflows/ci.yml/badge.svg)](https://github.com/lmctl-ai/lmnum/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

### Differential equations

| ![predator_prey](docs/images/predator_prey.png) | ![van_der_pol](docs/images/van_der_pol.png) |
| --- | --- |
| Lotka-Volterra: populations in time and closed orbits in phase space.<br>`lmctl autorun https://raw.githubusercontent.com/lmctl-ai/lmnum/main/examples/gallery/predator_prey.lms` | Van der Pol oscillator: every start converges to the limit cycle.<br>`lmctl autorun https://raw.githubusercontent.com/lmctl-ai/lmnum/main/examples/gallery/van_der_pol.lms` |

| ![stiff_kinetics](docs/images/stiff_kinetics.png) | ![sir_epidemic](docs/images/sir_epidemic.png) |
| --- | --- |
| Robertson kinetics over twelve decades of time (stiff, BDF).<br>`lmctl autorun https://raw.githubusercontent.com/lmctl-ai/lmnum/main/examples/gallery/stiff_kinetics.lms` | An epidemic and the equation that predicts its size: CVODE against a root finder.<br>`lmctl autorun https://raw.githubusercontent.com/lmctl-ai/lmnum/main/examples/gallery/sir_epidemic.lms` |

| ![heat_diffusion](docs/images/heat_diffusion.png) | |
| --- | --- |
| The heat equation as a stiff ODE system, numerical points on the exact curves.<br>`lmctl autorun https://raw.githubusercontent.com/lmctl-ai/lmnum/main/examples/gallery/heat_diffusion.lms` | |

### Chaos and nonlinear maps

| ![lorenz_attractor](docs/images/lorenz_attractor.png) | ![lorenz_anim](docs/images/lorenz.gif) |
| --- | --- |
| The Lorenz attractor, coloured by time.<br>`lmctl autorun https://raw.githubusercontent.com/lmctl-ai/lmnum/main/examples/gallery/lorenz_attractor.lms` | The Lorenz butterfly, animated (needs ffmpeg).<br>`lmctl autorun https://raw.githubusercontent.com/lmctl-ai/lmnum/main/examples/gallery/lorenz_anim.lms` |

| ![logistic_bifurcation](docs/images/logistic_bifurcation.png) | ![newton_fractal](docs/images/newton_fractal.png) |
| --- | --- |
| Route to chaos: bifurcation diagram and Lyapunov exponent of the logistic map.<br>`lmctl autorun https://raw.githubusercontent.com/lmctl-ai/lmnum/main/examples/gallery/logistic_bifurcation.lms` | Newton's method for z^3 = 1: basins of attraction.<br>`lmctl autorun https://raw.githubusercontent.com/lmctl-ai/lmnum/main/examples/gallery/newton_fractal.lms` |

### Linear algebra and fitting

| ![hilbert_conditioning](docs/images/hilbert_conditioning.png) | ![vibration_modes](docs/images/vibration_modes.png) |
| --- | --- |
| Ill-conditioning: Hilbert matrices, condition number and solution error.<br>`lmctl autorun https://raw.githubusercontent.com/lmctl-ai/lmnum/main/examples/gallery/hilbert_conditioning.lms` | Normal modes of a chain of masses: eigenvalues and mode shapes.<br>`lmctl autorun https://raw.githubusercontent.com/lmctl-ai/lmnum/main/examples/gallery/vibration_modes.lms` |

| ![pca_ellipse](docs/images/pca_ellipse.png) | ![polyfit_overfit](docs/images/polyfit_overfit.png) |
| --- | --- |
| PCA of 500 samples: principal axes and sigma ellipses.<br>`lmctl autorun https://raw.githubusercontent.com/lmctl-ai/lmnum/main/examples/gallery/pca_ellipse.lms` | Polynomial fits of noisy points: underfit, good fit, overfit.<br>`lmctl autorun https://raw.githubusercontent.com/lmctl-ai/lmnum/main/examples/gallery/polyfit_overfit.lms` |

Each command runs the example from any empty directory: lmnum computes, [lmplot](https://github.com/lmctl-ai/lmplot) draws, and the picture lands in `images/`. `examples/render-all.sh` regenerates `docs/images/` from a checkout.

**Quick start:** `npm i -g @lmctl-ai/lmctl`, then paste any `lmctl autorun` line above.

Eigen linear algebra, SUNDIALS ODE and nonlinear solvers, integration, root finding, optimization and
fitting, with no Python and no BLAS. It is a scripting
host, not a command-line tool: write an [lmscript](https://lmctl.com/tools/lmscript/skill.html)
`_dsl_` block, compile it, run it with `lmnum --dsl`. One static executable, no shared libraries.

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
| [gallery/sir_epidemic.lms](examples/gallery/sir_epidemic.lms) | SIR epidemic: final size from CVODE against the Brent root of s = S0 exp(-R0 (1 - s)) | `lmctl autorun https://raw.githubusercontent.com/lmctl-ai/lmnum/main/examples/gallery/sir_epidemic.lms` |
| [gallery/logistic_bifurcation.lms](examples/gallery/logistic_bifurcation.lms) | bifurcation diagram and Lyapunov exponent; period-2 points and exponent asserted | `lmctl autorun https://raw.githubusercontent.com/lmctl-ai/lmnum/main/examples/gallery/logistic_bifurcation.lms` |
| [gallery/hilbert_conditioning.lms](examples/gallery/hilbert_conditioning.lms) | condition number from `svd_values` against the error of `solve` | `lmctl autorun https://raw.githubusercontent.com/lmctl-ai/lmnum/main/examples/gallery/hilbert_conditioning.lms` |
| [gallery/vibration_modes.lms](examples/gallery/vibration_modes.lms) | 24-mass chain: `eig_sym` against 2 - 2 cos(k pi / 25) | `lmctl autorun https://raw.githubusercontent.com/lmctl-ai/lmnum/main/examples/gallery/vibration_modes.lms` |
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

## Resource limits

A program may use at most 4096 MiB in total (matrices, solver state, everything the host keeps);
beyond that it stops with a run error (exit 3) naming the limit, instead of exhausting the machine.
Set `LMNUM_MAX_MEMORY_MB` to change it, e.g. `LMNUM_MAX_MEMORY_MB=16384 lmscript big.lms`.

## License

MIT ([LICENSE](LICENSE)). SUNDIALS is BSD-3-Clause; Eigen is MPL-2.0 (used with `EIGEN_MPL2_ONLY`,
unmodified); see [THIRD_PARTY_NOTICES](THIRD_PARTY_NOTICES).

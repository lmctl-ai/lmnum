# Examples

`examples/*.lms` each assert their own results; `examples/combo/lorenz_plot.lms` shows two hosts in
one script (lmnum for CVODE, lmplot for the picture). Notes from writing them:

- The DSL has no `log`/`pi`; use `num.eval("pi")` and `num.func("log(a)", "a")`.
- `system` in plain lmscript returns `{code, stdout, stderr}`; check `r.code` (a failing standalone
  call prints its stderr).
- Chaotic problems (Lorenz) depend on the last bits of the arithmetic, so the picture is not
  byte-compared across platforms; only deterministic CSVs of the non-chaotic examples are.

## Gallery (pictures) and `lmctl autorun`

`examples/gallery/*.lms` (25 programs) each compute with lmnum, write CSV into `data/`, and draw with lmplot (or lmdraw) into `images/` in the
*current directory*; the README gallery shows copies in `docs/images/` (`examples/render-all.sh` runs them from a checkout and copies;
PNG <= 300 KB, GIF <= 3 MB). Every example, old and new, ends with `r = system ${dsl_cli(p)} --lmcode ${out}; assert(r.code == 0);`
so `lmctl autorun <raw github url>` produces the output, not just bytecode. README captions are the autorun command.
- Stories: Lorenz (still and 90-frame GIF via ffmpeg palette), Lotka-Volterra orbits (conserved H asserted), Van der Pol limit
  cycle, Robertson kinetics restarted per decade (log time axis), heat equation by method of lines vs the exact two-mode
  solution, Newton fractal for z^3 = 1 (160 000 iterations in lmscript loops), seeded polynomial overfit, PCA ellipse.
- lmplot habits that bit: no inline `-` data via `plot.cmd` (write a CSV), `unset colorbox` for palette lines, `set format x '10^{%L}'`
  for log axes, DSL has no exponent literals (`0.0000001`) and `num` has no `assert_true` (use `assert_close(min(x, bound), x, 0)`).
- `test.sh` checks README images (magic bytes, sizes) and runs the gallery when lmplot is available (GIF only with ffmpeg).
- Added in the QA pass (stories with a known answer): `sir_epidemic` (CVODE final size against the Brent root of
  s = S0 exp(-R0 (1 - s)), asserted to 1e-4), `logistic_bifurcation` (period-2 points r = 3.2 in closed form, Lyapunov
  exponent 0.49 at r = 3.9; ln comes from `num.func("log(...)")`), `hilbert_conditioning` (cond(H5) = 4.77e5 and cond(H10) = 1.6e13
  asserted; `Matrix.solve` correctly refuses from n = 12 with "matrix is singular"), `vibration_modes` (24-mass chain, `eig_sym`
  vs 2 - 2 cos(k pi / 25) to 1e-10, `eigvec_sym` mode 1 vs a sine). Van der Pol now samples 5001 points per trajectory.
- Sweeps print one line per case with `num.print`; lmscript saves `r.stdout`; gnuplot reads the file (rows it cannot parse, such as the
  final JSON status line or rows starting with a tag like `L`, are skipped, so one file can hold two series). `plot.data`
  truncates long strings (about 8-11 KB seen): use a file. No `'< grep'` pipes (not portable to Windows).

## Added in the 0.1.2 pass (12 examples, each with a known answer)

- `linear_regression` (bands from the residual variance, t = 2.0244), `pendulum` (elliptic integral by `integrate`, period from the
  first zero crossing), `orbital` (apoapsis start, return after 2 pi asserted to 1e-7; energy/L drift 1e-9), `wave_equation`
  (398 equations, Adams; d'Alembert check must be before the first reflection: at t = 0.2 the Gaussian tail already touches x = 0),
  `burgers` (399 equations, BDF, dense Newton; characteristics check at t = 0.1, later the viscosity already changes the profile),
  `quadrature_orders` (use e^x: for 4/(1+x^2) the Simpson h^4 term vanishes because f'''(0) = f'''(1) = 0 and the order looks like 6),
  `monte_carlo` (6-D with 1e6 points x 3 seeds is 11 s of DSL loops), `nelder_mead` (`minimize_path`; `minimize` used to fail on
  any minimum at exactly 0 because its stop test was purely relative, fixed with a 1e-10 floor and a simplex-diameter test),
  `svd_compression` (`svd_u/svd_v`), `membrane_modes` (576 x 576 `eig_sym` in 0.3 s; degenerate pairs come out as mixtures),
  `spectrum_dft` (200 samples at 100 Hz so 5 and 30 Hz are exact bins and 12.25 Hz leaks), `markov_chain` (lmdraw infographic).
- lmplot/gnuplot lessons: `set key at ...` in one multiplot panel confuses the key placement of the following panels (use plain
  `bottom center` etc., or `at screen`); `set size ratio -1` in a layout panel also shifts later keys; contour plots need
  `set surface` plus per-plot `nosurface`/`nocontours`; `with image` takes x-y-z triples on a grid (pm3d needs blank lines);
  titles with `_` need `noenhanced`; a DSL `fn` cannot see block-level `let` variables (pass them as arguments).
- lmscript: `${name}` in a `_dsl_` block is one expression, not a statement splice (unroll repeated statements); numbers in text
  parse with `json_parse`.

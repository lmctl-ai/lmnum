# Examples

`examples/*.lms` each assert their own results; `examples/combo/lorenz_plot.lms` shows two hosts in
one script (lmnum for CVODE, lmplot for the picture). Notes from writing them:

- The DSL has no `log`/`pi`; use `num.eval("pi")` and `num.func("log(a)", "a")`.
- `system` in plain lmscript returns `{code, stdout, stderr}`; check `r.code` (a failing standalone
  call prints its stderr).
- Chaotic problems (Lorenz) depend on the last bits of the arithmetic, so the picture is not
  byte-compared across platforms; only deterministic CSVs of the non-chaotic examples are.

## Gallery (pictures) and `lmctl autorun`

`examples/gallery/*.lms` (13 programs) each compute with lmnum, write CSV into `data/`, and draw with lmplot into `images/` in the
*current directory*; the README gallery shows copies in `docs/images/` (`examples/render-all.sh` runs them from a checkout and copies;
PNG <= 300 KB, GIF <= 3 MB). Every example, old and new, ends with `r = system ${dsl_cli(p)} --dsl ${out}; assert(r.code == 0);`
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

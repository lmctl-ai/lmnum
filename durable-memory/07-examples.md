# Examples

`examples/*.lms` each assert their own results; `examples/combo/lorenz_plot.lms` shows two hosts in
one script (lmnum for CVODE, lmplot for the picture). Notes from writing them:

- The DSL has no `log`/`pi`; use `num.eval("pi")` and `num.func("log(a)", "a")`.
- `system` in plain lmscript returns `{code, stdout, stderr}`; check `r.code` (a failing standalone
  call prints its stderr).
- Chaotic problems (Lorenz) depend on the last bits of the arithmetic, so the picture is not
  byte-compared across platforms; only deterministic CSVs of the non-chaotic examples are.

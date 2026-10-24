# Purpose and place

lmnum is the first target of the *scripted scientific libraries* family (see
`../../simulation/ROADMAP.md`): well-known native libraries embedded into one executable,
driven from lmscript `_dsl_` bytecode through an embedded schema. The idea is the same as lmplot,
lmhtml, lmcad and lmssh: the script holds policy and control flow, the host holds the heavy code.

- **Scripting only.** There is no user-facing command line beyond `--dsl`, `--dry-run`,
  `--version`, `--notices`, `--dsl-schema [--json]` and `--dsl-signatures` (the conventions
  of the sibling hosts). Unlike lmplot (which also exposes gnuplot's own CLI) a numerical library
  has no CLI worth preserving.
- **Libraries**: Eigen (dense linear algebra), SUNDIALS 7 (CVODE for ODEs, KINSOL for nonlinear
  systems; serial N_Vector, dense matrix and solver). Both are pinned in `deps.lock` and fetched
  into git-ignored `third_party/` by `scripts/sync-deps.sh`; nothing of them is committed.
- **lmcode-cpp** (`cpp/dslvm.hpp`, bytecode v5) is vendored and pinned by `sdk.lock`.
- **lmscript** binds programs to the binary with `_dsl_ cli="lmnum" install="github:lmctl-ai/lmnum@latest";`
  so `lmscript prog.lms` is all a user runs; the schema is read from the binary
  (`lmnum --dsl-schema --json`).

## Scope boundary

The DSL has no lists, maps or closures. Therefore:

- collections are host objects (`Matrix`, with builder-style methods returning the receiver);
- functions are expression strings compiled by the host (`cpp/expr.hpp`);
- results come back as matrices and floats, and files (`Matrix.save_csv`, `Num.load_csv`) are the
  interchange with other hosts (lmplot draws from CSV).

Out of scope for v0: sparse matrices, complex numbers, DAEs (IDA is not built), sensitivities
(CVODES), parallel vectors, automatic differentiation, symbolic algebra.

## Related families (not built yet)

The brainstorm lists lmfluid, lmspace, lmphysics, lmweather, lmfinance, lmbio, lmcell, lmmolecule,
lmparticle. lmnum is the numerical base they would share ideas with (matrix and expression
conventions), not a runtime dependency.

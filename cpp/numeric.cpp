#include "numeric.hpp"

#include <algorithm>
#include <cmath>
#include <cvode/cvode.h>
#include <kinsol/kinsol.h>
#include <nvector/nvector_serial.h>
#include <stdexcept>
#include <sundials/sundials_context.h>
#include <sunlinsol/sunlinsol_dense.h>
#include <sunmatrix/sunmatrix_dense.h>

#include "expr.hpp"

namespace lmnum {

namespace {
// 15-point Gauss-Kronrod nodes/weights on [-1,1].
const double XGK[8] = {0.991455371120812639206854697526329, 0.949107912342758524526189684047851,
                       0.864864423359769072789712788640926, 0.741531185599394439863864773280788,
                       0.586087235467691130294144838258730, 0.405845151377397166906606412076961,
                       0.207784955007898467600689403773245, 0.000000000000000000000000000000000};
const double WGK[8] = {0.022935322010529224963732008058970, 0.063092092629978553290700663189204,
                       0.104790010322250183839876322541518, 0.140653259715525918745189590510238,
                       0.169004726639267902826583426598550, 0.190350578064785409913256402421014,
                       0.204432940075298892414161999234649, 0.209482141084727828012999174891714};
const double WG[4] = {0.129484966168869693270611432679082, 0.279705391489276667901467771423780,
                      0.381830050505118944950369775488975, 0.417959183673469387755102040816327};

struct Seg { double a, b, val, err; };

Seg gk15(const Expr &f, double a, double b, double *x) {
  double c = 0.5 * (a + b), h = 0.5 * (b - a);
  double fc;
  x[0] = c; fc = f.eval(x);
  double rk = fc * WGK[7], rg = fc * WG[3];
  for (int j = 0; j < 7; j++) {
    double dx = h * XGK[j];
    x[0] = c - dx; double f1 = f.eval(x);
    x[0] = c + dx; double f2 = f.eval(x);
    rk += WGK[j] * (f1 + f2);
    if (j % 2 == 1) rg += WG[j / 2] * (f1 + f2);
  }
  return {a, b, rk * h, std::fabs((rk - rg) * h)};
}
}  // namespace

double integrate(const std::string &expr, const std::string &var, double a, double b, double tol) {
  Expr f(expr, {var});
  double x[1];
  std::vector<Seg> segs{gk15(f, a, b, x)};
  for (int it = 0; it < 2000; it++) {
    double total = 0, err = 0;
    for (auto &s : segs) { total += s.val; err += s.err; }
    if (err <= std::max(tol, tol * std::fabs(total))) return total;
    auto worst = std::max_element(segs.begin(), segs.end(), [](const Seg &p, const Seg &q) { return p.err < q.err; });
    Seg s = *worst;
    double m = 0.5 * (s.a + s.b);
    *worst = gk15(f, s.a, m, x);
    segs.push_back(gk15(f, m, s.b, x));
  }
  throw std::runtime_error("integrate: no convergence (singular or oscillating integrand?)");
}

double find_root(const std::string &expr, const std::string &var, double a, double b, double tol) {
  Expr e(expr, {var});
  auto f = [&](double x) { return e.eval(&x); };
  double fa = f(a), fb = f(b);
  if (fa == 0) return a;
  if (fb == 0) return b;
  if (fa * fb > 0) throw std::runtime_error("root: f(a) and f(b) have the same sign; the interval does not bracket a root");
  double c = a, fc = fa, d = b - a, e2 = d;
  for (int i = 0; i < 200; i++) {  // Brent's method
    if (fb * fc > 0) { c = a; fc = fa; d = b - a; e2 = d; }
    if (std::fabs(fc) < std::fabs(fb)) { a = b; b = c; c = a; fa = fb; fb = fc; fc = fa; }
    double tol1 = 2 * 2.2e-16 * std::fabs(b) + 0.5 * tol, xm = 0.5 * (c - b);
    if (std::fabs(xm) <= tol1 || fb == 0) return b;
    if (std::fabs(e2) >= tol1 && std::fabs(fa) > std::fabs(fb)) {
      double s = fb / fa, p, q;
      if (a == c) { p = 2 * xm * s; q = 1 - s; }
      else { double qq = fa / fc, r = fb / fc; p = s * (2 * xm * qq * (qq - r) - (b - a) * (r - 1)); q = (qq - 1) * (r - 1) * (s - 1); }
      if (p > 0) q = -q;
      p = std::fabs(p);
      if (2 * p < std::min(3 * xm * q - std::fabs(tol1 * q), std::fabs(e2 * q))) { e2 = d; d = p / q; }
      else { d = xm; e2 = d; }
    } else { d = xm; e2 = d; }
    a = b; fa = fb;
    b += std::fabs(d) > tol1 ? d : (xm > 0 ? tol1 : -tol1);
    fb = f(b);
  }
  throw std::runtime_error("root: no convergence");
}

Mat minimize(const std::string &expr, const std::string &vars, const Mat &x0, double tol, int max_iter) {
  auto names = split_names(vars);
  int n = (int)names.size();
  if (x0.size() != n) throw std::runtime_error("minimize: start vector length does not match the variables");
  Expr e(expr, names);
  auto f = [&](const Eigen::VectorXd &x) { return e.eval(x.data()); };
  std::vector<Eigen::VectorXd> p(n + 1, Eigen::VectorXd(x0.col(0)));
  for (int i = 0; i < n; i++) p[i + 1](i) += p[i + 1](i) != 0 ? 0.05 * p[i + 1](i) : 0.00025;
  std::vector<double> fv(n + 1);
  for (int i = 0; i <= n; i++) fv[i] = f(p[i]);
  std::vector<int> idx(n + 1);
  for (int it = 0; it < max_iter; it++) {
    for (int i = 0; i <= n; i++) idx[i] = i;
    std::sort(idx.begin(), idx.end(), [&](int a, int b) { return fv[a] < fv[b]; });
    int lo = idx[0], hi = idx[n], nh = idx[n - 1];
    if (std::fabs(fv[hi] - fv[lo]) <= tol * (std::fabs(fv[hi]) + std::fabs(fv[lo]) + 1e-30)) break;
    Eigen::VectorXd c = Eigen::VectorXd::Zero(n);
    for (int i = 0; i <= n; i++) if (i != hi) c += p[i];
    c /= n;
    Eigen::VectorXd r = c + (c - p[hi]);
    double fr = f(r);
    if (fr < fv[lo]) {
      Eigen::VectorXd ex = c + 2 * (c - p[hi]);
      double fe = f(ex);
      if (fe < fr) { p[hi] = ex; fv[hi] = fe; } else { p[hi] = r; fv[hi] = fr; }
    } else if (fr < fv[nh]) { p[hi] = r; fv[hi] = fr; }
    else {
      Eigen::VectorXd k = fr < fv[hi] ? Eigen::VectorXd(c + 0.5 * (r - c)) : Eigen::VectorXd(c + 0.5 * (p[hi] - c));
      double fk = f(k);
      if (fk < std::min(fr, fv[hi])) { p[hi] = k; fv[hi] = fk; }
      else for (int i = 0; i <= n; i++) if (i != lo) { p[i] = p[lo] + 0.5 * (p[i] - p[lo]); fv[i] = f(p[i]); }
    }
  }
  int best = (int)(std::min_element(fv.begin(), fv.end()) - fv.begin());
  return Mat(p[best]);
}

Mat polyfit(const Mat &x, const Mat &y, int degree) {
  if (x.size() != y.size() || x.size() == 0) throw std::runtime_error("polyfit: x and y must be non-empty and the same length");
  if (degree < 0 || degree + 1 > x.size()) throw std::runtime_error("polyfit: degree needs at least degree+1 points");
  Mat A(x.size(), degree + 1);
  for (int i = 0; i < x.size(); i++) { double v = 1; for (int j = 0; j <= degree; j++) { A(i, j) = v; v *= x(i); } }
  return A.bdcSvd(Eigen::ComputeThinU | Eigen::ComputeThinV).solve(Mat(y.reshaped(y.size(), 1)));
}

double polyval(const Mat &c, double x) {
  double r = 0;
  for (int i = (int)c.size() - 1; i >= 0; i--) r = r * x + c(i);
  return r;
}

double interp1(const Mat &x, const Mat &y, double at) {
  int n = (int)x.size();
  if (n < 2 || y.size() != n) throw std::runtime_error("interp: need matching x and y with at least 2 points");
  if (at <= x(0)) return y(0);
  if (at >= x(n - 1)) return y(n - 1);
  int lo = 0, hi = n - 1;
  while (hi - lo > 1) { int m = (lo + hi) / 2; (x(m) <= at ? lo : hi) = m; }
  double t = (at - x(lo)) / (x(hi) - x(lo));
  return y(lo) + t * (y(hi) - y(lo));
}

// ------------------------------------------------------------------ ODE (CVODE)
namespace {
struct OdeCtx {
  std::vector<std::unique_ptr<Expr>> f;
  int n;
};
int ode_rhs(sunrealtype t, N_Vector y, N_Vector ydot, void *user) {
  auto *c = static_cast<OdeCtx *>(user);
  std::vector<double> v(c->n + 1);
  v[0] = t;
  for (int i = 0; i < c->n; i++) v[i + 1] = NV_Ith_S(y, i);
  for (int i = 0; i < c->n; i++) NV_Ith_S(ydot, i) = c->f[i]->eval(v.data());
  return 0;
}
struct Ctx {
  SUNContext ctx = nullptr;
  Ctx() { if (SUNContext_Create(SUN_COMM_NULL, &ctx) != 0) throw std::runtime_error("SUNDIALS context creation failed"); }
  ~Ctx() { SUNContext_Free(&ctx); }
};
}  // namespace

Mat ode_solve(const OdeSpec &s, double t0, double t1, int points) {
  if (s.n <= 0) throw std::runtime_error("ode: no equations");
  if (points < 2) throw std::runtime_error("ode: points must be at least 2");
  if ((int)s.rhs.size() != s.n || (int)s.y0.size() != s.n) throw std::runtime_error("ode: every equation needs rhs() and init()");
  OdeCtx c;
  c.n = s.n;
  std::vector<std::string> vars{"t"};
  for (int i = 0; i < s.n; i++) vars.push_back("y" + std::to_string(i));
  for (int i = 0; i < s.n; i++) {
    if (s.rhs[i].empty()) throw std::runtime_error("ode: equation " + std::to_string(i) + " has no rhs");
    c.f.push_back(std::make_unique<Expr>(s.rhs[i], vars, s.params));
  }
  Ctx sc;
  N_Vector y = N_VNew_Serial(s.n, sc.ctx);
  for (int i = 0; i < s.n; i++) NV_Ith_S(y, i) = s.y0[i];
  void *mem = CVodeCreate(s.stiff ? CV_BDF : CV_ADAMS, sc.ctx);
  SUNMatrix A = SUNDenseMatrix(s.n, s.n, sc.ctx);
  SUNLinearSolver LS = SUNLinSol_Dense(y, A, sc.ctx);
  auto cleanup = [&] { SUNLinSolFree(LS); SUNMatDestroy(A); CVodeFree(&mem); N_VDestroy(y); };
  try {
    if (CVodeInit(mem, ode_rhs, t0, y) != CV_SUCCESS) throw std::runtime_error("ode: CVodeInit failed");
    CVodeSStolerances(mem, s.rtol, s.atol);
    CVodeSetUserData(mem, &c);
    CVodeSetLinearSolver(mem, LS, A);
    CVodeSetMaxNumSteps(mem, s.max_steps);
    Mat out(points, s.n + 1);
    out(0, 0) = t0;
    for (int i = 0; i < s.n; i++) out(0, i + 1) = s.y0[i];
    for (int k = 1; k < points; k++) {
      double tout = t0 + (t1 - t0) * k / (points - 1), t = t0;
      int flag = CVode(mem, tout, y, &t, CV_NORMAL);
      if (flag < 0) throw std::runtime_error("ode: CVODE failed at t=" + std::to_string(t) + " (flag " + std::to_string(flag) + (flag == CV_TOO_MUCH_WORK ? ", too many steps: try stiff()" : "") + ")");
      out(k, 0) = t;
      for (int i = 0; i < s.n; i++) out(k, i + 1) = NV_Ith_S(y, i);
    }
    cleanup();
    return out;
  } catch (...) { cleanup(); throw; }
}

// ------------------------------------------------------------------ nonlinear systems (KINSOL)
namespace {
struct KinCtx { std::vector<std::unique_ptr<Expr>> f; int n; };
int kin_f(N_Vector u, N_Vector fval, void *user) {
  auto *c = static_cast<KinCtx *>(user);
  std::vector<double> v(c->n);
  for (int i = 0; i < c->n; i++) v[i] = NV_Ith_S(u, i);
  for (int i = 0; i < c->n; i++) NV_Ith_S(fval, i) = c->f[i]->eval(v.data());
  return 0;
}
}  // namespace

Mat nonlinear_solve(const std::vector<std::string> &eqs, const Mat &guess, double tol) {
  int n = (int)eqs.size();
  if (guess.size() != n) throw std::runtime_error("nlsolve: initial guess length must equal the number of equations");
  KinCtx c; c.n = n;
  std::vector<std::string> vars;
  for (int i = 0; i < n; i++) vars.push_back("x" + std::to_string(i));
  for (auto &e : eqs) c.f.push_back(std::make_unique<Expr>(e, vars));
  Ctx sc;
  N_Vector u = N_VNew_Serial(n, sc.ctx), scale = N_VNew_Serial(n, sc.ctx);
  for (int i = 0; i < n; i++) { NV_Ith_S(u, i) = guess(i); NV_Ith_S(scale, i) = 1.0; }
  void *mem = KINCreate(sc.ctx);
  SUNMatrix A = SUNDenseMatrix(n, n, sc.ctx);
  SUNLinearSolver LS = SUNLinSol_Dense(u, A, sc.ctx);
  auto cleanup = [&] { SUNLinSolFree(LS); SUNMatDestroy(A); KINFree(&mem); N_VDestroy(u); N_VDestroy(scale); };
  try {
    KINInit(mem, kin_f, u);
    KINSetUserData(mem, &c);
    KINSetFuncNormTol(mem, tol);
    KINSetLinearSolver(mem, LS, A);
    KINSetNumMaxIters(mem, 200);
    int flag = KINSol(mem, u, KIN_LINESEARCH, scale, scale);
    if (flag < 0) throw std::runtime_error("nlsolve: KINSOL failed (flag " + std::to_string(flag) + "); try another initial guess");
    Mat r(n, 1);
    for (int i = 0; i < n; i++) r(i) = NV_Ith_S(u, i);
    cleanup();
    return r;
  } catch (...) { cleanup(); throw; }
}

}  // namespace lmnum

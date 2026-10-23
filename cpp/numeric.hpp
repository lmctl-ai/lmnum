// Numeric routines behind the lmnum schema. Plain C++; no knowledge of the DSL.
#pragma once
#include <Eigen/Dense>
#include <map>
#include <string>
#include <vector>

namespace lmnum {

using Mat = Eigen::MatrixXd;

double integrate(const std::string &expr, const std::string &var, double a, double b, double tol);
double find_root(const std::string &expr, const std::string &var, double a, double b, double tol);
// Nelder-Mead on the named variables, starting at x0 (n x 1). Returns the minimiser (n x 1).
Mat minimize(const std::string &expr, const std::string &vars, const Mat &x0, double tol, int max_iter);
Mat polyfit(const Mat &x, const Mat &y, int degree);
double polyval(const Mat &coeffs, double x);  // coefficients in ascending powers
double interp1(const Mat &x, const Mat &y, double at);  // piecewise linear, x ascending

struct OdeSpec {
  int n = 0;
  std::vector<std::string> rhs;                 // d y_i / dt, expression in t, y0..y{n-1} and params
  std::vector<double> y0;
  std::map<std::string, double> params;
  double rtol = 1e-8, atol = 1e-10;
  bool stiff = false;                           // BDF (stiff) instead of Adams
  long max_steps = 500000;
};
// Rows: t, y0..y{n-1} at `points` equally spaced output times from t0 to t1 (points >= 2).
Mat ode_solve(const OdeSpec &spec, double t0, double t1, int points);

// Solve F(x) = 0 for a system of n equations in x0..x{n-1} (KINSOL); returns n x 1.
Mat nonlinear_solve(const std::vector<std::string> &eqs, const Mat &guess, double tol);

}  // namespace lmnum

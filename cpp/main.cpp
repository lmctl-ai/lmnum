// lmnum: Eigen + SUNDIALS (CVODE, KINSOL) behind an lmscript `_dsl_` schema. Scripting only:
// the executable has no user-facing commands besides --dsl and the schema/version queries.
#include <cmath>
#include <algorithm>
#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <iostream>
#include <memory>
#include <random>
#include <sstream>
#include <string>
#include <vector>
#ifdef _WIN32
#include <fcntl.h>
#include <io.h>
#endif

#include "dslvm.hpp"
#include "expr.hpp"
#include "memory_budget.hpp"
#include "notices_embedded.hpp"
#include "numeric.hpp"
#include "schema_embedded.hpp"

namespace {
using dslvm::Args;
using dslvm::Value;
using lmnum::Mat;

struct Func { std::unique_ptr<lmnum::Expr> e; int nvars; std::string text; };
struct Ode { lmnum::OdeSpec spec; };
struct System { std::vector<std::string> eqs; };

struct Host {
  bool dry_run = false;  // --dry-run: save_csv reports the file it would write and writes nothing
  std::vector<std::unique_ptr<Mat>> mats;
  std::vector<std::unique_ptr<Func>> funcs;
  std::vector<std::unique_ptr<Ode>> odes;
  std::vector<std::unique_ptr<System>> systems;
  template <class T> Value hold(std::vector<std::unique_ptr<T>> &arena, const char *type, T v) {
    if (arena.size() >= 4000000) throw dslvm::Error(std::string(type) + " object limit exceeded");
    arena.push_back(std::make_unique<T>(std::move(v)));
    return Value::object(type, arena.back().get());
  }
  // Matrix payloads come from Eigen's malloc, outside operator new: count them while the arena keeps them.
  Value mat(Mat m) {
    membudget::charge(std::size_t(m.size()) * sizeof(double));
    return hold(mats, "Matrix", std::move(m));
  }
};

template <class F> Value translate(F &&fn) {
  try { return fn(); }
  catch (const dslvm::Error &) { throw; }
  catch (const std::exception &e) { throw dslvm::Error(e.what()); }
}

void check_args(const char *who, const std::vector<std::string> &params, Args &a) {
  for (size_t i = 0; i < params.size(); i++) {
    const auto &want = params[i];
    const auto &v = a[i];
    bool ok = want == "float" ? v.kind == Value::FLOAT
              : want == "int" ? v.kind == Value::INT
              : want == "string" ? v.kind == Value::STR
              : v.kind == Value::OBJ && v.type == want && v.obj;
    if (!ok) throw dslvm::Error(std::string(who) + " argument " + std::to_string(i + 1) + " must be " + want);
  }
}

void method(dslvm::Registry &r, const char *type, const char *name, std::vector<std::string> params, std::string returns,
            dslvm::Method cb) {
  std::string who = std::string(type) + "." + name;
  r.method(type, name, params, returns, [who, params, cb](void *self, Args &a) {
    check_args(who.c_str(), params, a);
    return translate([&] { return cb(self, a); });
  });
}

Mat &M(void *p) { return *static_cast<Mat *>(p); }
Mat &arg_mat(Value &v) { return *static_cast<Mat *>(v.obj); }
void need_index(const Mat &m, int64_t i, int64_t j, const char *who) {
  if (i < 0 || j < 0 || i >= m.rows() || j >= m.cols())
    throw dslvm::Error(std::string(who) + ": index (" + std::to_string(i) + "," + std::to_string(j) + ") outside " +
                       std::to_string(m.rows()) + "x" + std::to_string(m.cols()));
}
void same_shape(const Mat &a, const Mat &b, const char *who) {
  if (a.rows() != b.rows() || a.cols() != b.cols())
    throw dslvm::Error(std::string(who) + ": shapes " + std::to_string(a.rows()) + "x" + std::to_string(a.cols()) + " and " +
                       std::to_string(b.rows()) + "x" + std::to_string(b.cols()) + " differ");
}
void square(const Mat &a, const char *who) {
  if (a.rows() != a.cols()) throw dslvm::Error(std::string(who) + ": matrix must be square");
}

std::string fmt(double x) { char b[40]; std::snprintf(b, sizeof b, "%.10g", x); return b; }
// Shortest of %.15g/%.16g/%.17g that reads back as the same double: files round-trip exactly.
std::string fmt_exact(double x) {
  char b[40];
  for (int prec = 15; prec <= 17; prec++) {
    std::snprintf(b, sizeof b, "%.*g", prec, x);
    if (std::strtod(b, nullptr) == x || std::isnan(x)) break;
  }
  return b;
}

// Matrix sizes from script integers: non-negative, at most 1e8 entries (no int64 overflow).
void need_dims(int64_t r, int64_t c, const char *who) {
  if (r < 0 || c < 0 || r > 100000000 || c > 100000000 || (r > 0 && c > 100000000 / r))
    throw dslvm::Error(std::string(who) + ": bad size " + std::to_string(r) + "x" + std::to_string(c) +
                       " (rows and columns must be >= 0, at most 1e8 entries)");
  membudget::require(std::size_t(r) * std::size_t(c) * sizeof(double));  // fail before allocating
}
void need_finite(const Mat &m, const char *who) {
  if (!m.allFinite()) throw dslvm::Error(std::string(who) + ": matrix contains NaN or infinity");
}
void need_symmetric(const Mat &m, const char *who) {
  square(m, who);
  need_finite(m, who);
  double scale = m.size() ? m.cwiseAbs().maxCoeff() : 0.0;
  if ((m - m.transpose()).cwiseAbs().maxCoeff() > 1e-10 * std::max(1.0, scale))
    throw dslvm::Error(std::string(who) + ": matrix is not symmetric");
}

// Portable random numbers: mt19937_64 is fully specified by the standard, but the
// std::*_distribution algorithms are implementation-defined (libstdc++ and libc++ differ).
// These are explicit so a seed gives the same matrix on every platform.
double uniform01(std::mt19937_64 &g) { return (double)(g() >> 11) * 0x1.0p-53; }  // [0, 1)
double std_normal(std::mt19937_64 &g, bool &have, double &spare) {  // Marsaglia polar method
  if (have) { have = false; return spare; }
  double u, v, s;
  do { u = 2 * uniform01(g) - 1; v = 2 * uniform01(g) - 1; s = u * u + v * v; } while (s >= 1 || s == 0);
  double k = std::sqrt(-2 * std::log(s) / s);
  spare = v * k; have = true;
  return u * k;
}

Mat parse_matrix(const std::string &text) {
  std::vector<std::vector<double>> rows;
  std::vector<double> cur;
  std::string tok;
  auto flush_tok = [&] {
    if (tok.empty()) return;
    size_t used = 0;
    double v;
    try { v = std::stod(tok, &used); } catch (...) { used = 0; v = 0; }
    if (used != tok.size()) throw std::runtime_error("matrix text: bad number '" + tok + "'");
    if (!std::isfinite(v)) throw std::runtime_error("matrix text: '" + tok + "' is not a finite number");
    cur.push_back(v);
    tok.clear();
  };
  auto flush_row = [&] { flush_tok(); if (!cur.empty()) rows.push_back(cur); cur.clear(); };
  for (char c : text) {
    if (c == ';' || c == '\n') flush_row();
    else if (c == ',' || c == ' ' || c == '\t' || c == '\r') flush_tok();
    else tok += c;
  }
  flush_row();
  if (rows.empty()) throw std::runtime_error("matrix text is empty");
  Mat m(rows.size(), rows[0].size());
  for (size_t i = 0; i < rows.size(); i++) {
    if (rows[i].size() != rows[0].size()) throw std::runtime_error("matrix text: row " + std::to_string(i + 1) + " has a different length");
    for (size_t j = 0; j < rows[i].size(); j++) m(i, j) = rows[i][j];
  }
  return m;
}

std::string to_text(const Mat &m) {
  std::string s;
  for (int i = 0; i < m.rows(); i++) {
    for (int j = 0; j < m.cols(); j++) { if (j) s += ' '; s += fmt(m(i, j)); }
    s += '\n';
  }
  return s;
}

void register_host(dslvm::Registry &r, Host &h) {
  r.context("num", "Num");

  // ---------------------------------------------------------------- Num
  method(r, "Num", "matrix", {"int", "int"}, "Matrix", [&h](void *, Args &a) {
    need_dims(a[0].i, a[1].i, "Num.matrix");
    return h.mat(Mat::Zero(a[0].i, a[1].i));
  });
  method(r, "Num", "identity", {"int"}, "Matrix", [&h](void *, Args &a) {
    if (a[0].i < 1 || a[0].i > 20000) throw dslvm::Error("Num.identity: bad size");
    return h.mat(Mat::Identity(a[0].i, a[0].i));
  });
  method(r, "Num", "parse", {"string"}, "Matrix", [&h](void *, Args &a) { return h.mat(parse_matrix(a[0].s)); });
  method(r, "Num", "linspace", {"float", "float", "int"}, "Matrix", [&h](void *, Args &a) {
    if (a[2].i < 2) throw dslvm::Error("Num.linspace: need at least 2 points");
    if (a[2].i > 100000000) throw dslvm::Error("Num.linspace: at most 1e8 points");
    if (!std::isfinite(a[0].f) || !std::isfinite(a[1].f)) throw dslvm::Error("Num.linspace: ends must be finite");
    return h.mat(Mat(Eigen::VectorXd::LinSpaced(a[2].i, a[0].f, a[1].f)));
  });
  method(r, "Num", "random", {"int", "int", "int"}, "Matrix", [&h](void *, Args &a) {
    need_dims(a[0].i, a[1].i, "Num.random");
    std::mt19937_64 g((uint64_t)a[2].i);
    Mat m(a[0].i, a[1].i);
    for (Eigen::Index i = 0; i < m.rows(); i++) for (Eigen::Index j = 0; j < m.cols(); j++) m(i, j) = uniform01(g);
    return h.mat(m);
  });
  method(r, "Num", "normal", {"int", "int", "int"}, "Matrix", [&h](void *, Args &a) {
    need_dims(a[0].i, a[1].i, "Num.normal");
    std::mt19937_64 g((uint64_t)a[2].i);
    bool have = false; double spare = 0;
    Mat m(a[0].i, a[1].i);
    for (Eigen::Index i = 0; i < m.rows(); i++) for (Eigen::Index j = 0; j < m.cols(); j++) m(i, j) = std_normal(g, have, spare);
    return h.mat(m);
  });
  method(r, "Num", "load_csv", {"string"}, "Matrix", [&h](void *, Args &a) {
    std::ifstream f(a[0].s);
    if (!f) throw dslvm::Error("Num.load_csv: cannot open " + a[0].s);
    std::stringstream ss; ss << f.rdbuf();
    std::string t = ss.str();
    // skip a header row that does not start with a number
    size_t nl = t.find('\n');
    if (nl != std::string::npos) { char c = t.empty() ? 0 : t[0]; if (std::isalpha((unsigned char)c)) t = t.substr(nl + 1); }
    return h.mat(parse_matrix(t));
  });
  method(r, "Num", "eval", {"string"}, "float", [](void *, Args &a) {
    lmnum::Expr e(a[0].s, {});
    return Value::real(e.eval(nullptr));
  });
  method(r, "Num", "func", {"string", "string"}, "Func", [&h](void *, Args &a) {
    auto names = lmnum::split_names(a[1].s);
    Func f{std::make_unique<lmnum::Expr>(a[0].s, names), (int)names.size(), a[0].s};
    return h.hold(h.funcs, "Func", std::move(f));
  });
  method(r, "Num", "ode", {"int"}, "Ode", [&h](void *, Args &a) {
    if (a[0].i < 1 || a[0].i > 10000) throw dslvm::Error("Num.ode: bad number of equations");
    Ode o; o.spec.n = (int)a[0].i; o.spec.rhs.assign(a[0].i, ""); o.spec.y0.assign(a[0].i, 0.0);
    return h.hold(h.odes, "Ode", std::move(o));
  });
  method(r, "Num", "system", {"int"}, "System", [&h](void *, Args &a) {
    if (a[0].i < 1 || a[0].i > 10000) throw dslvm::Error("Num.system: bad number of equations");
    System s; s.eqs.assign(a[0].i, "");
    return h.hold(h.systems, "System", std::move(s));
  });
  method(r, "Num", "integrate", {"string", "string", "float", "float"}, "float", [](void *, Args &a) {
    return Value::real(lmnum::integrate(a[0].s, a[1].s, a[2].f, a[3].f, 1e-10));
  });
  method(r, "Num", "root", {"string", "string", "float", "float"}, "float", [](void *, Args &a) {
    return Value::real(lmnum::find_root(a[0].s, a[1].s, a[2].f, a[3].f, 1e-12));
  });
  method(r, "Num", "minimize", {"string", "string", "Matrix"}, "Matrix", [&h](void *, Args &a) {
    return h.mat(lmnum::minimize(a[0].s, a[1].s, arg_mat(a[2]), 1e-12, 20000));
  });
  method(r, "Num", "polyfit", {"Matrix", "Matrix", "int"}, "Matrix", [&h](void *, Args &a) {
    if (a[2].i < 0 || a[2].i > 1000) throw dslvm::Error("Num.polyfit: degree must be 0..1000");
    return h.mat(lmnum::polyfit(arg_mat(a[0]), arg_mat(a[1]), (int)a[2].i));
  });
  method(r, "Num", "polyval", {"Matrix", "float"}, "float", [](void *, Args &a) {
    return Value::real(lmnum::polyval(arg_mat(a[0]), a[1].f));
  });
  method(r, "Num", "interp", {"Matrix", "Matrix", "float"}, "float", [](void *, Args &a) {
    return Value::real(lmnum::interp1(arg_mat(a[0]), arg_mat(a[1]), a[2].f));
  });
  method(r, "Num", "assert_close", {"float", "float", "float"}, "void", [](void *, Args &a) {
    if (!(std::fabs(a[0].f - a[1].f) <= a[2].f))
      throw dslvm::Error("assert_close failed: " + fmt(a[0].f) + " vs " + fmt(a[1].f) + " (tolerance " + fmt(a[2].f) + ")");
    return Value::none();
  });
  method(r, "Num", "print", {"string"}, "void", [](void *, Args &a) { std::cout << a[0].s << std::endl; return Value::none(); });
  method(r, "Num", "version", {}, "string", [](void *, Args &) { return Value::string("lmnum " LMNUM_VERSION); });

  // ---------------------------------------------------------------- Matrix
  method(r, "Matrix", "rows", {}, "int", [](void *p, Args &) { return Value::integer(M(p).rows()); });
  method(r, "Matrix", "cols", {}, "int", [](void *p, Args &) { return Value::integer(M(p).cols()); });
  method(r, "Matrix", "get", {"int", "int"}, "float", [](void *p, Args &a) { need_index(M(p), a[0].i, a[1].i, "Matrix.get"); return Value::real(M(p)(a[0].i, a[1].i)); });
  method(r, "Matrix", "set", {"int", "int", "float"}, "Matrix", [](void *p, Args &a) { need_index(M(p), a[0].i, a[1].i, "Matrix.set"); M(p)(a[0].i, a[1].i) = a[2].f; return Value::object("Matrix", p); });
  method(r, "Matrix", "copy", {}, "Matrix", [&h](void *p, Args &) { return h.mat(M(p)); });
  method(r, "Matrix", "add", {"Matrix"}, "Matrix", [&h](void *p, Args &a) { same_shape(M(p), arg_mat(a[0]), "Matrix.add"); return h.mat(M(p) + arg_mat(a[0])); });
  method(r, "Matrix", "sub", {"Matrix"}, "Matrix", [&h](void *p, Args &a) { same_shape(M(p), arg_mat(a[0]), "Matrix.sub"); return h.mat(M(p) - arg_mat(a[0])); });
  method(r, "Matrix", "hadamard", {"Matrix"}, "Matrix", [&h](void *p, Args &a) { same_shape(M(p), arg_mat(a[0]), "Matrix.hadamard"); return h.mat(M(p).cwiseProduct(arg_mat(a[0]))); });
  method(r, "Matrix", "mul", {"Matrix"}, "Matrix", [&h](void *p, Args &a) {
    if (M(p).cols() != arg_mat(a[0]).rows()) throw dslvm::Error("Matrix.mul: inner dimensions differ");
    return h.mat(M(p) * arg_mat(a[0]));
  });
  method(r, "Matrix", "scale", {"float"}, "Matrix", [&h](void *p, Args &a) { return h.mat(M(p) * a[0].f); });
  method(r, "Matrix", "shift", {"float"}, "Matrix", [&h](void *p, Args &a) { return h.mat(M(p).array() + a[0].f); });
  method(r, "Matrix", "transpose", {}, "Matrix", [&h](void *p, Args &) { return h.mat(M(p).transpose()); });
  method(r, "Matrix", "inverse", {}, "Matrix", [&h](void *p, Args &) {
    square(M(p), "Matrix.inverse");
    need_finite(M(p), "Matrix.inverse");
    Eigen::FullPivLU<Mat> lu(M(p));
    if (!lu.isInvertible()) throw dslvm::Error("Matrix.inverse: matrix is singular");
    return h.mat(lu.inverse());
  });
  method(r, "Matrix", "det", {}, "float", [](void *p, Args &) { square(M(p), "Matrix.det"); return Value::real(M(p).determinant()); });
  method(r, "Matrix", "trace", {}, "float", [](void *p, Args &) { square(M(p), "Matrix.trace"); return Value::real(M(p).trace()); });
  method(r, "Matrix", "norm", {}, "float", [](void *p, Args &) { return Value::real(M(p).norm()); });
  method(r, "Matrix", "solve", {"Matrix"}, "Matrix", [&h](void *p, Args &a) {
    square(M(p), "Matrix.solve");
    if (M(p).rows() != arg_mat(a[0]).rows()) throw dslvm::Error("Matrix.solve: right-hand side has the wrong number of rows");
    need_finite(M(p), "Matrix.solve");
    // Full pivoting with Eigen's rank threshold: an exact-zero determinant test misses
    // numerically singular matrices (det of [1 2 3; 4 5 6; 7 8 9] is 6.7e-16 in doubles).
    Eigen::FullPivLU<Mat> lu(M(p));
    if (!lu.isInvertible()) throw dslvm::Error("Matrix.solve: matrix is singular");
    return h.mat(lu.solve(arg_mat(a[0])));
  });
  method(r, "Matrix", "lstsq", {"Matrix"}, "Matrix", [&h](void *p, Args &a) {
    if (M(p).rows() != arg_mat(a[0]).rows()) throw dslvm::Error("Matrix.lstsq: right-hand side has the wrong number of rows");
    return h.mat(M(p).bdcSvd(Eigen::ComputeThinU | Eigen::ComputeThinV).solve(arg_mat(a[0])));
  });
  method(r, "Matrix", "eig_sym", {}, "Matrix", [&h](void *p, Args &) {
    need_symmetric(M(p), "Matrix.eig_sym");
    Eigen::SelfAdjointEigenSolver<Mat> s(M(p));
    if (s.info() != Eigen::Success) throw dslvm::Error("Matrix.eig_sym: eigensolver did not converge");
    return h.mat(Mat(s.eigenvalues()));
  });
  method(r, "Matrix", "eigvec_sym", {}, "Matrix", [&h](void *p, Args &) {
    need_symmetric(M(p), "Matrix.eigvec_sym");
    Eigen::SelfAdjointEigenSolver<Mat> s(M(p));
    if (s.info() != Eigen::Success) throw dslvm::Error("Matrix.eigvec_sym: eigensolver did not converge");
    return h.mat(s.eigenvectors());
  });
  method(r, "Matrix", "svd_values", {}, "Matrix", [&h](void *p, Args &) { return h.mat(Mat(M(p).bdcSvd().singularValues())); });
  method(r, "Matrix", "col", {"int"}, "Matrix", [&h](void *p, Args &a) { need_index(M(p), 0, a[0].i, "Matrix.col"); return h.mat(M(p).col(a[0].i)); });
  method(r, "Matrix", "row", {"int"}, "Matrix", [&h](void *p, Args &a) { need_index(M(p), a[0].i, 0, "Matrix.row"); return h.mat(M(p).row(a[0].i)); });
  method(r, "Matrix", "hstack", {"Matrix"}, "Matrix", [&h](void *p, Args &a) {
    if (M(p).rows() != arg_mat(a[0]).rows()) throw dslvm::Error("Matrix.hstack: row counts differ");
    Mat m(M(p).rows(), M(p).cols() + arg_mat(a[0]).cols()); m << M(p), arg_mat(a[0]); return h.mat(m);
  });
  method(r, "Matrix", "vstack", {"Matrix"}, "Matrix", [&h](void *p, Args &a) {
    if (M(p).cols() != arg_mat(a[0]).cols()) throw dslvm::Error("Matrix.vstack: column counts differ");
    Mat m(M(p).rows() + arg_mat(a[0]).rows(), M(p).cols()); m << M(p), arg_mat(a[0]); return h.mat(m);
  });
  method(r, "Matrix", "sum", {}, "float", [](void *p, Args &) { return Value::real(M(p).sum()); });
  method(r, "Matrix", "mean", {}, "float", [](void *p, Args &) { if (!M(p).size()) throw dslvm::Error("Matrix.mean: empty"); return Value::real(M(p).mean()); });
  method(r, "Matrix", "min", {}, "float", [](void *p, Args &) { if (!M(p).size()) throw dslvm::Error("Matrix.min: empty"); return Value::real(M(p).minCoeff()); });
  method(r, "Matrix", "max", {}, "float", [](void *p, Args &) { if (!M(p).size()) throw dslvm::Error("Matrix.max: empty"); return Value::real(M(p).maxCoeff()); });
  method(r, "Matrix", "std", {}, "float", [](void *p, Args &) {
    if (M(p).size() < 2) throw dslvm::Error("Matrix.std: need at least 2 values");
    double mu = M(p).mean();
    return Value::real(std::sqrt((M(p).array() - mu).square().sum() / (M(p).size() - 1)));
  });
  method(r, "Matrix", "map", {"Func"}, "Matrix", [&h](void *p, Args &a) {
    auto *f = static_cast<Func *>(a[0].obj);
    if (f->nvars != 1) throw dslvm::Error("Matrix.map: the function must have exactly one variable");
    Mat m = M(p);
    for (int i = 0; i < m.rows(); i++) for (int j = 0; j < m.cols(); j++) { double x = m(i, j); m(i, j) = f->e->eval(&x); }
    return h.mat(m);
  });
  method(r, "Matrix", "to_text", {}, "string", [](void *p, Args &) { return Value::string(to_text(M(p))); });
  method(r, "Matrix", "save_csv", {"string"}, "void", [&h](void *p, Args &a) {
    if (h.dry_run) {
      std::cerr << "[dry-run] would write " << a[0].s << " (" << M(p).rows() << "x" << M(p).cols() << ")\n";
      return Value::none();
    }
    std::ofstream f(a[0].s);
    if (!f) throw dslvm::Error("Matrix.save_csv: cannot write " + a[0].s);
    for (int i = 0; i < M(p).rows(); i++) { for (int j = 0; j < M(p).cols(); j++) f << (j ? " " : "") << fmt_exact(M(p)(i, j)); f << "\n"; }
    f.close();
    if (!f) throw dslvm::Error("Matrix.save_csv: write failed for " + a[0].s);
    return Value::none();
  });

  // ---------------------------------------------------------------- Func
  method(r, "Func", "eval", {"float"}, "float", [](void *p, Args &a) {
    auto *f = static_cast<Func *>(p);
    if (f->nvars != 1) throw dslvm::Error("Func.eval: the function has " + std::to_string(f->nvars) + " variables; use eval2 for two");
    double x = a[0].f; return Value::real(f->e->eval(&x));
  });
  method(r, "Func", "eval2", {"float", "float"}, "float", [](void *p, Args &a) {
    auto *f = static_cast<Func *>(p);
    if (f->nvars != 2) throw dslvm::Error("Func.eval2: the function does not have exactly two variables");
    double x[2] = {a[0].f, a[1].f}; return Value::real(f->e->eval(x));
  });

  // ---------------------------------------------------------------- Ode
  auto ode = [](void *p) -> lmnum::OdeSpec & { return static_cast<Ode *>(p)->spec; };
  method(r, "Ode", "rhs", {"int", "string"}, "Ode", [ode](void *p, Args &a) {
    if (a[0].i < 0 || a[0].i >= ode(p).n) throw dslvm::Error("Ode.rhs: equation index out of range");
    ode(p).rhs[a[0].i] = a[1].s; return Value::object("Ode", p);
  });
  method(r, "Ode", "init", {"int", "float"}, "Ode", [ode](void *p, Args &a) {
    if (a[0].i < 0 || a[0].i >= ode(p).n) throw dslvm::Error("Ode.init: variable index out of range");
    ode(p).y0[a[0].i] = a[1].f; return Value::object("Ode", p);
  });
  method(r, "Ode", "param", {"string", "float"}, "Ode", [ode](void *p, Args &a) { ode(p).params[a[0].s] = a[1].f; return Value::object("Ode", p); });
  method(r, "Ode", "tol", {"float", "float"}, "Ode", [ode](void *p, Args &a) {
    if (!(a[0].f >= 0 && a[1].f >= 0 && std::isfinite(a[0].f) && std::isfinite(a[1].f) && a[0].f + a[1].f > 0))
      throw dslvm::Error("Ode.tol: tolerances must be finite, >= 0 and not both zero");
    ode(p).rtol = a[0].f; ode(p).atol = a[1].f; return Value::object("Ode", p); });
  method(r, "Ode", "stiff", {}, "Ode", [ode](void *p, Args &) { ode(p).stiff = true; return Value::object("Ode", p); });
  method(r, "Ode", "solve", {"float", "float", "int"}, "Matrix", [ode, &h](void *p, Args &a) {
    if (a[2].i < 2 || a[2].i > 10000000) throw dslvm::Error("Ode.solve: points must be 2..1e7");
    return h.mat(lmnum::ode_solve(ode(p), a[0].f, a[1].f, (int)a[2].i));
  });

  // ---------------------------------------------------------------- System
  method(r, "System", "eq", {"int", "string"}, "System", [](void *p, Args &a) {
    auto *s = static_cast<System *>(p);
    if (a[0].i < 0 || a[0].i >= (int64_t)s->eqs.size()) throw dslvm::Error("System.eq: index out of range");
    s->eqs[a[0].i] = a[1].s; return Value::object("System", p);
  });
  method(r, "System", "solve", {"Matrix", "float"}, "Matrix", [&h](void *p, Args &a) {
    auto *s = static_cast<System *>(p);
    for (auto &e : s->eqs) if (e.empty()) throw dslvm::Error("System.solve: every equation needs eq()");
    if (!(a[1].f > 0 && std::isfinite(a[1].f))) throw dslvm::Error("System.solve: tolerance must be > 0");
    return h.mat(lmnum::nonlinear_solve(s->eqs, arg_mat(a[0]), a[1].f));
  });
}

const char *usage = "usage: lmnum --version | --notices | --dsl-schema [--json] | --dsl-signatures | [--dry-run] --dsl FILE [FILE ...]\n"
                    "environment: LMNUM_MAX_MEMORY_MB  total memory budget in MiB (default 4096); a program that needs more\n"
                    "             stops with a run error (exit 3) instead of allocating\n";
}  // namespace

int main(int argc, char **argv) {
#ifdef _WIN32
  _setmode(_fileno(stdout), _O_BINARY);
  _setmode(_fileno(stderr), _O_BINARY);
#endif
  Host host;
  dslvm::Registry reg;
  register_host(reg, host);
  std::string a1 = argc > 1 ? argv[1] : "";
  if (argc == 2 && a1 == "--version") { std::cout << "lmnum " LMNUM_VERSION "\n"; return std::cout ? 0 : 4; }
  if (argc == 2 && a1 == "--notices") {
    std::cout.write(reinterpret_cast<const char *>(lmnum::embedded_notices), (std::streamsize)lmnum::embedded_notices_size);
    return std::cout ? 0 : 4;
  }
  if (argc >= 2 && a1 == "--dsl-schema") {
    if (argc == 2) { for (const auto &s : reg.signatures()) std::cout << s << "\n"; return std::cout ? 0 : 4; }
    if (argc == 3 && std::string(argv[2]) == "--json") {
      std::cout.write(reinterpret_cast<const char *>(lmnum::embedded_schema), (std::streamsize)lmnum::embedded_schema_size);
      return std::cout ? 0 : 4;
    }
    std::cerr << usage; return 2;
  }
  if (argc == 2 && a1 == "--dsl-signatures") { for (const auto &s : reg.signatures()) std::cout << s << "\n"; return 0; }
  int first = 2;
  if (argc >= 2 && a1 == "--dry-run") { first = 3; host.dry_run = true; }  // the only side effect is save_csv
  if (argc <= first || std::string(argv[first - 1]) != "--dsl") { std::cerr << usage; return 2; }
  for (int i = first; i < argc; i++)
    if (std::string(argv[i]).empty() || std::string(argv[i]).rfind("--", 0) == 0) { std::cerr << usage; return 2; }
  if (!membudget::configure("lmnum", "LMNUM_MAX_MEMORY_MB")) { std::cerr << usage; return 2; }
  const std::string schema(reinterpret_cast<const char *>(lmnum::embedded_schema), lmnum::embedded_schema_size);
  dslvm::Context context;
  context.set("num", &host);
  std::vector<dslvm::Program> programs;
  for (int i = first; i < argc; i++) {
    try { programs.push_back(dslvm::Program::load(dslvm::read_file(argv[i]), schema, reg)); }
    catch (const dslvm::Error &e) { return dslvm::report_error("load", e); }
    catch (const std::exception &e) { return dslvm::report_error("load", dslvm::Error(e.what())); }
  }
  for (const auto &p : programs) {
    try { p.run(context, reg); }
    catch (const dslvm::Error &e) { return dslvm::report_error("run", e); }
    catch (const std::exception &e) { return dslvm::report_error("run", dslvm::Error(e.what())); }  // budget in the VM
    dslvm::report_ok();
  }
  return 0;
}

# Expression language (`cpp/expr.hpp`)

Recursive descent into a tree of small nodes; evaluation is allocation free. Grammar:

```
add   := mul (('+'|'-') mul)*
mul   := unary (('*'|'/') unary)*
unary := ('-'|'+') unary | pow
pow   := atom (('^'|'**') unary)?          right associative; -2^2 = -4; 2^-1 = 0.5
atom  := number | name | name '(' args ')' | '(' add ')'
```

Numbers: `12`, `1.5`, `.5`, `1e-3`. Names resolve in this order: variables of the call (`"x,y"`),
named parameters (`Ode.param`), then the constants `pi` and `e`. Functions: `sin cos tan asin acos
atan sinh cosh tanh exp log ln log10 sqrt abs floor ceil sign` (1 argument) and `atan2 pow min max
mod` (2 arguments). `log` is the natural logarithm. No comparison, logical or conditional
operators; use `min/max/abs/sign` or split the problem in the script.

Errors name the expression and the column: `expression "2 +* 3": unexpected '*' at column 4`.
Where each API binds variables: `integrate`/`root` take one named variable; `minimize` a comma
list; `func` a comma list; `Ode` uses `t, y0...`; `System` uses `x0...`.

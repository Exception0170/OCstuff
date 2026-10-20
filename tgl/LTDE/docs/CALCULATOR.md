# Calculator

Open Calculator from Start or run `run calc.app`. The compact 36-column window
accepts both button presses and keyboard input; typing appends to the expression.
Enter or `=` evaluates, Backspace removes a character, Escape/Delete clears,
and F2 or the Extended/Basic button switches modes. Clipboard paste is supported.
The `neg` button negates the whole expression. After a result, an operator
continues the calculation; a number or function starts a new expression.
`ans` recalls the last successful result in this calculator window (initially 0).

Basic mode supports decimal/scientific numbers, `+ - * /`, unary signs, and
parentheses, with ordinary arithmetic precedence. Extended mode adds `^`,
`pi`, `e`, and these one-argument functions:

`sqrt abs sin cos tan asin acos atan ln log exp floor ceil`

Trig uses radians; `ln` is natural logarithm and `log` is base 10. Function calls
require parentheses. Powers associate right-to-left; `-2^2` is `-4`. There is no
implicit multiplication, percentage operator, or complex-number support.
Expressions are limited to 512 characters and bounded nesting. Results display
12 significant digits. Invalid input, division by zero, and non-finite results
produce errors without replacing the previous answer.

## CMD

```
calc (2+3)*4
calc "sqrt(81)+2^3"
calc "sin(pi/2)"
```

All scientific features are enabled by default. Each CMD invocation is
independent (`ans` starts at 0); results can be redirected normally.

## Shared engine

Load `/ltde/sys/slib/ltcalc.lua` with `loadfile` from system-mode code.
`evaluate(expression, extended, ans)` returns a number or `nil, error`.
`format(number)` produces the display string. The parser evaluates only its
arithmetic grammar; it never loads or executes the expression as Lua code.

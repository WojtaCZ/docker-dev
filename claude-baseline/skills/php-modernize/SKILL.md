---
name: php-modernize
description: Modernise PHP code to PHP 8.x idioms — typed properties, enums, match expressions, named arguments, readonly, fibers, and strict_types. Flags deprecated patterns and PSR violations.
---

Review the provided PHP code and rewrite it using modern PHP 8.x features where appropriate. Apply changes in this order:

1. **Strict types** — add `declare(strict_types=1)` at the top if missing.
2. **Type declarations** — add parameter, return, and property types everywhere possible. Prefer union types (`int|string`) over docblocks where PHP supports them natively.
3. **Constructor promotion** — collapse `__construct` parameters + property declarations into promoted properties.
4. **Readonly properties** — mark properties that are only written in the constructor as `readonly`.
5. **Enums** — replace `const` groups representing a fixed set of values with a backed or pure enum.
6. **Match expressions** — replace `switch` statements that return or assign a value with `match`.
7. **Nullsafe operator** — replace `isset`/`!== null` chains with `?->`.
8. **Named arguments** — use named arguments where they improve clarity (especially for built-ins with many optional params).
9. **First-class callables** — replace `Closure::fromCallable('fn')` and `[$obj, 'method']` with `$obj->method(...)`.
10. **Fibers** — flag blocking I/O that could benefit from Fibers or async libraries (do not auto-convert; explain the trade-off).
11. **PSR-12** — fix formatting, braces, and naming to PSR-12.

For each change state: what changed, why, and any BC-break risk. Flag anything that requires a PHP version above 8.0 with its minimum version.

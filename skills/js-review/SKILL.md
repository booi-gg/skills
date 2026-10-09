---
name: js-review
description: JavaScript/TypeScript code review based on "JavaScript: The Good Parts" and "How JavaScript Works" plus architecture. Flags bad and awful parts, impure functions, architecture smells, poor naming, typos, dead code, and scope creep. Use when user says "booi review", "/booi-code-review", or wants a Good Parts review of a diff or files.
---

Review the diff (default: uncommitted changes; else the files or PR the user names). Report problems only.

Before reviewing, check CLAUDE.md and other project style guides for rules that conflict with these (e.g. "prefer `for...of`" vs no loops). List each conflict and ask the user which side to apply. Apply their choice for the rest of the review.

Principle: if a feature is sometimes useful and sometimes dangerous, and a better option exists, always use the better option.

## Rules

**Architecture**

- Single responsibility: one reason to change per function, file, module.
- Separation of concerns: UI, business logic, data access in separate layers. Flag logic in UI components, I/O in pure logic.
- Dependency direction: inner layers never import outer. Flag circular imports.
- Module boundaries: import through a module's public entry, not its internals.
- Colocation: group by feature, not by type. Things that change together live together.
- Duplication: same logic in two places → extract once.
- Coupling: flag shared mutable state, hidden dependencies, god files/functions.
- Folder structure mirrors the domain; flag misplaced files and pointless deep nesting.

**Bad parts**

- `==` / `!=` → `===` / `!==`.
- `with`, `eval`, `new Function`, string-arg `setTimeout`/`setInterval`.
- `continue` → restructure.
- `switch` fall-through.
- Block-less `if`/`for`/`while` → always braces.
- `++` / `--` → `+= 1` / `-= 1`.
- Bitwise operators outside true bit work.
- Function statements → function expressions.
- Typed wrappers (`new Boolean`/`Number`/`String`/`Object`/`Array`) → literals.
- `new` on custom constructors, `class`, `this`, `prototype` mutation → factory functions + closures.
- `void`.

**Awful parts**

- Globals: no implicit globals, no top-level mutable state.
- Scope: `const` default, `let` only when reassigned, never `var`.
- Semicolon insertion: always semicolons; `return` value on the same line; `{` at end of line.
- `typeof null === 'object'` → check `=== null`; arrays → `Array.isArray`.
- `parseInt` always with radix (or `Number()`).
- `+`: ensure both operands are numbers.
- Floating point: money and exact math in integers.
- `NaN`: `Number.isNaN` / `Number.isFinite`, never global `isNaN` or `=== NaN`.
- `arguments` → rest params.
- Falsy values: when `0`/`''`/`false` are valid, compare explicitly.
- `hasOwnProperty` → `Object.hasOwn`.
- User-keyed maps → `Map` or `Object.create(null)`.
- `for...in` → `Object.keys`/`entries`.
- `delete` on array elements → `splice`/`filter`.
- `sort()` without comparator → pass a comparator.
- Reserved words as identifiers or unquoted keys.

**How JavaScript Works**

- Loops: array methods (`map`/`filter`/`reduce`/`every`/`some`) or recursion → flag `for`/`while`.
- `undefined` only → flag `null`.
- `Object.freeze` for objects meant to be immutable.
- No getters/setters, generators, `Symbol` tricks.
- `switch` → object lookup or `if`/`else`.
- `try`/`catch` for real failures, not control flow.

**Purity**

- Same input → same output, no input mutation, no hidden state.
- Side effects (I/O, DOM, network) at the edges, isolated.

**Naming**

- Files/folders: kebab-case, named for what they hold. Flag `utils2`/`misc`/`helpers`.
- Functions: verb phrases (`getUser`, `isValid`). Booleans: `is`/`has`/`can`. UPPER_SNAKE only for true constants.
- Keys and variables say what the value is. Flag single letters (outside tiny lambdas), abbreviations, misleading names.
- Comments accurate and current.

**Hygiene**

- Typos in names, comments, strings.
- Unused files, folders, exports, vars, imports, commented-out code.
- Scope creep: changes unrelated to the stated task.

## Output

Grouped by file, one line per issue:

`⚠️ path:line — rule — problem`

Done when every rule is applied to every changed file. Nothing found → "clean".

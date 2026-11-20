---
version: 1.1.0
---

# Vite+: lint, format, tasks, and the editor

How the repo is linted, formatted, and how workspace tasks run. One tool: [Vite+](https://viteplus.dev) (`vp`), which bundles Oxlint, Oxfmt, and the Vite Task runner.

## The shape

| Piece | Choice |
| --- | --- |
| CLI | `vite-plus`, pinned exactly in the root `package.json`; the global `vp` delegates to it |
| Lint | Oxlint via `vp lint` |
| Format | Oxfmt via `vp fmt` |
| Rule set | Ultracite presets — `ultracite/oxlint/{core,react,tanstack}`, `ultracite/oxfmt` |
| Config | the `lint` and `fmt` blocks of the root `vite.config.ts`; no per-package lint/fmt config |
| Tasks | `vp run -r <task>` across workspace packages (replaces Turborepo) |
| Editor | Vite Plus Extension Pack (`VoidZero.vite-plus-extension-pack`), settings in `.vscode/settings.json` |
| Biome / Prettier / ESLint / Turbo | not used |

The root `vite.config.ts` holds only lint + format config. Each app keeps its own `vite.config.ts` for dev/build.

## Scripts

Root `package.json`:

| Script | Runs | Use |
| --- | --- | --- |
| `pnpm check` | `vp check` | format check + lint, no writes; fails on any error |
| `pnpm lint` | `vp lint` | lint only |
| `pnpm format` | `vp fmt` | format, writes |
| `pnpm build` / `test` / `typecheck` | `vp run -r <task>` | every package that defines the task, in workspace dependency order |
| `pnpm dev` | `vp run -r --parallel dev` | all dev servers at once |
| `pnpm preview` | build, then `vp run -r --parallel preview` |  |

Files you touched: `vp check path/to/a.tsx path/to/b.ts`. One package: `vp run --filter @app/main build`.

Do not run `vp lint --fix` (or `vp check --fix`) repo-wide. Some of Ultracite's oxlint "safe" fixes change behaviour (`Error` → `TypeError`, dropping a required `useRef(undefined)` argument). Format with `vp fmt`, fix lint by hand.

## Pre-commit hook

`.vite-hooks/pre-commit` runs on every commit; any failure aborts it.

1. `vp staged` — the `staged` block of the root `vite.config.ts`: `vp fmt` (writes, re-staged) then `vp lint` on the staged files. Lint errors fail; warnings don't.
2. `pnpm test` — every package's tests.

`pnpm install` installs the dispatcher (`prepare` → `vp config --no-agent`, sets `core.hooksPath`). Status: `vp hooks status`. Skip once: `VP_GIT_HOOKS=0 git commit …`. Opt out in a clone: `vp hooks disable`.

## `vite.config.ts`

- **Presets** — the three Ultracite oxlint presets are merged (plugins unioned, rules spread, overrides concatenated). `fmt` is `ultracite/oxfmt` as-is: 2 spaces, double quotes, semicolons, ES5 trailing commas, 80 cols, sorted imports and Tailwind classes.
- **Ignores** — Ultracite's shared list plus `routeTree.gen.ts` and `packages/ui/src/shadcn/**` (vendored shadcn output).
- **Repo style deltas (off)** — `func-style`, `react/function-component-definition` (we use `function` declarations), `import/consistent-type-specifier-style` (inline `type` specifiers), `prefer-named-capture-group`, `unicorn/switch-case-braces`.
- **Backlog (warn)** — rules Oxlint enforces that Biome did not. They warn so `vp check` passes. Fix the warnings for a rule, then delete it from the list.
- **Overrides** — inline JSX handlers allowed in `apps/main` (React Compiler); `no-await-in-loop` off in `apps/api`; `oxc/no-barrel-file` off for the intentional UI/feature indexes.
- **Boundary (error)** — `no-restricted-imports` in every package but `apps/api` and `packages/db`: no `@pkg/db` at all, and `@app/api` only as `import type` (`AppType` for `hc`). In `apps/main`, the analytics SDK is allowed only in its adapter file ([`guide-analytics.md`](./guide-analytics.md#lint-boundary)). In `apps/api`, payment provider SDKs are allowed only in `src/integrations/payment/` ([`guide-payments.md`](./guide-payments.md#lint-boundary)).

## Suppressing

Fix the code first. If there is no other way, suppress one rule with a reason:

```ts
// oxlint-disable-next-line no-await-in-loop -- each pass waits for the admin's choice.
/* oxlint-disable no-bitwise -- DER length octets are bit fields. */ // whole file
```

## Editor: VS Code

Install `VoidZero.vite-plus-extension-pack` (Oxc + Vitest). The workspace settings make Oxc the formatter for JS/TS/JSON/CSS, disable nested configs so the root `vite.config.ts` always wins, format whole files (`formatOnSaveMode: file` — Oxfmt can't format ranges), and run `source.fixAll.oxc` on an explicit save. `routeTree.gen.ts` is excluded from watch/search and opened read-only.

## Upgrading Vite+

Bump `vite-plus` in the root `package.json` to an exact version and `pnpm install`. The global `vp` picks up the project version automatically.

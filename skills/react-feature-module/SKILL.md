---
name: react-feature-module
description: Scaffold or restructure a React + TypeScript feature module into a layered architecture — entry point, injected service, per-variant config, JSON copy, API handlers, query/mutation/domain hooks, a facade hook and a pure render layer. Supports SPA and SSR. Use when the user wants to create a new feature module, build a multi-page/dialog-heavy feature, move an existing feature into this structure, or says "new module", "scaffold module", "module architecture".
---

# React Feature Module

Self-contained feature module. Copy lives in JSON, behaviour in config, infra in a service, logic in hooks, JSX in one render layer.

## Workflow

1. **Ask first** — never guess these:
   - Module name (PascalCase) and target folder
   - SPA or SSR → decides the service shape ([LAYERS.md §2](LAYERS.md#2-service--servicemodulets))
   - Variants the config is keyed by (or none)
   - Pages, large sections and dialogs → decides `pages/` and the `content/` split
   - Locales (default `en`), API operations, tracked events
   - New module, or restructuring an existing feature
2. **Find the house pieces.** Read one existing module that already follows this pattern, if any. Grep for the project's own template-string formatter, tracking handler, user-token hook, query-param hook, loader, error boundary and dialog/drawer. Use their real import paths and props. Missing → ask.
3. **Scaffold only what the module needs** (tree below). Code: [LAYERS.md](LAYERS.md). Copy: [CONTENT.md](CONTENT.md).
4. **Restructuring:** one layer per step, behaviour unchanged — strings → JSON, then handlers, then hooks, then render layer.
5. **Verify:** type-check changed files. Run `/booi-js-review` and `/ank-code-review` on the new files if installed, then [CHECKLIST.md](CHECKLIST.md) for module-specific rules.

## Tree

```
<Module>/
  index.tsx                  entry: resolve infra, init service, prefetch, guard
  service.<module>.ts        injected infra + active config + content
  config.<module>.ts         behaviour per variant, no copy        (skip: no variants)
  constants.<module>.ts      enums, base URLs, defaults
  types.<module>.ts          every type, incl. content types
  events.<module>.ts         tracking event names                  (skip: no tracking)
  use<Module>.ts             facade hook
  <Module>Content.tsx        render layer
  content/<locale>/*.json    copy, pure JSON
  handlers/                  request.<module>.ts + one thin wrapper per API call (skip: no API)
  hooks/queries/             useQuery wrappers
  hooks/mutations/           useMutation wrappers
  hooks/use<Domain>.ts       domain, selector and decorator hooks
  utils/                     pure functions, grouped by concept
  pages/                     one per page                          (skip: single page)
  components/  dialogs/  ui/
```

Small module → skip layers until the first thing needs them. Never pre-create empty folders.

## Core rules

- `content/` is what the user reads; `config` is what the module does. A string shown on screen never goes in config. Copywriter would change it → content. Developer → config.
- Imports point inward: render → facade → hooks → handlers → service → config/content/utils → types/constants. Nothing imports `index.tsx` or the render layer.
- `index.tsx` is the only place the service is initialised.
- The service is the only runtime importer of content JSON and `MODULE_CONFIG`.
- Handlers and utils: no React, no service. Handlers take the token as a param and throw; TanStack Query owns error state.
- Every file earns its place: if deleting it just moves its code into callers unchanged, merge it. Utils group by concept, not one function per file.
- `index.tsx` starts every query the page needs, in parallel. Children never start a fetch `index.tsx` could have started.
- Components never fetch, never track, never hold business logic.
- One `activeDialog` union for all modals — never `isXOpen` booleans. Heavy dialogs load with `React.lazy`.
- Conditional render: `cond ? <A /> : null`, or ensure `cond` is boolean. `count && <A />` renders `0`.
- Function expressions only; destructure params in the body, not the signature; `undefined`, not `null`; `Object.freeze` static data; no getters, no classes.
- No barrels. Import files by direct path. A barrel is a second interface to keep in sync and defeats tree-shaking.
- File casing follows the repo. No convention → components PascalCase, everything else as shown above.

## Gotchas

- **SPA:** the service is a module-level singleton — one mounted instance per module. Two instances at once with different variants → use the SSR shape.
- **SPA:** `init()` runs during render on purpose so children always read current values. Keep it synchronous, idempotent and free of I/O.
- **SSR:** never use the module-level singleton. Module state is shared across requests, so one user's token leaks into another's render. Create the service per render and pass it through context.

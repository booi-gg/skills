---
version: 1.0.1
---

# Module Guide

What a module is, where its edges are, and how modules talk to each other.

Companion docs: [`guide-structure.txt`](./guide-structure.txt) for the repo tree, [`guide-functions.md`](./guide-functions.md) for what goes inside a module.

---

## What a module is

A module is one **domain noun** the product actually has — `roll`, `pool`, `payment`, `camera` — and it owns that noun end to end: its network calls, its cache, its UI, its types.

They live in `src/features/`. One folder per module, no nesting.

> **Decision:** `features/`, not `mods/`. `src/mods/` is an empty scaffold; delete it. Everything already lives in `features/`, `guide-structure.txt` documents it, and a rename buys nothing. `<module>/` in [`guide-functions.md`](./guide-functions.md) means `src/features/<name>/`.

**The test — all three must hold:**

1. **A name from the product, not the framework.** `roll`, `pool`, `join`. If the best name you have is `utils`, `common`, `helpers`, or `shared`, it isn't a module.
2. **It owns data.** It fetches, caches, or persists something, or it holds a decision the rest of the app reads. Pure presentation is not a module.
3. **You could delete it.** Remove the folder and its routes, and the rest of the app compiles minus that one product capability. If deleting it breaks four unrelated screens, the boundary is wrong.

**What is not a module, and where it goes instead:**

| Thing | Goes to |
| --- | --- |
| App chrome used by every screen — navbar, tabs, layout | `src/components/layout/` |
| UI shared across modules with no domain knowledge | `src/components/shared/` |
| Reusable primitive independent of this app | `packages/ui/` |
| Framework or infrastructure — query client, api fetch, auth client, upload | `src/lib/` |
| Server implementation | `apps/api` |
| One-off page with no data of its own | a route file |

## Anatomy

Add a subdirectory only when it holds real code. An empty folder is a promise, and promises rot.

```
features/roll/
  index.ts          the module's entire public surface
  handlers/         network calls            create-roll.ts
  hooks/
    queries/        reads                    use-roll.ts
    mutations/      writes                   use-create-roll.ts
    keys.ts         query keys for this module
    use-*.ts        non-server hooks
  components/       module-local UI          film-stock-card.tsx
  views/            states of a screen       login-view.tsx
  utils/            pure helpers
  content/
    en/             all visible copy as JSON   onboarding-view.json
  data/
    copy.ts         loads content/en/*.json, fills config {placeholders}
  assets/
  types.ts          the module's domain types
```

`views/` holds the states a screen in `src/screens/` switches between without changing the path. The screen picks one from a `view` search param: `/auth?view=login` and `/auth?view=signup` are one route, one screen, and two views. The value can be a name (`login`) or a number (`1`). `components/` is everything smaller. If a component is used by exactly one view, it can sit next to it — move it to `components/` on the second consumer, same promotion rule as everywhere else.

## Copy lives in JSON

Same rules as pages ([`guide-pages.md`](./guide-pages.md#copy-lives-in-json)), scoped to the module.

- **All visible text is in `content/<locale>/*.json`**: headings, body, labels, placeholders, hints, button text, error messages. Components hold no literal copy.
- **One JSON file per component that carries copy**, named like the component: `onboarding-view.json` ↔ `views/onboarding-view.tsx`.
- **`data/copy.ts` is the only importer of the JSON.** It fills config placeholders (`{rootHost}`, `{minLength}`) once with `fillDeep` from `#/lib/copy`, and exports one object per file (`onboardingView`, `onboardingPerks`). Components import from `data/copy`, never from `content/`.
- **Runtime values are `{placeholders}` too** (`{name}`, `{count}`), left unfilled by `copy.ts` and filled at render with `fill` from `#/lib/copy`. No string concatenation or `.replace` in components.
- **Match the project voice.** See [`guide-copy.md`](./guide-copy.md).
- **Only `en` exists today.** A second locale (`jp`) is a sibling folder; choosing it happens in `copy.ts`, not in components.

`keys.ts` holds **this module's** query keys and nothing else. A module never defines keys for another module's data.

## The public surface

`index.ts` is the module's API. Everything else is private.

```ts
// features/roll/index.ts
export * from "./components";
export * from "./hooks/queries";
export * from "./hooks/mutations";
export type { Roll, RollDraft } from "./types";
```

```ts
import { FrameWindow } from "@/features/hub/components/frame-window";
// ❌ reaching past the barrel
import { rollKeys } from "@/features/hub/queries";
// ✅ from another module or a route
import { useRoll, RollDetail } from "@/features/roll";
```

**Inside** a module, import by relative path (`./handlers`, `../types`) — the barrel is for outsiders. Importing your own module through `@/features/x` creates a cycle through the barrel and defeats the point.

Export the smallest thing that works: hooks, views, the components others genuinely render, the types they hold. Handlers stay private — another module needing your network call is a sign it needs your _hook_, or that the call belongs somewhere else.

## Dependencies

```
routes  →  features  →  components / lib / packages
```

- **Routes** import from modules. Route files stay thin: pick the screen, pass params, render.
- **Modules** import from `components/`, `lib/`, `packages/*`, and — carefully — other modules.
- **`lib/` and `components/` never import a module.** They sit below the domain. This is the rule that keeps the graph acyclic.

**Module → module** is allowed, through the barrel, in one direction. Two rules:

1. **No cycles.** If `a` imports `b`, then `b` must not import `a` — directly or through a chain.
2. **When two modules need each other, the shared thing moves down.** Not sideways. It goes to `lib/` if it is infrastructure, `components/` if it is UI, or a third smaller module if it is genuinely its own domain.

The current graph has real cycles — see _Known drift_ — so this is a rule to converge on, not a description of today.

## Lifecycle

**Creating one.** Start with `index.ts` and one folder. Not the full tree. A module that begins with seven empty directories tells the next reader nothing about what it does.

**Growing.** Add folders as code arrives. When `components/` passes roughly a dozen files, that is a signal the module covers two nouns — look for the seam before adding the thirteenth.

**Promoting.** Module-local until a second consumer appears. Then it moves down a level: to `components/shared/` if it is UI, `lib/` if it is infrastructure, `packages/` only when a _different app_ needs it. Never promote in anticipation.

**Retiring.** Delete the folder and its routes. If that doesn't compile cleanly, the module was leaking — and the compiler is telling you exactly where.

## New module checklist

- [ ] The name is a product noun, and the three tests above pass
- [ ] `src/features/<name>/` with `index.ts` and only the folders that hold code
- [ ] Route files delegate; no domain logic in `src/routes/`
- [ ] Network calls in `handlers/`, cache in `hooks/`, per [`guide-functions.md`](./guide-functions.md)
- [ ] Query keys in this module's `hooks/keys.ts`
- [ ] Visible text in `content/en/*.json`, loaded through `data/copy.ts`
- [ ] A dashboard view's `<main>` and its loading skeleton use `cn(pageWidth, …)` from `@pkg/ui`, so content lines up with the nav
- [ ] Every cross-module import goes through the other module's `index.ts`
- [ ] No import from `lib/` or `components/` back into a feature
- [ ] Added to the tree in `guide-structure.txt`


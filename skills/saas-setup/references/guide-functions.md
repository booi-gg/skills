# Function Guide

How functions are named and where they live. `fn` = function.

Two rules carry the rest:

1. **Pure by default.** Input in, output out, nothing touched outside the arguments. Reach for a side effect only when the effect _is_ the job.
2. **One layer per concern.** A handler knows the network. A hook knows the cache. A component knows neither.

---

## Layers

```
component  →  hook  →  handler  →  network
```

Imports go one direction only. A handler never imports a hook. A hook never renders. A component never calls `fetch`, never builds a URL, never touches a query key.

| Layer | Knows about | Never touches |
| --- | --- | --- |
| `handlers/` | URL, method, body, response type | React, cache, toasts, routing |
| `hooks/` | query keys, `staleTime`, `enabled`, invalidation | URLs, request bodies |
| components | props, local state, rendering | both of the above |

When a rule below is ambiguous, this table decides it.

---

## 1. Handlers — the network layer

A fn that calls an API URL directly is a **handler**. Name it for the verb it performs. The folder already says "handler"; the name doesn't repeat it.

```
createRoll, getRollById, getMyRolls, archiveRoll, deletePost
```

- Location: `<module>/handlers/`
- App-wide: `src/handlers/`
- One handler per file, kebab-case, re-exported from `handlers/index.ts`
- Returns parsed data or throws. No swallowed errors, no UI concerns.

```
features/roll/handlers/
  create-roll.ts        → createRoll
  get-roll-by-id.ts     → getRollById
  archive-roll.ts       → archiveRoll
  index.ts              → export * from "./create-roll"  …
```

Read/list handlers start with `get`. Writes start with the verb that describes the change — `create`, `update`, `archive`, `reveal`, `delete`. Never `handle`; that prefix belongs to nothing in this codebase.

## 2. Hooks — the cache layer

Most handlers have a TanStack Query counterpart that wraps them.

| Kind      | Name               | Example                               |
| --------- | ------------------ | ------------------------------------- |
| Read one  | `use<Thing>`       | `useRoll(id)`, `usePoolAward()`       |
| Read many | `use<Things>`      | `useMyRolls()`, `useParticipants(id)` |
| Write     | `use<Verb><Thing>` | `useCreateRoll()`, `useArchiveRoll()` |

- Reads: `<module>/hooks/queries/`
- Writes: `<module>/hooks/mutations/`
- App-wide: `src/hooks/queries/`, `src/hooks/mutations/`
- One hook per file, kebab-case: `use-create-roll.ts`

No `Query` or `Mutation` suffix — the folder and the shape of the return value already say it.

```ts
export function useRoll(id: string) {
  return useQuery({
    queryKey: rollKeys.byId(id),
    queryFn: () => getRollById(id),
    enabled: !!id,
  });
}
```

**Query keys** live in `<module>/hooks/keys.ts` as one object per module, so invalidation never guesses at a string array:

```ts
export const rollKeys = {
  all: ["roll"] as const,
  mine: () => [...rollKeys.all, "mine"] as const,
  byId: (id: string) => [...rollKeys.all, id] as const,
};
```

Hooks that hold no server state — `useCamera`, `useScrollShrink` — are not query hooks. They go in `<module>/hooks/`, alongside the two folders, not inside them.

## 3. Utils — pure helpers

No network, no React, no module state.

- Name: describe what it does, no prefix. `formatFilmDate`, `slugifyTitle`, `centsToDisplay`
- Location: `<module>/utils/`
- Shared: `src/lib/` — a focused file per concern, not a growing `utils.ts` drawer

If it needs a hook, a fetch, or component state, it isn't a util. Move it to the layer that owns that.

## 4. Inline functions

Defined inside a component.

**Events** — prefix `on`, named for what happened, not what it does about it.

```
onSubmit, onFilmSelect, onRetryClick
```

This holds for both directions: the prop a component exposes and the fn passed into it share the name. `<Button onClick={onRetryClick} />`.

**Everything else** — a plain verb. `buildPricing`, `nextSlot`, `resetDraft`. Once a second caller appears, lift it into `utils/`.

There is no `do` prefix. "Is this a side effect?" has no crisp answer, so it can't be a naming rule.

## 5. Booleans

Predicates and boolean values read as a question the name answers.

```
isRevealed, isPending, hasSlots, canClaim, shouldRetry
```

Functions returning a boolean use the same prefixes: `canClaimPool(award)`.

---

## Files and folders

- **kebab-case for every file.** `get-roll-by-id.ts`, `use-create-roll.ts`, `film-stock-card.tsx`. The export inside is camelCase or PascalCase as usual.
- **Module-local first.** Promote to `src/` on the _second_ consumer, not in anticipation of one.
- **Barrels only at folder boundaries** — `handlers/index.ts`, `components/index.ts`. Not a barrel per file.

```
<module>/
  handlers/       network calls          create-roll.ts
  hooks/
    queries/      reads                  use-roll.ts
    mutations/    writes                 use-create-roll.ts
    keys.ts       query keys
    use-*.ts      non-server hooks
  components/     module-local UI
  views/          states of a screen (?view=)
  utils/          pure helpers
  content/en/     copy as JSON
  data/copy.ts    loads and fills content/
  types.ts
  assets/
```

---

## Quick reference

| Kind        | Name                        | Lives in                      |
| ----------- | --------------------------- | ----------------------------- |
| API call    | `createRoll`, `getRollById` | `<module>/handlers/`          |
| Read hook   | `useRoll`, `useMyRolls`     | `<module>/hooks/queries/`     |
| Write hook  | `useCreateRoll`             | `<module>/hooks/mutations/`   |
| Other hook  | `useCamera`                 | `<module>/hooks/`             |
| Pure helper | `formatFilmDate`            | `<module>/utils/`, `src/lib/` |
| Event       | `onFilmSelect`              | inline                        |
| Boolean     | `isRevealed`, `canClaim`    | anywhere                      |

---

## Known drift

Current code predates this guide. Fix as files are touched — not in one sweep.

- `features/roll/handlers/` still exports `handleCreateRoll`, `handleUpdateRoll`, `handlePayRoll`. Campaign the prefix. The rest of the folder (`getRollById`, `getMyRolls`, `archiveRoll`) already matches.
- Query hooks sit in `features/pool/queries.ts` and `features/hub/queries.ts`, with keys inline. Split into `hooks/queries/` + `hooks/keys.ts`. The hook _names_ (`usePoolAward`, `useMyRolls`, `useCreateDownloadSession`) already match — only the location moves.
- Loose hooks at feature root: `features/roll/use-welcome-roll.ts`, `features/camera/use-camera-capture.ts`, `features/pwa/use-install.ts` → `<module>/hooks/`.
- `src/hooks/*.ts` uses camelCase filenames (`useSession.ts`, `useUploadSync.ts`) → kebab-case.

## Open

- **`mods/` vs `features/`.** `src/mods/` is an empty scaffold beside a populated `src/features/`. `<module>/` in this guide means whichever wins. Settle it before the next module.

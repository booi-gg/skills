---
name: react-layered-architecture
description: Build, review or refactor React + TypeScript code into three layers — a React-free service layer behind a typed contract (swappable per platform, e.g. Electron vs Web), a hooks layer that syncs services into React state behind a stable signature, and a purely presentational UI layer. Use when the user writes a service, hook or component that touches platform or business logic, asks for "layered architecture", "thinking in React", "service layer", "platform adapter", "container/presentational", "make this work on web and Electron", or wants code reviewed or untangled against these layers.
---

# React Layered Architecture

React renders UI. Nothing else. Data, business logic and platform integration live in layers React consumes, not owns.

```
UI        props in, JSX out. No services, no business logic.
  ↓
Hooks     bridge services → React. Only layer that syncs app state into React. Stable signature.
  ↓
Service   plain TS, no React. Typed contract, one implementation per platform.
```

**Invariant:** while a layer's contract (type / hook signature) holds, nothing above it changes. Swap Electron for Web, or Zustand for an API, without touching a component.

## Pick the mode

- **Build** — new service, hook or component. Follow [LAYERS.md](LAYERS.md).
- **Review** — check files or a diff. Run [CHECKLIST.md](CHECKLIST.md), report each hit as `file:line — rule broken`.
- **Refactor** — untangle an existing component. Workflow below.

## Build workflow

1. **Ask first** — never guess:
   - Which platforms (Electron, Web, both, tests) and where each one gets its data
   - What the hooks must expose (this is the contract — fix it before writing code)
   - Does the repo already use Zustand / TanStack Query / a store? Reuse it
2. **Find house pieces.** Grep for the existing HTTP client, store, and entry points (`app.web.tsx`, `app.electron.tsx` or equivalent). Use real paths. Missing → ask.
3. **Contract first.** Write the service type before any implementation.
4. **Implement per platform**, then the facade, then wire it in each entry point.
5. **Hooks**, then **container → presentational** components.
6. **Verify:** type-check changed files. Run `/booi-code-review` if installed, then [CHECKLIST.md](CHECKLIST.md).

Building a whole feature module (config, content JSON, handlers, queries)? Use `/react-feature-module` for the file layout; these layers map onto its service, hooks and render layer.

## Refactor workflow

One layer per step. Behaviour unchanged after every step.

1. Move platform and business logic out of the component into a service behind a contract.
2. Replace direct store / API / `useEffect` subscriptions with a hook that reads the service.
3. Split the component: container calls hooks, presentational takes props.
4. Rename business-aware props to visual ones (`isHistoryView` → `isIndented`).

## Core rules

- **Service:** factory functions returning a frozen object, deps injected as params. No React, no setState, no DOM events. Runs in browser, Electron, Node and tests.
- **Contract first.** Every platform implements the same `T<Name>Service` type. Hooks import only the facade, never an implementation.
- **Subscribe shape:** `subscribe(listener) → unsubscribe` + a synchronous `get…()` snapshot. That plugs straight into `useSyncExternalStore`.
- **Wiring lives in the entry point only.** Switching platform = changing the one `init(...)` call.
- **Hook signature never changes** when the service behind it is swapped.
- Hooks: call services, hold loading/error state, return a stable shape. No platform details (eStore, axios, `window.electron`), no business logic.
- UI: props in, JSX out. Hooks only in containers. Local UI state (open, hover, focus) is fine — app state is not.
- Props describe how it looks, not why: `isIndented`, not `isHistoryView`.
- Small composable pieces over one component with ten flags.
- Function expressions; destructure params in the body; `undefined`, not `null`; no classes; no barrels.

## Gotchas

- **Snapshot must be referentially stable.** `getUser()` returning a fresh object every call makes `useSyncExternalStore` loop forever. Cache it; replace only on real change.
- **Never tear services down in a React effect.** StrictMode mounts → unmounts → mounts in dev, so `useEffect(() => () => service.destroy(), [])` kills the service and nothing re-inits it. Start work on the first subscriber, stop on the last.
- **Hydrate before render.** A web snapshot that starts `undefined` and fills after the first poll flashes the logged-out UI. Fetch the initial value in the entry point before `render`.
- **Notify only on change.** A poll that fires listeners every tick re-renders every subscriber for nothing.
- **Every method a hook calls is in the contract.** If a hook needs `logout`, `logout` goes in the type, every implementation and the facade.
- **SSR:** a module-level facade is shared across requests — one user's data leaks into another's render. Create the service per request and pass it through context.

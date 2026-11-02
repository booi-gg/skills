# Checklist

Run `/booi-code-review` first if installed. This list covers what it can't know about these layers.

Report each hit as `file:line — rule broken`. Problems only.

## Service

- Imports React, calls setState, dispatches DOM events or reads `window` outside a platform implementation
- Class instead of a factory function returning a frozen object
- Dependency imported directly instead of injected (HTTP client, store, timers config)
- Implementation doesn't satisfy the contract type, or adds public methods the contract lacks
- `get…()` snapshot returns a new object each call (breaks `useSyncExternalStore`)
- Listeners notified when nothing changed
- Interval, socket or store watcher started at creation and never stopped, or not tied to subscriber count
- Promise rejection unhandled inside a poll or subscription callback
- Callback array typed for one payload but called with another

## Facade and wiring

- Hook or component importing a platform implementation instead of the facade
- `init(...)` called anywhere but an entry point, or inside a component
- Facade used before init without a clear error (`impl!`)
- `destroy()` in a `useEffect` cleanup (StrictMode kills the service)
- Web snapshot starts empty with no hydration before render (logged-out flash)
- SSR: module-level facade or any module-level mutable state

## Hooks

- Business logic in the hook body instead of the service
- Platform detail in the hook: `eStore`, axios, `fetch`, `window.electron`, IPC
- Subscribes to a store or API directly instead of through the service
- `useState` + `useEffect` subscription where `useSyncExternalStore` fits
- Subscription without cleanup
- Signature changed when only the backing service changed
- Calls a service method missing from the contract
- Manually updates another store after a service call the service already notifies about
- Async action with no error state or catch

## UI

- Imports a service
- Presentational component calls an app hook (only containers do)
- Business logic, fetching or app state in a presentational component
- Business-aware prop names (`isHistoryView`, `isCheckoutPage`) instead of visual ones (`isIndented`, `isCompact`)
- One large component driven by many flags instead of composable pieces
- Promise passed straight to `onClick`

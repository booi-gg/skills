# React

Rules for the **React** axis, condensed from Vercel's React best practices. Ordered by impact — report the impact level with each finding. Skip the **Server** section unless the app renders on the server (SSR, Next.js, RSC).

## Waterfalls — CRITICAL

- Independent awaits run one after another → `Promise.all`.
- `await` before a cheap sync check that could exit early → check first.
- `await` at the top when only one branch uses it → move it into that branch.
- Parent renders, then child starts its own fetch → start every page query at the entry point, in parallel.
- Whole page waits on slow data → `Suspense` boundary around the slow part.

## Bundle — CRITICAL

- Import through a barrel file → import the file directly.
- Heavy component or dialog imported statically but shown rarely → `React.lazy` / dynamic import.
- Module only used behind a feature flag or user action → load it on activation.
- Analytics, chat, logging SDKs loaded before first paint → defer until after hydration / idle.
- Dynamic import path built from a variable → keep paths statically analysable.

## Server — HIGH (SSR only)

- Module-level mutable state holding per-request data (user, token) → leaks across requests; create per request.
- Server action without auth check → authenticate like an API route.
- Repeated identical fetch within one request → `React.cache`.
- Large objects passed to client components → pass only the fields used.
- Sequential fetches in nested server components → restructure to fetch in parallel.

## Client data — MEDIUM-HIGH

- Same request fired by several components → share one query (TanStack Query / SWR) for deduplication.
- Global `addEventListener` per component instance → one shared listener.
- Scroll/touch listeners without `{ passive: true }`.
- `localStorage` data without a version or schema → version it, store the minimum.

## Re-renders — MEDIUM

- State derived in `useEffect` + `setState` → compute during render.
- Interaction logic in an effect → move it into the event handler.
- Subscribing to state only read inside a callback → read it in the callback.
- Subscribing to a raw value when only a boolean is needed → derive and expose the boolean.
- `setState(value)` depending on current state → functional `setState(prev => …)`.
- Expensive initial value passed to `useState` → lazy initialiser `useState(() => …)`.
- Object/array/function in effect deps → depend on primitives.
- `useMemo` around a cheap primitive expression → drop it.
- Non-primitive default prop (`= []`, `= {}`) on a memoised component → hoist to a constant.
- Component defined inside another component → remounts every render; move it out.
- One hook mixing unrelated state with different deps → split it.
- Frequently changing value only used in handlers → `useRef`.
- Non-urgent update blocking input → `startTransition` / `useDeferredValue`.

## Rendering — MEDIUM

- `count && <X />` where `count` can be `0` → renders `0`; use a ternary or a boolean.
- Static JSX rebuilt each render → hoist it outside the component.
- Long lists fully rendered → `content-visibility: auto` or virtualise.
- Manual loading booleans around transitions → `useTransition`'s `isPending`.
- Animating an SVG element directly → animate a wrapping `div`.
- Hydration mismatch silenced broadly → suppress only the known mismatch.

## JS performance — LOW-MEDIUM

- Regex created inside a render or loop → hoist to module level.
- Repeated `.find` / `.includes` on the same array in a loop → build a `Map` / `Set` once.
- Several `.filter().map()` passes over one array → one pass, or `flatMap`.
- `sort()` to get min/max → single loop.
- `sort()` mutating props or state → `toSorted()`.
- Repeated `localStorage` reads → cache the value.
- Expensive comparison before a cheap length check → check length first.
- `Intl.*Format` constructed per call → create once and reuse.

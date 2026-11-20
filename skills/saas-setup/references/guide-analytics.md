# Analytics, errors and logs

The web app sends product events, caught errors and log lines through its own small module, `apps/main/src/lib/analytics/`. One adapter file forwards them to the vendor (PostHog today). App code never names the vendor, so swapping vendors means writing one new adapter. Read this before adding an event, adding a vendor call, or changing vendor.

## The shape

```
component / hook  →  track · identify · resetAnalytics · captureError · logger  →  AnalyticsProvider · LogSink  →  <vendor>-adapter.ts  →  vendor SDK
```

| File | Holds | Knows about |
| --- | --- | --- |
| `packages/shared/src/analytics.ts` | `AnalyticsEvents` (every event name and its properties), `AnalyticsUserTraits` | nothing |
| `lib/analytics/analytics.ts` | `track`, `identify`, `resetAnalytics`, `captureError`, the `AnalyticsProvider` interface, `setAnalyticsProvider` | the catalog |
| `lib/analytics/logger.ts` | `logger.debug/info/warn/error`, the `LogSink` interface, `setLogSink` | nothing |
| `lib/analytics/posthog-adapter.ts` | `startPostHog()`: starts the SDK, registers a provider and a sink | the vendor SDK, `env.ts` |
| `routes/__root.tsx` | one `startPostHog()` call at module load, plus `RestoreIdentity` | the adapter's start function only |
| `router.tsx` | `defaultOnCatch` → `captureError` | `analytics.ts` |

**The rule:** only the adapter imports the vendor SDK. A lint rule enforces it (see [Lint boundary](#lint-boundary)).

## Event catalog

The event names and their properties are the analytics API. They live in `packages/shared` so the api Worker can send the same names later.

```ts
// packages/shared/src/analytics.ts — export it as "./analytics" in package.json
export interface AnalyticsEvents {
  project_created: { initial_reviewer_count: number };
  project_deleted: undefined;            // no properties
  review_invites_sent: { sent_count: number; target: "image" | "project" };
}
export type AnalyticsEventName = keyof AnalyticsEvents;
export interface AnalyticsUserTraits { email: string; name: string }
```

- **Names:** snake case, `<thing>_<past-tense verb>`.
- **Properties:** snake case. Use counts and enums. Never put ids, emails or free text in properties: `identify` is where a person is attached.
- **Renames:** don't. A rename starts a new series in the vendor's dashboards. Add a new name and stop sending the old one.
- **Shape:** each property type is an inline object literal, not a named interface, so it fits the provider's `EventProperties` union.

## The module

```ts
// lib/analytics/analytics.ts
export type EventProperties = Exclude<AnalyticsEvents[AnalyticsEventName], undefined>;

export interface AnalyticsProvider {
  captureError: (error: unknown, context?: Record<string, unknown>) => void;
  identify: (userId: string, traits: AnalyticsUserTraits) => void;
  reset: () => void;
  track: (event: AnalyticsEventName, properties?: EventProperties) => void;
}

const drop = (): void => {
  // Analytics is off: nothing to send.
};
let provider: AnalyticsProvider = { captureError: drop, identify: drop, reset: drop, track: drop };

export function setAnalyticsProvider(next: AnalyticsProvider): void { provider = next; }

/** Events without properties take only their name. */
type EventArgs<E extends AnalyticsEventName> =
  AnalyticsEvents[E] extends undefined ? [] : [properties: AnalyticsEvents[E]];

export function track<E extends AnalyticsEventName>(event: E, ...[properties]: EventArgs<E>): void {
  provider.track(event, properties);
}
// identify, resetAnalytics, captureError: one-line forwards to `provider` in the same way
```

- **Plain functions, not a hook.** They work in components, hooks, handlers and plain modules, and they never go in a hook's dependency array.
- **The off provider is the default.** Calls made before the vendor starts, on the server, or with no keys are dropped, never thrown.
- **The no-op has a comment body.** `() => undefined` fails `unicorn/no-useless-undefined`, and an empty body fails `no-empty-function`.
- **`EventArgs` makes properties compile-checked:** `track("project_deleted")` takes no second argument, and `track("project_created", {})` is a type error.

`logger.ts` follows the same pattern with a `LogSink { write(level, message, attributes) }`, where `LogAttributes` is `Record<string, string | number | boolean>`. Logs have their own sink because they often move to a different tool than product events.

## Vendor adapter

```ts
// lib/analytics/posthog-adapter.ts
import { posthog } from "posthog-js"; // named import: the default one fails import/no-named-as-default

const posthogAnalytics: AnalyticsProvider = {
  captureError: (error, context) => { posthog.captureException(error, context); },
  identify: (userId, traits) => { posthog.identify(userId, traits); },
  reset: () => { posthog.reset(); },
  track: (event, properties) => { posthog.capture(event, properties); },
};
const posthogLogs: LogSink = {
  write: (level, message, attributes) => { posthog.logger[level](message, attributes); },
};

let started = false;
export function startPostHog(): void {
  if (started || typeof window === "undefined") {
    return;
  }
  started = true;
  const token = env.CLIENT_POSTHOG_PROJECT_TOKEN;
  const host = env.CLIENT_POSTHOG_HOST;
  if (token === undefined || host === undefined) {
    // In dev, console.error which variable is missing. Then stay off.
    return;
  }
  posthog.init(token, {
    api_host: host,                        // e.g. https://us.i.posthog.com
    ui_host: host.replace(".i.", "."),     // the toolbar's app host
    capture_exceptions: true,              // unhandled errors and rejections
    defaults: "2025-05-24",
    debug: import.meta.env.DEV,
    logs: { environment: import.meta.env.MODE, serviceName: "<app-name>-web" },
  });
  setAnalyticsProvider(posthogAnalytics);
  setLogSink(posthogLogs);
}
```

- **Dependency:** add `posthog-js` to `apps/main` through the pnpm catalog. `@posthog/react` isn't needed: nothing outside the adapter uses its hooks.
- **Env:** `CLIENT_POSTHOG_PROJECT_TOKEN` and `CLIENT_POSTHOG_HOST` are optional in `env.ts` (`z.string().trim().min(1).optional().catch(undefined)`), so a blank value means "off" rather than a crash. The project token is a public key, so the `CLIENT_` prefix is correct. Put real values in `.env.production` and placeholders in `.env.example`. Leave them out of the local `.env` unless you want dev events in the production project.

## Startup, identity and errors

- **Start at module load.** Call `startPostHog()` at the top level of `routes/__root.tsx`, not inside an effect. React runs child effects before parent effects, so a provider started in a root effect misses whatever children track or identify on their first render. That's what `<PostHogProvider apiKey>` does. The function's own guards make the top-level call safe during SSR and HMR.
- **Identity:**
  - After a successful sign-in, call `identify(user.id, { email, name })` with the session user.
  - `RestoreIdentity` in the root shell does the same on every page load: an effect that reads the session and calls `identify` if someone is signed in.
  - After a successful sign-out, call `resetAnalytics()`, so later events belong to a new anonymous visitor.
- **Errors:**
  - The vendor's autocapture (`capture_exceptions`) gets unhandled errors and promise rejections.
  - Render errors never reach it, because TanStack Router's catch boundaries catch them first and show the route's error screen. Report them from the router instead:

```ts
// router.tsx
createRouter({
  defaultOnCatch: (error, errorInfo) => {
    captureError(error, { component_stack: errorInfo.componentStack });
  },
  // …
});
```

  A vendor error boundary such as `PostHogErrorBoundary`, wrapped around the router's output, adds nothing: the router's boundaries sit inside it and catch everything first.

## Lint boundary

Overrides on the same file replace a rule's options rather than merging them. So the adapter's override has to repeat the web package's other import bans. Keep them in shared constants in the root `vite.config.ts`:

```ts
const webImportRules = [/* the @app/api type-only and @pkg/db bans from guide-lint.md */];
const analyticsVendorRule = {
  group: ["posthog-js", "posthog-js/*", "@posthog/*"],
  message: "Use track/identify from lib/analytics/analytics or logger from lib/analytics/logger. Only the vendor adapter imports the SDK.",
};

// lint.overrides
{ files: ["apps/main/**"],
  rules: { "no-restricted-imports": ["error", { patterns: [...webImportRules, analyticsVendorRule] }] } },
{ files: ["apps/main/src/lib/analytics/posthog-adapter.ts"],
  rules: { "no-restricted-imports": ["error", { patterns: webImportRules }] } },
```

## Adding an event

1. Add the name and its properties to `AnalyticsEvents` in `packages/shared/src/analytics.ts`.
2. Call `track("<name>", { … })` where the action has succeeded: after the `await`, not before it.
3. Run the check. Done when it passes and the call compiles without a cast.

## Changing vendor

1. Add the new SDK to `apps/main`. Write `lib/analytics/<vendor>-adapter.ts`, implementing `AnalyticsProvider` (and `LogSink` if the vendor takes logs) with a `start<Vendor>()` built like `startPostHog()`.
2. Replace the `startPostHog()` call in `__root.tsx`.
3. Point the lint rule at the new SDK's packages and the new adapter file. Then remove `posthog-js`, its env vars and the old adapter.
4. Done when the check passes and nothing outside the adapter mentions either vendor.

To run two vendors side by side during a migration, register a provider whose methods call both adapters' methods. Remove it once the new vendor's data is trusted.

## Verifying without real traffic

Run the dev server with fake keys, so nothing reaches the real project:

```sh
CLIENT_POSTHOG_HOST=http://127.0.0.1:5199 CLIENT_POSTHOG_PROJECT_TOKEN=phc_localprobe pnpm --filter @app/main dev
```

Open the app and watch the network panel. The requests fail with connection refused, which is expected: the requests themselves are the evidence. A `POST /e/` for the pageview shows the SDK started. With `debug` on, the console logs `[PostHog.js] send "<event>"` for each `track` call.

## Why it's built this way

| Decision | Why |
| --- | --- |
| Our own interface, not the vendor's API spread through the app | A vendor swap is one new file instead of editing every call site. Tests and dev run on the off provider. |
| The catalog in `packages/shared` | One list of names for both Workers. Typos and wrong properties become type errors instead of dead series in a dashboard. |
| Only track, identify, reset and errors in the interface | Every vendor has these. Feature flags, session replay and surveys differ per vendor: each gets its own small interface when it's first used, not a field squeezed into this one. |
| Logs as a separate sink | Product events and logs often end up in different tools. Splitting them later would mean touching every log call. |
| Plain module state, not React context | Calls work outside components (upload queues, handlers), and hooks don't re-run when the client changes. |

## Checklist

- [ ] Every event name and its properties are in `AnalyticsEvents`; no `track` call uses a cast.
- [ ] Only `<vendor>-adapter.ts` imports the SDK; the lint rule fails on any other import.
- [ ] The vendor starts at module load in `__root.tsx`, does nothing on the server, and stays off with a dev warning when either env var is missing.
- [ ] Sign-in calls `identify`, `RestoreIdentity` re-identifies on load, and sign-out calls `resetAnalytics`.
- [ ] `defaultOnCatch` in `router.tsx` reports render errors through `captureError`.
- [ ] Log lines go through `logger`, never the vendor's logger.
- [ ] `.env.example` lists both `CLIENT_*` vars with placeholders.

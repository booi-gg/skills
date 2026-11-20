---
version: 1.1.0
---

# Split Workers: web + api

How to run a Cloudflare app as two independent Workers — a TanStack Start **web** Worker that only serves the web app, and a Hono **api** Worker that owns every API call, all data, and auth.

Placeholders used throughout:

| Placeholder       | Meaning                               |
| ----------------- | ------------------------------------- |
| `example.app`     | web origin — TanStack Start           |
| `api.example.app` | api origin — Hono + Better Auth       |
| `my-app-web`      | web Worker name                       |
| `my-app-api`      | api Worker name                       |
| `@repo/api`       | workspace package name of the api app |

## The rule

- The **web** Worker is the web app and nothing else. Stock TanStack Start server entry, no custom routing, no API handlers, no server functions that touch data. No database, R2, queues, crons, rate limits, or secrets.
- The **api** Worker owns everything else: Hyperdrive, R2, queues, crons, rate limits, Better Auth, all secrets.
- **Every** API call — from the browser or anywhere else — goes to `api.example.app`. The web Worker never proxies or calls the database.

## The shape

```text
browser
  │
  ├──▶ example.app      web Worker (TanStack Start default entry)
  │                       ├─ static assets (hashed JS/CSS only)
  │                       └─ SSR ──── fetch (cookie forwarded) ───┐
  │                                                               ▼
  └──▶ api.example.app  api Worker (Hono)  ◀──────────────────────┘
                          ├─ /auth/*      → Better Auth
                          ├─ /*           → feature routers
                          ├─ queue()
                          └─ scheduled()
```

The two Workers share no bindings. During SSR the web Worker calls the api over plain HTTP at its public URL, exactly like the browser does. They deploy independently.

## Why a subdomain, not a separate domain

`example.app` and `api.example.app` are **same-site** (same registrable domain), though cross-origin. That means:

- `SameSite=Lax` session cookies are still sent on `fetch` from the web app to the api — no `SameSite=None`, no third-party-cookie blocking;
- only CORS with credentials is needed, not cross-site cookie workarounds.

A fully separate domain (`example-api.com`) would be cross-site and run into third-party cookie restrictions. Don't.

## Better Auth — frontend never touches the database

Better Auth runs **only** in the api Worker. The web app talks to it purely over HTTP — from the browser, and from SSR with the user's cookie forwarded.

### Server (api Worker)

```ts
export const auth = betterAuth({
  baseURL: "https://api.example.app",
  trustedOrigins: ["https://example.app"],
  advanced: {
    crossSubDomainCookies: {
      enabled: true,
      domain: "example.app",
    },
  },
  // database, providers, ...
});
```

- `baseURL` is the api origin — OAuth callbacks land on `https://api.example.app/auth/callback/<provider>`. Register those redirect URIs with each provider.
- `trustedOrigins` must list the web origin, or Better Auth rejects its requests.
- `crossSubDomainCookies` is **required for SSR**. It scopes the session cookie to `example.app`, so the browser sends it to the web Worker too — which is how SSR gets a cookie to forward. Without it the cookie is host-only on `api.example.app`, the web Worker never sees it, and every SSR render is logged-out. Keep the domain as specific as possible; don't host untrusted subdomains under it.

### Client (web app)

```ts
export const authClient = createAuthClient({
  baseURL: "https://api.example.app",
});
```

The session cookie is HTTP-only and set by the api. The browser attaches it to api calls; the web app never reads or stores a token.

### Protecting routes

SSR stays on. The web Worker has no data access, so any server-side code that needs the session or user data **asks the api**, forwarding the incoming cookie:

```ts
// web: src/lib/auth/session.ts
import { createServerFn } from "@tanstack/react-start";
import { getRequestHeaders } from "@tanstack/react-start/server";

export const getServerSession = createServerFn({ method: "GET" }).handler(
  async () => {
    const res = await fetch(
      `${import.meta.env.CLIENT_API_URL}/auth/get-session`,
      { headers: { cookie: getRequestHeaders().cookie ?? "" } }
    );
    if (!res.ok) return null;
    const session = await res.json();
    if (!session?.user) return null;
    // return a narrow shape: { id, email, name, emailVerified }
  }
);
```

- Protected layout's `beforeLoad` calls `getServerSession()` and redirects to login on `null`. It works on the first SSR request and on client navigations (the server function is invoked over RPC).
- Same pattern for SSR data loaders: call the api with the forwarded cookie (e.g. `hc` with `headers: { cookie }`), never the database.
- Cloudflare allows a Worker to `fetch` another Worker on a **custom domain** in the same zone without a service binding — so this needs no binding and no change to the default server entry.
- Each SSR render that needs the session costs one subrequest to the api. Fine at this scale; if it ever shows up in traces, a service binding to the api is a drop-in transport swap inside `getServerSession`.

This guard is cosmetic. The real boundary is the api Worker's auth middleware on every endpoint.

## Monorepo layout

```text
apps/
  web/            TanStack Start
    wrangler.jsonc
    vite.config.ts
  api/            Hono
    wrangler.jsonc
    src/index.ts  export default { fetch, queue, scheduled }
    drizzle.config.ts, migrations
```

- DB tooling (drizzle, pg, migrations, auth schema generation), logging, email, payment integrations → `apps/api`.
- React, router, UI, design system → `apps/main`.
- `apps/main` depends on `@repo/api` **for types only** (`AppType` for `hc`). Import with `import type` so no backend code enters the web bundle. Add a lint rule (Oxlint `no-restricted-imports`, `allowTypeImports`) in `apps/main` that bans value imports from `@repo/api`.

## api Worker

### Hono entry

```ts
export const app = new Hono<{ Bindings: Env; Variables: Variables }>();

// CORS first — it must run before the auth handler and every router.
app.use(
  "*",
  cors({
    origin: (origin, c) => (origin === c.env.WEB_ORIGIN ? origin : null),
    credentials: true,
    allowHeaders: ["Content-Type"],
  })
);

app.on(["GET", "POST"], "/auth/*", (c) => createAuth(c.env).handler(c.req.raw));
// ...feature routers
```

```ts
// apps/api/src/index.ts
export default {
  fetch: app.fetch,
  queue,
  scheduled,
} satisfies ExportedHandler<Env>;
```

- Never use `origin: "*"` with `credentials: true`.
- Add any extra header the web app sends (e.g. `Range`) to `allowHeaders`, and any response header it reads to `exposeHeaders`.

### Typed client (web app)

`apps/main/src/lib/client.ts` holds `hc<AppType>` with a type-only import of `AppType`. The browser sends the cookie with `credentials: "include"` (the call is cross-origin); the web Worker rejects `credentials`, so during SSR it forwards the incoming cookie instead. The full client, `unwrap` and error handling are in [`guide-api-client.md`](./guide-api-client.md).

### api wrangler.jsonc

```jsonc
{
  "name": "my-app-api",
  "main": "src/index.ts",
  "compatibility_date": "<date>",
  "compatibility_flags": ["nodejs_compat"],
  "routes": [{ "pattern": "api.example.app", "custom_domain": true }],
  "hyperdrive": [{ "binding": "HYPERDRIVE", "id": "<id>" }],
  "r2_buckets": [{ "binding": "R2", "bucket_name": "<bucket>" }],
  "queues": { "producers": [], "consumers": [] },
  "ratelimits": [],
  "triggers": { "crons": [] },
  "vars": {
    "API_URL": "https://api.example.app",
    "WEB_ORIGIN": "https://example.app",
  },
  "observability": { "logs": { "enabled": true } },
  "env": {
    "dev": {
      "name": "my-app-api-dev",
      // dev Hyperdrive, bucket, queues, rate-limit namespaces, dev vars
    },
  },
}
```

All secrets (`BETTER_AUTH_SECRET`, OAuth, payment, email) are set on this Worker only.

## web Worker

### web wrangler.jsonc

TanStack Start's default Cloudflare setup — the default server entry, no custom `main`:

```jsonc
{
  "name": "my-app-web",
  "main": "@tanstack/react-start/server-entry",
  "compatibility_date": "<date>",
  "compatibility_flags": ["nodejs_compat"],
  "routes": [{ "pattern": "example.app", "custom_domain": true }],
  "observability": { "logs": { "enabled": true } },
  "env": {
    "dev": { "name": "my-app-web-dev" },
  },
}
```

No bindings, no vars, no secrets. The only config the web app needs is browser-visible build-time env:

```dotenv
CLIENT_MAIN_URL=https://example.app
CLIENT_API_URL=https://api.example.app
```

## Local dev

Two processes, two ports:

| App | Command | URL |
| --- | --- | --- |
| web | `vite dev` | `http://localhost:3000` (site), `http://admin.localhost:3000` (dashboard) |
| api | `wrangler dev` | `http://admin.localhost:8787` |

- The dashboard is on `admin.localhost`, and Chrome never shares a `localhost` cookie with `*.localhost` (`Domain=localhost` stays host-only, and the two are different sites). So the api runs under the same name: cookies ignore ports, and a host-only `admin.localhost` cookie set by `admin.localhost:8787` reaches `admin.localhost:3000`, for browser calls and SSR forwarding alike. Leave `crossSubDomainCookies` disabled in dev. The apex doesn't see the session in dev; nothing there reads it.
- api dev vars: `WEB_ORIGIN=http://localhost:3000`, `API_URL=http://admin.localhost:8787`; Better Auth `trustedOrigins` adds the dashboard (`http://admin.localhost:3000`) on its own.
- web dev env: `CLIENT_API_URL=http://admin.localhost:8787`.
- Google takes plain-http callbacks on `localhost` only, so in dev Google returns to `http://localhost:8787/auth/callback/google` (register that one). Better Auth's `oAuthProxy` plugin, on in dev only (`apps/api/src/lib/auth.ts`), hands the profile, encrypted and valid for a minute, to `admin.localhost:8787`, which sets the session cookie there. Production and staging use the normal callback.

## Deploy

Independent. Order only matters when a change spans both:

- web starts using a new endpoint → deploy api first;
- api removes an endpoint → deploy web first.

### Go-live checklist

- [ ] Add the zone to Cloudflare.
- [ ] Custom domains in both `wrangler.jsonc` files: `example.app` and `admin.example.app` on web, `api.example.app` on api. Drop `workers_dev`.
- [ ] Set `CLIENT_ROOT_DOMAIN` (web build vars) and `COOKIE_DOMAIN`, `WEB_ORIGIN`, `ALLOWED_ORIGINS` (api vars) to the root domain.
- [ ] Register `https://api.example.app/auth/callback/google`.
- [ ] Verify `example.app` in SES: Easy DKIM CNAMEs, MAIL FROM (MX and SPF TXT), a `_dmarc` TXT. Check that a test from `hello@example.app` passes SPF, DKIM and DMARC.
- [ ] For inbound mail on the apex, use one mail host. Cloudflare Email Routing replaces existing MX records.

## Migrating from one combined Worker

- [ ] Create `apps/api`; move backend code, DB config, migrations, backend deps.
- [ ] Remove any custom Worker entry that routed between Start and Hono; the web app goes back to the default TanStack Start server entry.
- [ ] Delete `/api` prefix-stripping or path-rewrite code.
- [ ] api `wrangler.jsonc` with all stateful bindings and `api.example.app` custom domain.
- [ ] Move all secrets to the api Worker (prod and dev).
- [ ] Better Auth: `baseURL` = api origin, `trustedOrigins` = web origin; re-register OAuth redirect URIs.
- [ ] CORS with `credentials: true` and an explicit origin, before all routes.
- [ ] Strip backend deps, bindings, and data-touching server functions from the web app.
- [ ] Enable `crossSubDomainCookies` (prod) so SSR receives the session cookie.
- [ ] SSR session read and loaders → `fetch` the api with the forwarded cookie.
- [ ] `authClient` and `hc` point at `CLIENT_API_URL`; `hc` sends the cookie per [`guide-api-client.md`](./guide-api-client.md).
- [ ] `hc<AppType>` via `import type` from `@repo/api`; lint rule banning value imports.
- [ ] Root scripts: DB scripts → api filter; separate deploy scripts per app.

## Reference

- [Better Auth + Hono (CORS, mounting)](https://www.better-auth.com/docs/integrations/hono)
- [Better Auth cookies / cross-subdomain](https://www.better-auth.com/docs/concepts/cookies)
- [Better Auth session management](https://www.better-auth.com/docs/concepts/session-management)
- [TanStack Start on Cloudflare](https://developers.cloudflare.com/workers/framework-guides/web-apps/tanstack-start/)

---
version: 1.0.1
---

# Auth Guide

Better Auth on the Hono api Worker. Where each piece lives, what talks to what, and which of it is load-bearing. The web and api split it runs on is in [`guide-split-workers.md`](./guide-split-workers.md).

Better Auth is _headless_: it ships routes, a session cookie and a database schema, with no UI, hosted service or vendor account. You own the sign-in screen and the user table.

Three rules carry the rest:

1. **The server decides, the client renders.** A route guard is cosmetic. Every endpoint that returns or mutates private data authorizes the request itself.
2. **One auth instance per request, one mount point.** Sign-in, OAuth callbacks, verification links and sign-out are one handler under one path.
3. **Better Auth runs only in the api Worker.** The web app reaches it over HTTP, from the browser and from SSR with the user's cookie forwarded.

| File | Role |
| --- | --- |
| `apps/api/src/lib/auth.ts` | The server instance. `createAuth(env)`: providers, database, session policy. |
| `apps/api/src/app.ts` | The mount: one `/auth/*` line, after CORS. |
| `apps/api/src/middleware/auth.ts` | The security boundary, used by every private route. |
| `packages/db/src/schema/auth.ts` | Reviewed auth tables. |
| `apps/main/src/lib/auth/auth-client.ts` | The browser instance: hooks and sign-in calls. |
| `apps/main/src/lib/auth/session.ts` | Reads the session during SSR, forwarding the cookie to the api. |
| `apps/api/.dev.vars`, wrangler secrets | Secrets and provider credentials. |

## The per-request instance

```ts
export function createAuth(env: IEnv) {
  return betterAuth({
    database: drizzleAdapter(getDb(env), { provider: "pg", schema }),
    secret: env.BETTER_AUTH_SECRET,
    baseURL: env.API_URL,
    basePath: "/auth",
    trustedOrigins: trustedOrigins(env),
  });
}
```

Worker bindings exist only inside an invocation. A module-scope `betterAuth({...})` would throw at import or capture the first request's bindings, and it would hold a cached database client, which hangs the Worker (see [`guide-db.md`](./guide-db.md)). Read published Node examples as shapes to adapt.

**`nodejs_compat` is required.** Better Auth uses `AsyncLocalStorage`. Without the flag, auth breaks at runtime and builds fine.

## The mount

```ts
.on(["GET", "POST"], "/auth/*", (c) => createAuth(c.env).handler(c.req.raw))
```

`basePath` and the mount path are two spellings of one fact. Change both together, or OAuth breaks on the provider's error page, where your logs can't see it.

`auth.handler` returns the `Response` with `Set-Cookie` on it, so cookies set themselves. Leave `tanstackStartCookies()` out: it only applies to calling `auth.api.signIn*` inside a Start server function.

## Configuration

**Secret.** 32+ random characters, different per environment. Rotating it invalidates every live session at once.

**Sessions.**

```ts
session: {
  expiresIn: 60 * 60 * 24 * 30,
  updateAge: 60 * 60 * 24,
  cookieCache: { enabled: true, maxAge: 60 * 5 },
},
```

`cookieCache` puts signed session data in the cookie, so most API calls cost no Postgres round trip. The tradeoff is revocation lag: a signed-out or banned user stays valid until the window expires. Size `maxAge` by how fast revocation must bite.

**Rate limiting.** `storage: "database"` is mandatory on Workers. The in-memory default doesn't survive across isolates, which is the same as no limit. Counters live in the `rate_limit` table, and tight rules go on the sign-in and email-sending routes.

**Cookies across subdomains.** The web and api Workers are on different subdomains, so the session cookie is scoped to the root domain:

```ts
advanced: {
  crossSubDomainCookies: { enabled: true, domain: env.COOKIE_DOMAIN },
},
```

Everything on that domain receives the cookie. Keep user-supplied or untrusted code off every subdomain.

**Client IP, the rate limiter's key.**

```ts
advanced: { ipAddress: { ipAddressHeaders: ["cf-connecting-ip"] } },
```

Cloudflare appends to a client-supplied `X-Forwarded-For`, so that header arrives as a multi-hop chain. Better Auth then returns no IP and keys every such request into one shared bucket, which one caller can hold exhausted for everyone. `cf-connecting-ip` can't be spoofed and holds one address. List only that header, because a second entry reopens the spoofable path.

**Account linking.**

```ts
account: { accountLinking: { requireLocalEmailVerified: true } },
```

This stops a later Google sign-in from linking into an unverified account on an address its holder doesn't own, the classic pre-account-takeover. Keep it `true` even though it is the library default, so the decision stays visible. When a real owner gets `account not linked`, recover the address.

## Schema

Better Auth owns `user`, `session`, `account`, `verification` and `rate_limit`. Generate a candidate with the Better Auth CLI, using a CLI-only instance with inert bindings, because the CLI needs a module-scope `auth` and the runtime uses a factory.

Diff the candidate against `schema/auth.ts` and port the meaningful changes, keeping `withTimezone` timestamps and stable constraint names. Then generate and migrate. Repeat after upgrading `better-auth` or adding a plugin, and pin the runtime and CLI to one version.

Object keys must stay Better Auth's camelCase field names, because the adapter resolves by key.

## The client

```ts
export const authClient = createAuthClient({
  baseURL: env.CLIENT_API_URL,
  basePath: "/auth",
  fetchOptions: { credentials: "include" },
});
```

The session is an HTTP-only cookie the browser sends on credentialed calls, so there is no token to read, store or attach.

`callbackURL` is the provider's return target. Park the post-auth destination in `sessionStorage`, because it must survive a same-tab redirect through Google, and sanitize it before redirecting.

## Reading the session

| Where | Call | Use it for |
| --- | --- | --- |
| Component | `useSession()` | Rendering |
| Web SSR | a fetch to `/auth/get-session` with the cookie forwarded | Choosing what to render |
| Hono route | `authMiddleware`, then `c.get("user")` | **Authorization** |
| Anywhere in the api | `createAuth(env).api.getSession({ headers })` | **Authorization** |

`auth.handler` is the browser's door. `auth.api.*` is ours: direct function calls with no HTTP. Inside the api, always use `auth.api.getSession`, so a security check stays a local call.

## Protecting an endpoint

```ts
export const authMiddleware = createMiddleware<IAppEnv>(async (c, next) => {
  const session = await createAuth(c.env).api.getSession({
    headers: c.req.raw.headers,
  });
  if (!session?.user) {
    return c.json({ code: "unauthorized", error: "Unauthorized" }, 401);
  }
  c.set("user", { email: session.user.email, id: session.user.id });
  await next();
});
```

Import `createMiddleware` from `hono/factory`. Narrow the context to the fields handlers need.

**The guard is opt-in, so answer "who may call this?" in the handler signature** before writing the body. A new endpoint without it is public, and nothing fails to tell you.

**`authMiddleware` answers _who_, never _what they may touch_.** Every handler that takes a resource id also scopes its query by `user.id`. A handler that never compares them serves any signed-in stranger while looking guarded.

**Irreversible operations require a fresh session.** Add a check that the session was _created_ within 24 hours, measured from `session.createdAt`, not the last refresh, and fail closed on an unparseable date. Better Auth enforces this only on its own routes. The client handles the 403 by signing out and sending the user to sign in.

## Protecting a route

A `beforeLoad` guard decides what to render and is not a security boundary, because anyone can call the API directly. Throw `redirect` from `beforeLoad`, so it fires before the loader's fetches start. Hooks under an SSR route run on the server for the first request, so they stay free of `window`, `document` and `localStorage`.

If the app has a service worker, keep its precached shell on an unauthenticated route. Otherwise it can serve one user's data to the next.

## Environment

Secrets live in `apps/api/.dev.vars` locally and in Cloudflare secrets when deployed. Browser config is `CLIENT_`-prefixed (set as `envPrefix` in `vite.config.ts`), and everything in it is public.

Register each provider callback for every origin, localhost included:

```text
{API_URL}/auth/callback/google
```

A missing localhost entry is the most common cause of "OAuth works in prod, not on my machine". Local dev details are in [`guide-split-workers.md`](./guide-split-workers.md).

## Setup checklist

- [ ] `nodejs_compat` is in `compatibility_flags`
- [ ] Runtime auth uses `createAuth(env)`
- [ ] `basePath` equals the mount path
- [ ] CORS runs before the `/auth/*` mount, with `credentials: true`
- [ ] `trustedOrigins` lists every web origin
- [ ] `tanstackStartCookies()` appears in no file
- [ ] The CLI candidate was reviewed into the schema and applied by a migration
- [ ] The secret is 32+ random characters and differs per environment
- [ ] Secrets are in `.dev.vars` or wrangler secrets, and none are `CLIENT_`-prefixed
- [ ] Provider callback registered for every origin, localhost included
- [ ] `rateLimit.storage` is `"database"`
- [ ] `ipAddressHeaders` is exactly `["cf-connecting-ip"]`
- [ ] `requireLocalEmailVerified` is explicitly `true`
- [ ] Every private handler lists `authMiddleware`
- [ ] Every handler taking a resource id scopes by `user.id`
- [ ] Irreversible endpoints check session freshness, and their client handles the 403

## Traps

| Symptom | Cause |
| --- | --- |
| OAuth errors on the provider's page | `basePath` and the mount differ, or the callback isn't registered |
| Auth breaks at runtime, builds fine | `nodejs_compat` removed |
| Wrong database or secrets after deploy, or requests hang | Module-scope `betterAuth()` |
| Signed-out user keeps working for ~5 minutes | `cookieCache.maxAge`, expected |
| Rate limits never trigger | `storage` is not `"database"` |
| Rate limits fire for users behind a VPN | `ipAddressHeaders` not pinned to `cf-connecting-ip` |
| All sessions dropped after a deploy | The secret changed or is absent |
| A new endpoint serves private data to anyone | `authMiddleware` omitted |
| A guarded endpoint serves another user's data | The query isn't scoped by `user.id` |
| Google sign-in returns `account not linked` | An unverified local account holds that address |
| `beforeLoad` throws on a hard load only | A browser API in a hook that runs on the server |

## Known rough edges

- **`createAuth(env)` runs on every authorized request.** `cookieCache` saves the database round trip but not the construction. Memoizing it at module scope hangs the Worker.
- **`Set-Cookie` from the middleware is dropped.** `auth.api.getSession` can produce a refresh cookie that the middleware discards. The client's `useSession()` polling goes through `auth.handler`, which does set it, so check this before changing how the client polls.

## Reference

- Better Auth, Hono integration: <https://www.better-auth.com/docs/integrations/hono>
- Hono, Better Auth on Cloudflare: <https://hono.dev/examples/better-auth-on-cloudflare>
- Better Auth, session management: <https://www.better-auth.com/docs/concepts/session-management>
- Better Auth, cookies: <https://www.better-auth.com/docs/concepts/cookies>

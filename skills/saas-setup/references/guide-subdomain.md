# Tenant subdomains

How `{handle}.{ROOT_DOMAIN}` works: one wildcard, no per-tenant infrastructure. Read with the Hosts section of [`guide-route.md`](./guide-route.md), which has the routing mechanics.

## The rules

- **A tenant's handle is its subdomain and its sender address:** `acme.{ROOT_DOMAIN}` and `mail@acme.{ROOT_DOMAIN}`. One handle per tenant, one subdomain level.
- **Host to handle is a pure function of the hostname** (`handleFromHost` in `apps/main/src/lib/routing/host.ts`): no network call, same result on server and client. The router rewrites `acme.{ROOT_DOMAIN}/x` to the route ID `/p/acme/x` and strips the prefix again on output.
- **The api owns handles.** Syntax and reserved names live in `packages/shared/src/handle.ts`, and ownership lives in a `handles` table. The web app asks the api, and a 404 becomes `notFound()`.
- **One sending domain for every tenant.** `{ROOT_DOMAIN}` is verified in SES once (Easy DKIM plus MAIL FROM `bounce.{ROOT_DOMAIN}`). SES then sends for any subdomain, so a tenant needs no identity, DNS record or "verifying" state. Nothing is written on or under `{handle}.{ROOT_DOMAIN}`, which keeps the `*` wildcard answering for it.
- **Tenants supply content, never code.** The session cookie is scoped to the root domain, so every tenant subdomain receives it. That is safe only while tenant pages run no tenant-supplied HTML or JS.

## What to build

| Piece | Notes |
| --- | --- |
| Handle syntax | A zod schema, a reserved list, slugify, suggestions |
| Race-safe claim | `INSERT ... ON CONFLICT` |
| Availability check | `GET /handles/check`, with suggestions |
| Host rewrite | `hostRewrite` in `lib/routing/host.ts`, plus a helper for links that leave the host |
| Tenant routes | `apps/main/src/routes/p/$handle/` |
| CORS | `*.{ROOT_DOMAIN}` may call the api with credentials, via an `allowedOrigin` function |
| Sender address | One helper in `apps/api/src/lib/urls.ts` |
| Platform addresses | `auth@`, `hello@`, `contact@`, `admin@` in `packages/shared/src/addresses.ts` |
| Local dev | `acme.localhost:3000` with `CLIENT_ROOT_DOMAIN=localhost:3000`, no hosts-file edits |

**Reserve your own subdomains.** Keep one list in `packages/shared/src/handle.ts`. Only the names that serve the site (`www`, `app`, `api`, `staging`, `admin`) skip tenant routing. Other reserved names (`blog`, `docs`) reach the tenant routes and 404.

**Renames.** Allow one rename per 30 days, with a 30-day cooldown on the old name. Store `renamed_to` on the old handle and repoint older names, so a chain is one hop. Redirect with a 307, not a 301, because the old handle can belong to someone else after the cooldown.

**Test the host mapping:** apex, `www`, `staging`, two levels, look-alike domain, uppercase, `localhost`, a reserved name, and "every site subdomain is reserved".

## The request path

```text
browser asks for acme.{ROOT_DOMAIN}
  1. DNS (Cloudflare)   one proxied wildcard record, no per-tenant setup
  2. Cloudflare route   *.{ROOT_DOMAIN}/* runs the web Worker
  3. Web Worker         host.ts reads "acme" and treats the URL as /p/acme/first-project
  4. Route file         routes/p/$handle/$slug.tsx asks the api
  5. Api and Postgres   is the handle active, does the page exist: data or 404
```

## Patterns

**Skip the root `beforeLoad` server function** that reads the Host header and looks up the tenant. It makes every client navigation an RPC, and the hostname already is the handle. Only custom domains need a lookup.

**Avoid:** claims that check then write; renames with no cooldown or redirect; suffix matching that accepts `a.b.example.app`; uncached database reads per request for tenant resolution; reading the tenant in the browser and sending it as a header.

## Go-live checklist

- [ ] Add the zone and a proxied `*` record.
- [ ] Add routes in both `wrangler.jsonc` files: apex custom domain and `*.{ROOT_DOMAIN}/*` on web, `api.{ROOT_DOMAIN}` custom domain on api. Drop `workers_dev`.
- [ ] Set `CLIENT_ROOT_DOMAIN` (web build vars) and `COOKIE_DOMAIN`, `WEB_ORIGIN`, `ALLOWED_ORIGINS` (api vars) to the root domain.
- [ ] Register `https://api.{ROOT_DOMAIN}/auth/callback/google`.
- [ ] Verify `{ROOT_DOMAIN}` in SES: Easy DKIM CNAMEs, MAIL FROM (MX and SPF TXT), a `_dmarc` TXT. Check that a test from `mail@test.{ROOT_DOMAIN}` passes SPF, DKIM and DMARC.
- [ ] For inbound mail on the apex, use one mail host. Cloudflare Email Routing replaces existing MX records.
- [ ] Staging certificates: Universal SSL covers `*.{ROOT_DOMAIN}` but not `*.staging.{ROOT_DOMAIN}`. Enable Advanced Certificate Manager or Total TLS, or test tenant subdomains on production only.

## When traffic needs it

Cache the public page lookup with the Workers Cache API (30–60 s TTL, purge on publish or rename), and keep Hyperdrive query caching off. Split live counters into a small uncached endpoint first.

## Custom domains

- Use Cloudflare for SaaS on the root zone: fallback origin, custom hostnames with HTTP DV, and a CNAME target such as `domains.{ROOT_DOMAIN}`. Classify apex and subdomain with the public suffix list.
- Add a `custom_domains` table with `hostname` as primary key, `handle`, status and the Cloudflare hostname id. One owner per hostname. Roll back Cloudflare resources when registration fails.
- Resolution is no longer synchronous. Add a custom server entry that looks up `hostname → handle` in KV (written on verify, deleted on removal) and hands the handle to the router, so the rewrite produces the same `/p/$handle/...` route IDs. This is the one place a server-side tenant lookup belongs.
- The session cookie stays scoped to the root domain, so custom domains never receive it.

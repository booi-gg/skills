# Routes Guide

How a TanStack Router file route is written in `apps/main`: naming, the route file, data loading, auth, search params, navigation, hosts and prerendering, boundaries and head.

Companion docs: [`guide-structure.txt`](./guide-structure.txt) for where routes sit in the tree, [`guide-pages.md`](./guide-pages.md) for marketing pages, [`guide-module.md`](./guide-module.md) for the features a route renders.

Checked against `@tanstack/react-router` 1.170, `@tanstack/react-start` 1.168 and `@tanstack/react-query` 5.103. Paths below are relative to `apps/main/src/`.

---

## What a route file is

A route file is **wiring**. It maps a URL to a screen and declares what the router needs before rendering. Everything else lives elsewhere.

A route file may hold:

- path params, `validateSearch` and `loaderDeps`
- `beforeLoad` (guards, redirects, context) and `loader` (data prefetch)
- `head`, `ssr`, and the pending, error and not-found boundaries
- one small component that reads the route's hooks and renders a screen or page

A route file never holds:

- markup beyond picking a screen, a skeleton or a boundary
- fetch logic, query keys or query functions (those are in `features/<domain>/`)
- copy (in `pages/<page>/content/` or the feature)
- any export other than `Route`. Start's automatic code splitting moves the component into a lazy chunk. A second export forces the whole file into the critical bundle.

```tsx
// routes/admin/_protected.settings.tsx
export const Route = createFileRoute("/admin/_protected/settings")({
  component: Settings,
});

function Settings() {
  const tenant = useMyTenant();
  ...
  return <SettingsView tenant={tenant.data} />;
}
```

**Views take props, not route hooks.** The route reads `Route.useParams()` and `Route.useSearch()` and passes plain values to the screen (`<AuthView handle={handle} />`). A screen that needs route state deep in its tree uses `getRouteApi("/admin/_protected/settings")`. It never imports the route file.

## File naming

This repo uses **flat dot-notation inside a folder per surface**:

```text
routes/
  __root.tsx                               document shell, root context
  index.tsx                                /            (landing page)
  admin.tsx                                /admin       product layout
  admin/
    auth.tsx                               /admin/auth
    _protected.tsx                         pathless guard layout
    _protected.index.tsx                   /admin
    _protected.settings.tsx                /admin/settings
    _protected.projects.$projectId.index.tsx     /admin/projects/:projectId
    _protected.projects.$projectId.results.tsx   /admin/projects/:projectId/results
  p/
    $handle/
      $slug.tsx                            /p/:handle/:slug (tenant subdomain, see Navigation)
```

| Token | Meaning | Example |
| --- | --- | --- |
| `__root.tsx` | the root route, must sit at the top of `routes/` | `__root.tsx` |
| `.` | nesting, same as a folder | `_protected.settings.tsx` |
| `$name` | path param | `projects.$projectId.tsx` |
| `$` alone | splat, matches the rest of the path | `files.$.tsx` |
| `{-$name}` | optional path param | `{-$locale}.about.tsx` |
| `_name` prefix | pathless layout: wraps children, adds no URL segment | `_protected.tsx` |
| `name_` suffix | escape nesting under the parent layout | `drops_.new.tsx` |
| `index` | matches the parent path exactly | `_protected.index.tsx` |
| `route.tsx` | the route file for a folder's path | `projects/route.tsx` |
| `(group)` folder | groups files, adds no URL segment | `(marketing)/about.tsx` |
| `-name` prefix | ignored by the generator; colocated non-route files | `-components/` |
| `[x]` | escapes a special character | `sitemap[.]xml.tsx` |

Rules:

- **Inside `admin/`, stay flat.** Add a dot segment rather than a folder (`_protected.projects.$projectId.results.tsx`). A folder is for a new surface (`admin/`, `p/`), not for depth.
- **Do not use `-name` folders** to colocate components next to routes. Components go to `features/`, `pages/` or `components/`.
- **The path string is generated.** `createFileRoute("/admin/_protected/settings")` is written by the router plugin from the file name. Rename the file, run `pnpm dev` or `pnpm build`, and let the plugin rewrite it. Never edit the string by hand.
- **`routeTree.gen.ts` is output.** Never edit it. Regenerate it through the project scripts.

## Route options and key order


```tsx
interface ILoaderData {
  project: TPublicProject;
  visitorId: string;
}

export const Route = createFileRoute("/p/$handle/$slug")({
  component: HostedCampaign,
  head: ({ loaderData }: { loaderData?: ILoaderData }) => { ... },
  loader: async ({ params }): Promise<ILoaderData> => { ... },
});
```

## Data loading

The router decides **when** data loads. TanStack Query owns **the cache**. `router.tsx` already wires them together: `setupRouterSsrQueryIntegration` dehydrates the query cache into the SSR HTML, and `defaultPreloadStaleTime: 0` hands freshness to Query.

**The pattern:** the feature exports query options, the loader warms the cache, and the component reads it.

```ts
// features/project/hooks/queries/use-project.ts
export const dropQuery = (id: string) =>
  queryOptions({ queryFn: () => getCampaign(id), queryKey: dropKeys.byId(id) });

export function useCampaign(id: string) {
  return useSuspenseQuery(dropQuery(id));
}
```

```tsx
// routes/admin/_protected.projects.$projectId.results.tsx
export const Route = createFileRoute(
  "/admin/_protected/projects/$projectId/results"
)({
  component: CampaignResults,
  loader: async ({ context, params }): Promise<void> => {
    await context.queryClient.query({
      ...dropQuery(params.dropId),
      staleTime: "static",
    });
  },
});
```

- **Loaders can call authenticated endpoints.** `lib/client.ts` gives `hc` an isomorphic `fetch` (`createIsomorphicFn`). In the browser it sends `credentials: "include"`. On the web Worker it forwards the incoming request's cookie. Feature handlers work unchanged in both places.
- **Hydrated data is not refetched on mount.** The query client defaults `staleTime` to 30s (`integrations/tanstack-query/root-provider.tsx`). Without it, every query a loader warmed during SSR would refetch as soon as the page hydrates.
- **Routes that need an entity to exist redirect in the loader.** `requireMyTenant(queryClient)` warms the tenant and redirects to `/admin` (onboarding) when there is none. Its component reads the tenant with `useTenant()`, which is non-null. Header-tab pages (`/admin/projects`, `/admin/store`) don't redirect: their loader warms `myTenantQuery()`, skips the tenant-scoped calls when it is `null`, and the component renders `TenantRequiredView` with a link back to Overview.
- **Map an API 404 to `notFound()`** with `.catch(notFoundOn404)` from `lib/routing/not-found.ts`.
- **Use `queryClient.query()`.** In Query 5.103, `ensureQueryData`, `fetchQuery` and `prefetchQuery` are deprecated. `query({ ...options, staleTime: "static" })` replaces `ensureQueryData`.
- **Await what the first paint needs.** It is in the SSR HTML and there is no loading flash.
- **Don't await what can stream.** Call `void context.queryClient.query(opts).catch(noop)`. The component reads it with `useSuspenseQuery` inside a `Suspense` boundary, and SSR streams it in.
- **Type prefetch loaders as `Promise<void>`.** The data reaches the component through the query cache, not `useLoaderData`, so there is nothing to infer.
- **Fetch in parallel.** Start independent queries together with `Promise.all`. Never await one, then start the next.
- **`useSuspenseQuery` for loader-warmed data, `useQuery` for client-only data** (polling, data below the fold that need not be in the HTML).
- **Loader data without Query** (`useLoaderData`) is fine for one-shot data no other route shares, such as the public project page.
- **Search params reach the loader only through `loaderDeps`.** List only the keys the loader uses, because every listed key is part of the cache key.

```tsx
loaderDeps: ({ search: { page } }) => ({ page }),
loader: ({ context, deps }) => context.queryClient.query(dropsQuery(deps.page)),
```

Data loading still goes through `apps/main`'s rule: every call goes to `apps/api` over HTTP. The loader calls a feature handler, never a binding or the database.

## Auth and guards

- **Guard in `beforeLoad` on a pathless layout.** `admin/_protected.tsx` reads the session once, and every child inherits the guard and `context.user`. A parent's `beforeLoad` runs before its children's.
- **Guards read the cached session.** `beforeLoad` calls `queryClient.query(sessionQuery())` (`lib/auth/session.ts`), cached for the api's 5-minute cookie-cache window, so a navigation or hover preload doesn't wait on a server-fn round trip. Sign-out sets it to `null`; a `401` from the api does too, and `router.tsx` re-runs the guards.
- **Redirect by throwing:** `throw redirect({ replace: true, to: "/admin/auth" })`. Use `replace` so Back does not loop through the guard.
- **Carry the destination back.** `_protected.tsx` passes `search: { redirect: location.href }`, leaving it out for bare `/admin`. `auth.tsx` validates it with `authSearchSchema` (`lib/routing/search.ts`). `AuthView` gets it as `returnTo` and navigates there after sign-in. A user who is already signed in and lands on `/admin/auth?redirect=…` is sent straight there.
- **A redirect param only accepts product paths.** `authSearchSchema` keeps `redirect` only if it matches `/admin`, `/admin/…` or `/admin?…`. `//evil.com`, absolute URLs and `/administrator` are dropped, so the param can't become an open redirect.
- **Guards protect UI, not data.** `apps/api` authorizes every request itself. A missing guard shows the wrong screen. It never leaks data.
- **Read context, don't refetch.** A child gets the user from `context.user` (via `beforeLoad` or `Route.useRouteContext()`), not from another session call.

## Search params

- **Always validate.** `validateSearch` takes a Zod schema directly (Zod 4, no adapter). Unvalidated search is untyped.
- **Bound and default every field.** Use `.max()` on strings, and `.default()` or `.catch()` so a malformed URL renders a page instead of an error.
- **Read with `Route.useSearch()`** in the route component and pass the values down. Never read `window.location.search` in a screen. The hosted project page validates `?utm_*` with `utmSearchSchema` (`features/project-page/utils/utm.ts`) and passes `utm` to `HostedCampaignView`.
- **Unknown params are left alone.** A param the schema doesn't list (such as `fbclid`) stays in the URL. Only a listed param whose value fails `.catch()` is dropped, with a redirect to the clean URL.
- **Write with a function**, so other params survive: `navigate({ search: (prev) => ({ ...prev, page: 2 }) })`, or the same on `<Link search>`.
- **Keep shared params with middleware**, not by hand: `search: { middlewares: [retainSearchParams(["handle"])] }`. Use `stripSearchParams(defaults)` to keep default values out of the URL.

- **A schema used by more than one route lives in `lib/routing/search.ts`**, not copied into each route file.

```ts
// lib/routing/search.ts
export const handleSearchSchema = z.object({
  handle: z.string().max(HANDLE_MAX_LENGTH).optional().catch(undefined),
});
```

```tsx
// routes/admin/auth.tsx
export const Route = createFileRoute("/admin/auth")({
  component: AuthRoute,
  validateSearch: handleSearchSchema,
});
```

With `.catch(undefined)`, `/admin/auth?handle=<too long>` redirects to `/admin/auth` with the bad value dropped, instead of rendering the error screen.

## Navigation

- **Use `<Link to>` and `useNavigate()` with typed internal paths.** `to="/admin/projects/$projectId"` with `params={{ projectId }}`, never a template string. The `Register` declaration in `router.tsx` makes every `to`, `params` and `search` type-checked.
- **Pass `from` for relative links** (`from={Route.fullPath}`). It narrows the types and keeps type-checking fast.
- **Link to internal paths only.** `/admin/...` and `/p/$handle/projects/$slug` are route IDs. `lib/routing/host.ts` (`hostRewrite`) maps them to public URLs: `acme.{ROOT_DOMAIN}/projects/first-project` is routed as `/p/acme/projects/first-project`, and links on that host have `/p/acme` stripped (see [Hosts](#hosts-apex-tenant-subdomains-and-prerendering)). Never build a subdomain URL inside the app; use `tenantUrl()` for links that leave it.
- **A plain `<a href>` only for same-page anchors** (`#pricing`) and external URLs.
- **Preloading is on by default** (`defaultPreload: "intent"`): hovering a link runs its loader. That's another reason loaders should only warm the cache and stay cheap.
- **Shared link props** use `linkOptions({ to: "/admin/settings" })` or `as const satisfies LinkProps`, not a hand-typed `LinkProps`.

## Hosts: apex, tenant subdomains and prerendering

One web Worker serves three kinds of host. The apex (`{ROOT_DOMAIN}`) serves the site. `admin.{ROOT_DOMAIN}` serves the owner dashboard (the `/admin` routes). Every tenant subdomain (`acme.{ROOT_DOMAIN}`) serves that tenant's own site: tenant home, projects, store, product and order pages. The router keeps a single route tree: TanStack's recommended multi-tenant pattern rewrites the subdomain into a path.

### How a request is routed today

1. **Cloudflare picks the Worker.** `wrangler.jsonc` routes `{ROOT_DOMAIN}` (custom domain) and `*.{ROOT_DOMAIN}/*` (route on the zone) to the web Worker. `*.` matches subdomains only, never the apex, so both entries are needed.
2. **Static assets are checked first.** Cloudflare serves a file from `dist/client` whenever the **path** matches, before the Worker runs and whatever the host. Today that's only hashed `/assets/*` files.
3. **The Worker runs TanStack Start** (`main: "@tanstack/react-start/server-entry"`), which builds the router from `router.tsx` with `rewrite: hostRewrite`.
4. **`hostRewrite.input` maps the public URL to a route ID** (`lib/routing/host.ts`). On `admin.{ROOT_DOMAIN}`, `/projects` becomes `/admin/projects`. Otherwise `handleFromHost` returns `acme` for `acme.{ROOT_DOMAIN}`, and `null` for the apex and the reserved subdomains in `SITE_SUBDOMAINS`. With a handle, `/projects/first-project` becomes `/p/acme/projects/first-project`.
5. **The route renders on the server.** `p/$handle/$slug.tsx` loads the project. An API 404 becomes `notFound()`.
6. **`hostRewrite.output` maps links back**, stripping `/p/acme` on that host. A `/admin/*` link from any host points at `admin.{ROOT_DOMAIN}` without the prefix, and a non-`/admin` link from the dashboard points at the apex; a link that changes origin is a full page load. It runs on the server and the client, so hydration and client navigation agree. Keep linking by route ID (`to="/admin/projects"`); use `dashboardUrl()` only for absolute URLs the router doesn't build (auth callbacks).
7. **Old and off-host URLs redirect on their own.** Before loading, the server router compares the request with the URL `hostRewrite.output` builds for it and 307s on a mismatch. So `{ROOT_DOMAIN}/admin/projects` and `admin.{ROOT_DOMAIN}/admin/projects` both land on `admin.{ROOT_DOMAIN}/projects` with no route code.

| Public URL | Router sees | Result |
| --- | --- | --- |
| `{ROOT_DOMAIN}/` | `/` | landing page |
| `{ROOT_DOMAIN}/pricing` | `/pricing` | 404 until a pricing route exists |
| `{ROOT_DOMAIN}/admin/projects` | `/admin/projects` | 307 to `admin.{ROOT_DOMAIN}/projects` |
| `admin.{ROOT_DOMAIN}/` | `/admin` | dashboard overview |
| `admin.{ROOT_DOMAIN}/projects` | `/admin/projects` | the owner's projects |
| `acme.{ROOT_DOMAIN}/` | `/p/acme` | tenant home: store and projects |
| `acme.{ROOT_DOMAIN}/projects` | `/p/acme/projects` | the tenant's projects only |
| `acme.{ROOT_DOMAIN}/projects/first-project` | `/p/acme/projects/first-project` | project page, or "No project here" |
| `acme.{ROOT_DOMAIN}/store` | `/p/acme/store` | the tenant's products only |
| `acme.{ROOT_DOMAIN}/store/first-project` | `/p/acme/store/first-project` | product page and checkout |
| `acme.{ROOT_DOMAIN}/pricing` | `/p/acme/pricing` | 404: no tenant route matches |

**SSR is the only thing that can do this.** A rendered page can see the host. A static file cannot.

### If you want tenant subdomains (wildcard)

This is the current setup. Keep all of it:

- **A proxied wildcard DNS record** (`*`) on the zone, plus the `*.{ROOT_DOMAIN}/*` route in `wrangler.jsonc` (and `*.staging.{ROOT_DOMAIN}/*` under `env.staging`). Never add a DNS record for an individual handle.
- **`CLIENT_ROOT_DOMAIN`** in `.env` is the apex. `handleFromHost` strips its port, so `acme.localhost:3000` works in dev.
- **Reserve our own subdomains** in `SITE_SUBDOMAINS` (`@pkg/shared/handle`: `www`, `app`, `api`, `staging`, `admin`), so they serve the site and are never read as a handle. Add one there, and to `RESERVED_HANDLES`, before creating a new subdomain of our own; a test fails if the two disagree. Other reserved names still reach the tenant routes and 404.
- **Tenant routes live under `routes/p/$handle/`.** Link to them by route ID, and use `tenantUrl()` for links that leave the current host. A link whose output changes origin becomes a full page load. TanStack does that automatically.
- **No prerendered HTML.** Every path a tenant can own must reach the Worker, or a static file shadows it on every tenant host. `vite.config.ts` has no `prerender` config. Keep it that way unless you follow one of the options below.
- **Owners supply content, never code.** The session cookie is scoped to `COOKIE_DOMAIN` (the root domain), so the browser sends it to every tenant subdomain, and the api accepts credentialed calls from `*.{ROOT_DOMAIN}`. That is safe only because a tenant page renders owner text and images through our components. Never render owner-supplied HTML, scripts, embeds, or custom CSS on a tenant host; that code would run with the dashboard session of anyone signed in. If tenants ever need that, serve it from a separate registrable domain that the cookie cannot reach.

### If you want prerendering

Prerendering runs Start's server renderer at `pnpm build` and writes HTML into `dist/client`. Cloudflare then serves it as an asset. Choose by whether the Worker also serves the wildcard.

**A. The Worker serves no wildcard (apex only).** Use the plain TanStack config. Only the listed pages are rendered, and a page that fails stops the build:

```ts
// apps/main/vite.config.ts
tanstackStart({
  pages: [{ path: "/" }, { path: "/pricing" }],
  prerender: {
    autoStaticPathsDiscovery: false,
    crawlLinks: false,
    enabled: true,
    failOnError: true,
  },
}),
```

**B. The Worker also serves the wildcard (our case).** The asset layer can't see the host, so the Worker has to run first for the prerendered paths and decide. Keep the `vite.config.ts` above, then:

```jsonc
// apps/main/wrangler.jsonc
"main": "./src/server.ts",
"assets": {
  "binding": "ASSETS",
  // exactly the paths in `pages`; everything else stays asset-first
  "run_worker_first": ["/", "/pricing"]
}
```

```ts
// apps/main/src/server.ts: custom server entry
import handler from "@tanstack/react-start/server-entry";

import { handleFromHost } from "#/lib/routing/host";

export default {
  fetch(request: Request, env: Env, ctx: ExecutionContext) {
    const isApex = !handleFromHost(new URL(request.url).hostname);
    // apex: the prerendered file; tenant host: SSR through hostRewrite
    return isApex
      ? env.ASSETS.fetch(request)
      : handler.fetch(request, env, ctx);
  },
};
```

- **This gives `apps/main` a binding.** ASSETS is only the Worker's own built files, but it is an exception to the rule that web touches no bindings. Record it in `AGENTS.md` before shipping.
- **`run_worker_first` matches paths, never hosts**, and it must list exactly the prerendered paths. A listed path with no file returns a 404 from ASSETS on the apex.
- **Trailing slashes.** Start writes `/pricing` as `pricing/index.html` (`autoSubfolderIndex`). Cloudflare's default `html_handling` then redirects `/pricing` to `/pricing/`. Set `"html_handling": "project-trailing-slash"` or `prerender.autoSubfolderIndex: false` so URLs stay slash-less.
- **Build-time only.** Prerendering uses local env and bindings data, so `CLIENT_ROOT_DOMAIN` in the build env must be the production apex. A prerendered page must have no request-dependent loader (see [`guide-pages.md`](./guide-pages.md)).

**C. Split the hosts.** Route the apex to one Worker (prerender with option A) and `*.{ROOT_DOMAIN}/*` to another, with no prerendered HTML. Cloudflare's routing does the host check, so you need no custom entry and no binding. The cost is a third deployable.

Not chosen yet: today every page is SSR, which costs one Worker request per visit and gives the same SEO.

### Checking it

After `pnpm build`, run `pnpm --filter @app/main preview` and request both hosts:

```sh
curl -s -o /dev/null -w "%{http_code}\n" -H "Host: localhost:4173" http://localhost:4173/pricing
curl -s -o /dev/null -w "%{http_code}\n" -H "Host: acme.localhost:4173" http://localhost:4173/pricing
```

- **Today:** `find apps/main/dist -name "*.html"` prints nothing, and both requests reach the Worker.
- **With option B:** the apex returns the prerendered file, and the tenant host returns the project route's not-found, not the marketing page.
- **Which requests reached the Worker:** the preview log prints the Cloudflare local explorer URL. Its observability `spans` table lists every request the Worker served.

Sources: [TanStack Router URL rewrites](https://tanstack.com/router/latest/docs/framework/react/guide/url-rewrites), [TanStack Start static prerendering](https://tanstack.com/start/latest/docs/framework/react/guide/static-prerendering), [Cloudflare: TanStack Start](https://developers.cloudflare.com/workers/framework-guides/web-apps/tanstack-start/), [Cloudflare: assets vs Worker routing](https://developers.cloudflare.com/workers/static-assets/routing/worker-script/), [`run_worker_first`](https://developers.cloudflare.com/workers/static-assets/binding/), [HTML handling](https://developers.cloudflare.com/workers/static-assets/routing/advanced/html-handling/), [Workers routes](https://developers.cloudflare.com/workers/configuration/routing/routes/).

## Boundaries: pending, error, not found

Place a boundary on the highest route whose layout should survive the failure.

| Boundary | Where | What |
| --- | --- | --- |
| `notFoundComponent` | `__root.tsx`, `admin.tsx` | site and product 404: `NotFoundView` with a link home (`/` or `/admin`) |
| `errorComponent` | `__root.tsx`, `admin.tsx` | site and product error screen: `ErrorView`, whose retry calls `router.invalidate()` |
| `pendingComponent` | `admin.tsx` | product spinner while `/admin` itself loads |
| per-route `pendingComponent` | the header tabs (`OverviewSkeleton`, `ProjectsSkeleton`, `StoreSkeleton`) | the screen's real titles with blocks for its data, inside `AppShell`. `router.tsx` sets `defaultPendingMs` and `defaultPendingMinMs` to `0`, so it replaces the old page the moment a navigation starts |
| `NavigationProgress` | `AppShell` | top bar while a client navigation inside the product loads; child routes don't inherit `admin.tsx`'s spinner |
| per-route `notFoundComponent` | a route whose loader throws `notFound()` | "No project here" on `/p/$handle/$slug` |

- **Reuse the shared screens.** `NotFoundView` and `ErrorView` live in `components/shared/route-boundaries.tsx`, built on `StatusView`. A route that needs its own message (like "No project here") renders `StatusView` rather than new markup.
- **Throw `notFound()`** from `loader` or `beforeLoad` when an entity is missing (map an API 404 to it), not a rendered empty state.
- **Let other errors throw.** The nearest `errorComponent` catches them. Don't catch only to rethrow.
- **Skeletons belong to the screen's layout.** If the loader awaits the data, the component never needs a skeleton for it; the route's `pendingComponent` shows one while the loader runs. A child route does not inherit its parent's `pendingComponent`.

## Head and SSR

- **Every route that can be shared sets `head`**: `title`, `description`, `og:title`, `og:description` and `twitter:card` where relevant. Marketing pages follow [`guide-pages.md`](./guide-pages.md). Entity routes build theirs from loader data, as the public project page does.
- **Product routes inherit `noindex`** from `admin.tsx`. Don't repeat it.
- **SSR is on for every route.** Set `ssr: false` only for a route that cannot render on the server (`window`, `canvas`, `localStorage` at render). Use `ssr: "data-only"` when the data should load on the server but the component can't render there. A child can only become more restrictive than its parent.
- **Cookies and session on the server** go through `lib/auth/session.ts`, which forwards the cookie to `apps/api`. A route never reads cookies directly.

## Code splitting

Start enables `autoCodeSplitting`. The component, `errorComponent`, `pendingComponent` and `notFoundComponent` load lazily. `loader`, `beforeLoad`, `validateSearch` and `head` stay in the critical bundle. So:

- keep loaders and guards small, and import heavy code only from the component side;
- do not write `.lazy.tsx` files; the plugin already splits;
- export only `Route` (see above).

## Rules

1. One route file, one `Route` export, no other exports.
2. Route files wire; features fetch, pages render copy, screens render UI.
3. Never edit a `createFileRoute` path string or `routeTree.gen.ts` by hand.
4. Data the first paint needs is warmed in `loader` with `queryClient.query()`; read it with `useSuspenseQuery`.
5. Guards live in `beforeLoad` on a pathless layout and throw `redirect`; the API still authorizes every request.
6. Every search param is validated, bounded and defaulted.
7. Navigate with typed `<Link to>`/`navigate` on internal paths; `lib/routing` owns public URLs.
8. Nothing is prerendered while the Worker serves tenant subdomains, unless the Worker runs first and checks the host.
9. Missing entities throw `notFound()`; boundaries sit on the highest layout that should survive.

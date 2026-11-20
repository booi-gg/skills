---
version: 1.1.0
---

# API client: calling the api from the web app

How `apps/main` talks to `apps/api`: one typed `hc` client, thin handlers that unwrap it, query hooks that cache them, and one place that reacts to errors app-wide. Naming and folder rules are in [`guide-functions.md`](./guide-functions.md). Route loaders are in [`guide-route.md`](./guide-route.md). The api side is in [`guide-backend.md`](./guide-backend.md).

## Layers

```
component  →  hooks/queries · hooks/mutations  →  handlers/  →  lib/client.ts  →  api
                                    ↑
                              hooks/keys.ts
router.tsx  ←  query + mutation cache errors (401, domain codes)
```

| File | Owns | Never touches |
| --- | --- | --- |
| `lib/client.ts` | `hc<AppType>`, cookie forwarding, `unwrap`, `ApiError` | features, React, cache |
| `<module>/handlers/` | which endpoint, its input, which field of the body to return | React, cache, toasts |
| `<module>/hooks/` | query keys, `queryOptions`, invalidation | URLs, `client` |
| components | rendering, the error message | `client`, `fetch`, query keys |
| `router.tsx` | app-wide reactions to error codes | per-feature logic |

## The contract the client relies on

The api must hold these, or the client's types and errors break:

- **`export type AppType = typeof app`** from `apps/api/src/app.ts`, and the package's `exports["."]` points at that file. Every router and every mount is **chained** ([chaining rule](./guide-backend.md#the-chaining-rule)).
- **Every error body is `{ code, error }`.** `HttpError` + `app.onError`, the `validate()` zod wrapper, `notFound`, and the auth middleware's `401` all return that shape. `code` is stable and machine-readable; `error` is a human sentence.
- **Types `AppType` reaches stay importable from the browser.** Declare the slice of each binding the api uses in `types.ts`, not the Workers globals, which clash with the DOM's.

## `lib/client.ts`

The only web file that imports from `@app/api`, and only types. Enforce it with lint:

```ts
// vite.config.ts → lint rules
"no-restricted-imports": ["error", {
  paths: [{
    name: "@app/api",
    allowTypeImports: true,
    message: "Call the API over HTTP; import its types only.",
  }],
}],
```

```ts
import type { AppType } from "@app/api";
import { createIsomorphicFn } from "@tanstack/react-start";
import { getRequestHeaders } from "@tanstack/react-start/server";
import { type ClientResponse, hc } from "hono/client";

import { env } from "#/env";

/**
 * Sends the session cookie on both sides of SSR. The browser attaches it
 * (`credentials: "include"`). The web Worker doesn't support `credentials`,
 * so it forwards the incoming request's cookie instead.
 */
const sessionFetch = createIsomorphicFn()
  .server((input: RequestInfo | URL, init?: RequestInit) => {
    const cookie = getRequestHeaders().get("cookie");
    const headers = new Headers(init?.headers);
    if (cookie) {
      headers.set("cookie", cookie);
    }
    return fetch(input, { ...init, headers });
  })
  .client((input: RequestInfo | URL, init?: RequestInit) =>
    fetch(input, { ...init, credentials: "include" })
  );

export const client = hc<AppType>(env.CLIENT_API_URL, { fetch: sessionFetch });

/** Cookie-less, for public reads. Safe during SSR on public pages. */
export const publicClient = hc<AppType>(env.CLIENT_API_URL);

export class ApiError extends Error {
  readonly code: string;
  readonly status: number;

  constructor(status: number, code: string, message: string) {
    super(message);
    this.name = "ApiError";
    this.code = code;
    this.status = status;
  }
}

interface IErrorBody {
  code: string;
  error: string;
}

/** The success body of an `hc` response: every body that isn't `{ error }`. */
type TOk<TResponse> =
  TResponse extends ClientResponse<infer TBody, infer _TStatus, infer _TFormat>
    ? TBody extends IErrorBody
      ? never
      : TBody
    : never;

/** Awaits an `hc` call; throws ApiError on non-2xx, returns the JSON body. */
export const unwrap = async <TResponse extends ClientResponse<unknown>>(
  request: Promise<TResponse>
): Promise<TOk<TResponse>> => {
  const response = await request;
  if (!response.ok) {
    const body = (await response.json().catch(() => ({}))) as Partial<IErrorBody>;
    throw new ApiError(
      response.status,
      body.code ?? "error",
      body.error ?? "Something went wrong"
    );
  }
  return (await response.json()) as TOk<TResponse>;
};

export const apiErrorMessage = (error: unknown): string =>
  error instanceof Error ? error.message : "Something went wrong";
```

Why each piece:

- **`createIsomorphicFn`, not `init: { credentials: "include" }`.** The web Worker's `fetch` rejects `credentials`, so a loader running in SSR would throw. The server branch forwards the visitor's cookie, so loaders can call authenticated endpoints.
- **`publicClient`** sends no cookie. Use it for anything a signed-out visitor reads (public pages, public lookups), so the response never depends on who asked.
- **`TOk` strips the error union.** `hc` types a route's body as the union of every `c.json(...)` it returns. `TOk` drops the `{ code, error }` members, so a handler's return type is the success body only.
- **`unwrap` is the only place that reads `response.ok`.** Every handler gets throw-on-failure for free.

`env.CLIENT_API_URL` comes from a zod-parsed `src/env.ts` that holds browser-visible values only, never secrets.

## Handlers

One file per endpoint, per [`guide-functions.md`](./guide-functions.md). A handler is one `unwrap` call, plus picking the field the caller needs.

```ts
// features/project/handlers/get-project.ts
import { client, unwrap } from "#/lib/client";

export const getProject = async (id: string) => {
  const { project } = await unwrap(client.projects[":id"].$get({ param: { id } }));
  return project;
};

export type TProject = Awaited<ReturnType<typeof getProject>>;
```

```ts
// features/project/handlers/update-project.ts
import type { TProjectInput } from "@pkg/shared/project";

import { client, unwrap } from "#/lib/client";

export const updateProject = (id: string, input: Partial<TProjectInput>) =>
  unwrap(client.projects[":id"].$patch({ json: input, param: { id } }));
```

| Request part | `hc` option |
| --- | --- |
| JSON body | `{ json }` |
| Path `:id` | `client.x[":id"]` + `{ param: { id } }` |
| Query string | `{ query: { h } }` |
| File upload | `{ form: { file } }` |

Rules:

- **Derive response types, don't write them.** `export type TThing = Awaited<ReturnType<typeof getThing>>` beside the handler. Components import `TThing` from the module barrel.
- **Input types come from `@pkg/shared`**, the same zod schemas the api validates with. Never from `@app/api`.
- **`client` for signed-in calls, `publicClient` for public reads.** A public _write_ (a waitlist form on a public page) still uses `client`, so a signed-in visitor's cookie rides along.
- **Return the inner field** (`{ project } → project`) when the body wraps one thing. Return the whole body when the caller needs several fields.
- **Non-JSON responses skip `unwrap`.** A CSV or file download checks `response.ok` itself and throws the same `ApiError`, then reads `response.blob()`. This is the only place a handler touches `response` directly.
- **App-wide handlers** (an asset upload every module uses) live in `src/handlers/`.

## Hooks

### Keys

One object per module in `hooks/keys.ts`. `all` is the root every other key extends, so one `invalidateQueries({ queryKey: xKeys.all })` clears the module.

```ts
export const projectKeys = {
  all: ["project"] as const,
  byId: (id: string) => [...projectKeys.all, id] as const,
  mine: () => [...projectKeys.all, "mine"] as const,
};
```

### Queries

Each read exports **two things**: a `queryOptions` factory the route loader warms, and the hook the component reads it with.

```ts
// features/project/hooks/queries/use-project.ts
import { queryOptions, useSuspenseQuery } from "@tanstack/react-query";

import { getProject } from "../../handlers";
import { projectKeys } from "../keys";

export const projectQuery = (id: string) =>
  queryOptions({ queryFn: () => getProject(id), queryKey: projectKeys.byId(id) });

/** Reads the project a route loader warmed with `projectQuery(id)`. */
export function useProject(id: string) {
  return useSuspenseQuery(projectQuery(id));
}
```

- **`useSuspenseQuery`** for data the loader warmed. **`useQuery`** for client-only data: a debounced availability check, polling, data below the fold. Those set their own `enabled` and `staleTime`.
- The barrel exports the `*Query` factory alongside the hook, so routes can warm it.

### Mutations

The handler is the `mutationFn`. On success, invalidate the module's `all` key.

```ts
// features/project/hooks/mutations/use-update-project.ts
import type { TProjectInput } from "@pkg/shared/project";
import { useMutation, useQueryClient } from "@tanstack/react-query";

import { updateProject } from "../../handlers";
import { projectKeys } from "../keys";

export function useUpdateProject() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: ({ id, input }: { id: string; input: Partial<TProjectInput> }) =>
      updateProject(id, input),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: projectKeys.all }),
  });
}
```

- Invalidate another module's `all` too when the write changes its data.
- A mutation used by one component only (checkout redirect, portal link) may call `useMutation` inline with the handler. It still never touches `client`.

## Errors

Every failed call is an `ApiError` with `status`, `code` and a human `message`.

**In a component**, show the message; branch on `code`, never on the text:

```tsx
onError: (error) => toast.error(apiErrorMessage(error)),
// or
{update.error ? <FieldError>{apiErrorMessage(update.error)}</FieldError> : null}
```

**App-wide**, `router.tsx` subscribes to both caches once, so no feature handles a lost session:

```ts
const onError = (error: unknown) => {
  const { queryKey } = sessionQuery();
  // Only while a user is cached, so a signed-out page that gets a 401 can't loop.
  if (error instanceof ApiError && error.status === 401 && queryClient.getQueryData(queryKey)) {
    queryClient.setQueryData(queryKey, null);
    router.invalidate();
  }
};
for (const cache of [queryClient.getQueryCache(), queryClient.getMutationCache()]) {
  cache.subscribe((event) => {
    if (event.type === "updated" && event.action.type === "error") {
      onError(event.action.error);
    }
  });
}
```

`router.invalidate()` re-runs the guards and loaders, which then redirect to sign-in or render onboarding. Add a branch here only for a code that changes what the whole app shows.

**In a loader**, map a `404` to `notFound()` with `.catch(notFoundOn404)` ([`guide-route.md`](./guide-route.md)).

## Query client defaults

```ts
new QueryClient({ defaultOptions: { queries: { staleTime: 30_000 } } });
```

Without a `staleTime`, every query a loader fetched during SSR refetches the moment the page hydrates.

## Not through `hc`

| Call | Uses | Why |
| --- | --- | --- |
| Session read for guards | `createServerFn` + plain `fetch` with the forwarded cookie (`lib/auth/session.ts`) | runs on the web Worker on every navigation; see [`guide-auth.md`](./guide-auth.md) |
| Sign-in, sign-out, magic link | Better Auth `authClient` at `CLIENT_API_URL`, `basePath: "/auth"` | Better Auth owns those routes |

## Checklist

- [ ] api: `export type AppType`, every router and mount chained, every error `{ code, error }`.
- [ ] `@app/api` imported by type only, in `lib/client.ts` only; lint rule enforces it.
- [ ] `client` uses the isomorphic `sessionFetch`; `publicClient` has no cookie.
- [ ] Each handler is one `unwrap(...)` call in its own file; response type derived with `Awaited<ReturnType<…>>`.
- [ ] Input types from `@pkg/shared`; no hand-written response types.
- [ ] Keys in `hooks/keys.ts` with an `all` root; reads export `*Query` + `use*`; writes invalidate `all`.
- [ ] Components show `apiErrorMessage(error)` and branch on `error.code`.
- [ ] `401` and app-wide codes handled once in `router.tsx`, for both caches.
- [ ] `QueryClient` has a default `staleTime`.

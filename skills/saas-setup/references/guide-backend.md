# Backend: the Hono api Worker

How `apps/api` is built: its entry points, middleware order, logging, errors and typed client. The boundary with the web Worker is in [`guide-split-workers.md`](./guide-split-workers.md). What goes inside a handler is in [`guide-functions.md`](./guide-functions.md).

## The Worker entry

`apps/api/src/index.ts` exports all three entry points. A Worker has to exist for queues and crons, so the HTTP API costs nothing extra by living beside them.

```ts
export default {
  fetch: app.fetch,
  queue: (batch, env) => dispatchByQueueName(batch, env),
  scheduled: (controller, env) => runDueTasks(controller, env),
};
```

- **Queue dispatch is by queue name**, so an unregistered queue fails loudly and is never parsed as another queue's work.
- **Use one cron, every minute.** Each task checks whether it is due, runs inside its own `try`/`catch`, and gets a fresh database client. One failing task then can't stop the others.

## Middleware order

```ts
export const app = new Hono<IAppEnv>()
  .use(requestId())
  .use(loggerMiddleware())
  .use(cors({ credentials: true, origin: allowedOrigin }))
  .on(["GET", "POST"], "/auth/*", (c) => createAuth(c.env).handler(c.req.raw))
  .route("/projects", projectsRoute);

export type AppType = typeof app;
```

`requestId()` comes first because the logger reads `c.var.requestId`. Both run ahead of CORS, so a rejected preflight is still logged and `c.var.logger` exists for anything `onError` reports. CORS runs before the auth handler and every router.

## Logging

`hono-pino` + `pino`. One line per request, colourised in dev, one JSON object per line in production. A Worker's only sink is `console`.

| Export | Use it from |
| --- | --- |
| `loggerMiddleware()` | the root app, once |
| `baseLogger` | queue and cron handlers, which have no Hono context |
| `c.var.logger` | inside a request: a per-request child carrying the request id |

### Getting pino onto workerd

`pino(pretty())` and pino's `transport` option are Node-only: `pretty()` writes to a stream on fd 1, and `transport` spawns a worker thread. On workerd:

- **Use pino's browser build**, which hands each finished log object to a plain `write` function. If the bundler resolves the Node build, alias `pino` to `pino/browser.js`. It must be an alias, because `hono-pino` does its own `import pino from "pino"`.
- **In dev**, pipe each log object through pino-pretty's `prettyFactory` and `console.log` the result.
- **In production**, `console.log(JSON.stringify(log))`, the shape `wrangler tail` and Workers Logs index.

Timestamps print UTC because workerd forces `TZ=UTC`, which matches production.

### Conventions

- **Take request ids from `hono/request-id`**, not hono-pino's deprecated `http.reqId`. It also sets `x-request-id`, so a user-reported failure can be matched to its log line.
- **Add `serializers: { err: pino.stdSerializers.err }` plus `browser.serialize`.** An `Error`'s properties are non-enumerable, so without them it logs as `{}`.
- **Trim `onReqBindings` and `onResBindings`** to method, path and status. Add fields there, not at call sites.
- **Prefer `logger.error({ err, ...context }, "message")`** over interpolation, so the fields stay queryable.

| Context | Level |
| --- | --- |
| `vitest` | `silent` |
| `vite dev` | `debug` |
| deployed | `info` |

## Errors

`app.onError` maps known errors to a response and attaches the rest to the request's log line. Hono runs `onError` inside the middleware chain, so hono-pino's response line still fires and the error rides on it: one line per failure.

```ts
app.onError((thrown, c) => {
  if (thrown instanceof HttpError) {
    return c.json({ code: thrown.code, error: thrown.message }, thrown.status);
  }
  if (thrown instanceof ZodError) {
    return c.json({ code: "invalid", error: thrown.issues[0]?.message ?? "Invalid", issues: thrown.issues }, 400);
  }
  c.var.logger?.assign({ err: thrown });
  return c.json({ code: "internal", error: "Something went wrong" }, 500);
});
```

Every error response has a stable `code` the client can branch on.

## The typed client

The web app calls the api with Hono's RPC client, `hc<AppType>`, using an `import type` of `AppType`. Types come from the router, so a schema change surfaces as a client type error, and nothing from the api ships to the browser.

### The chaining rule

`hc` infers types only from **chained** handlers:

```ts
const projects = new Hono().get("/a", h).post("/b", h); // appears in AppType
const projects = new Hono();
projects.get("/a", h); // served, but invisible to the client
```

Mounts on the root app are chained too. An unchained router still serves traffic and contributes nothing to `AppType`.

**Gotcha when deriving types.** A bare `c.json(x)` types its status as the whole `ContentfulStatusCode` union, not the literal `200`, so `InferResponseType<..., 200>` collapses to `never`. Ask whether the response _could_ be a 200, and add the status when a handler deliberately returns 201 or 202.

## Where new code goes

| Need | Put it |
| --- | --- |
| Data for the web app | Hono route, called through `hc` |
| Webhook, OAuth callback, third-party caller | Hono route |
| Queue consumer, cron task | `apps/api/src/features/<feature>/`, registered in `index.ts` |
| File streaming, range requests | Hono route returning a raw `Response` |
| A log line | `c.var.logger` in a route, `baseLogger` in a queue or cron handler |

---
version: 1.0.0
---

# Database: Drizzle through Hyperdrive to Neon

How the schema is defined, how migrations are applied, how race-sensitive writes stay atomic, and the one rule about the connection that will hang the Worker if you break it.

Auth's tables and adapter are in [`guide-auth.md`](./guide-auth.md).

## The shape

| Piece | Choice |
| --- | --- |
| Database | Neon Postgres |
| Worker database access | Cloudflare Hyperdrive, with query caching disabled |
| Query builder | `drizzle-orm` |
| Driver | `drizzle-orm/node-postgres`: `pg` over TCP |
| Migrations | `drizzle-kit`, checked into `packages/db/migrations/` |
| Race-sensitive writes | Conditional updates and locking transactions |

```text
packages/db/
  drizzle.config.ts
  migrations/
  src/
    index.ts        createDb(connectionString): the only way to get a client
    schema/
      index.ts      drizzle-kit's single entry
      app.ts        product tables
      auth.ts       Better Auth tables, hand-reviewed
apps/api/src/lib/db.ts   getDb(env): createDb with the Hyperdrive connection string
```

`packages/db` is imported only by `apps/api`. A `no-restricted-imports` rule in the root `vite.config.ts` makes a stray import a lint failure.

## The connection rule

**Build a fresh client on every call and keep it inside the invocation.** This is the most important line in this document.

```ts
export const createDb = (connectionString: string) =>
  drizzle({
    casing: "snake_case",
    connection: { connectionString, max: 1 },
    schema,
  });
```

In workerd a socket belongs to the invocation that opened it, and the runtime closes it when that invocation ends. A module-scope pool keeps handing the dead client to the next request. The query promise never settles and there is no error to catch. You get the runtime's deadlock detector instead:

```text
Error: The Workers runtime canceled this request because it detected that your
Worker's code had hung and would never generate a response.
```

### How it presents

The symptom points nowhere near the cause:

- The **first** `/auth/*` request after an isolate starts succeeds. Every one after it hangs.
- Routes that never touch the database stay green, so the database looks fine.
- A route that short-circuits before its first query looks fine too.
- `/auth/*` is the loudest surface, because database-backed rate limiting queries before every handler.

The cheap confirmation is the `rate_limit` table: if eight requests leave `count = 1`, seven hung before reaching Postgres. This is a workerd rule, so cached-pool code fails the same way in production.

### The cost

A request that gets a client twice opens two short-lived edge connections. That is acceptable, because Hyperdrive removes the expensive origin handshake and reuses its Neon connections. Watch Hyperdrive's waiting-client and origin-pool metrics before raising the origin limit.

Keep Hyperdrive query caching disabled. An app with auth, billing, queues and immediate reads after writes would otherwise serve stale authorization and product state.

## Schema

Tables live in `app.ts` and `auth.ts`, re-exported from `schema/index.ts`. The `export *` there is deliberate: it stops a new table from being silently absent from the migration diff. Exempt that file in the lint config's overrides.

**Keys are camelCase, columns are snake_case.** For the auth tables this is load-bearing: the Better Auth adapter resolves fields by object key, so `emailVerified` is Better Auth's name and not ours to rename.

`user` is a reserved word in Postgres, so double-quote it in raw SQL. User ids are `text`, because Better Auth generates string ids.

## Migrations

```sh
pnpm db:generate       # diff schema into a new migration
pnpm db:migrate        # apply to staging/dev
pnpm db:migrate:prod   # apply to production, by hand, after staging/dev
pnpm db:studio
```

`drizzle-kit` runs in Node, so it reads `DATABASE_URL` from `packages/db/.env` and connects directly. Hyperdrive exists only inside Workers.

- **Applied migrations are permanent.** Fix a bad one with a new guarded forward migration.
- **Guard a tightening:** backfill, raise an exception if any row is still unfilled, and only then set `NOT NULL`.
- **Seed and reference rows belong in migrations.**
- **Every database, development included, changes only through generate and migrate.** `db:push` skips the journal and the seed rows.

## Atomic writes

Use no stored functions or triggers. Each write that races closes its race one of two ways:

- **One conditional `UPDATE`** that checks and writes together, with the limit inside the `WHERE`.
- **A transaction that locks first** (`.for("update")`) and then decides.

A transaction holds its one edge connection until it commits. Side effects that triggers would have done live in the app, for example new-user provisioning in Better Auth's `user.create.after` hook, which runs after the signup transaction commits.

## Where new code goes

| Need | Put it |
| --- | --- |
| A query | `getDb(c.env)` inside the handler |
| A new table | `schema/app.ts`, then generate and migrate |
| A change to an auth table | a CLI candidate reviewed into `schema/auth.ts`, then migrate |
| Something that must be atomic | a conditional update or a locking transaction |
| Seed or reference rows | a migration |
| A backfill or a constraint tightening | a new guarded migration |

## Databases

Use two Neon databases and no local Postgres.

| Database | Reached by |
| --- | --- |
| Production | Production Hyperdrive; `PROD_DATABASE_URL` in `packages/db/.env` |
| Staging/dev | Staging Hyperdrive when deployed; `DATABASE_URL` in `packages/db/.env`; `apps/api/.env` for `pnpm dev` |

In `pnpm dev`, `env.HYPERDRIVE.connectionString` is the staging/dev URL from `CLOUDFLARE_HYPERDRIVE_LOCAL_CONNECTION_STRING_HYPERDRIVE`, and the Worker connects to Neon directly. Every Hyperdrive origin uses Neon's direct, unpooled endpoint.

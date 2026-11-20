---
name: saas-setup
description: Full-stack SaaS setup with TanStack Start, Hono, Better Auth, Drizzle and Vite+, deployed on Cloudflare Workers. Use when scaffolding a project or changing its repo layout, Workers split, routes, hosts, marketing pages, feature modules, auth, database, payments and subscriptions, email, analytics, design system, lint config, blog or product copy.
metadata:
  version: 2.0.0
---

# Project setup

A monorepo for a SaaS that sells software (subscriptions and one-time purchases) to its own users, with two Cloudflare Workers: `apps/main` (TanStack Start, web app only) and `apps/api` (Hono: every API call, auth, all bindings and secrets). Shared code lives in `packages/`. The guides for copy, modules, functions, pages, design system, lint, payments, email and analytics apply on any host.

## Steps

1. **Pick the guides.** Find the task in the table below and read every guide its row names, from `references/`. Done when you have read each one, and `guide-structure.txt` too if files move or a package is added.
2. **Map the names.** Guides use neutral examples, listed under [Names](#names). Done when each example has its counterpart in the target project, or the project has no such concept and you have skipped that part.
3. **Build to the guide's rules and checklist.** Done when every item of the guide's checklist holds, and every [invariant](#invariants) still holds.
4. **Verify.** Run the project's check script, then its build if runtime code changed. Done when both pass.

| Task | Read |
| --- | --- |
| Start a project, or choose a library | `guide-stacks.md`, `guide-structure.txt`, `guide-split-workers.md`, `guide-lint.md` |
| Move files, add a package or app | `guide-structure.txt` |
| Web and api Worker boundary, CORS, deploy, local dev | `guide-split-workers.md` |
| Hono routes, middleware, logging, queues, crons | `guide-backend.md`, `guide-functions.md` |
| Calling the api from the web app: `hc` client, handlers, query hooks, API errors | `guide-api-client.md`, `guide-functions.md` |
| A file route: loaders, search params, navigation, hosts, head | `guide-route.md` |
| A marketing page | `guide-pages.md`, `guide-copy.md` |
| A feature module | `guide-module.md`, `guide-functions.md`, `guide-copy.md`, `guide-api-client.md` if it calls the api |
| Any user-facing words, `content/` JSON, `{placeholders}` | `guide-copy.md` |
| Sign-in, sessions, protecting endpoints | `guide-auth.md` |
| Google One Tap or Identity Services | `guide-gis.md`, `guide-auth.md` |
| Schema, migrations, atomic writes | `guide-db.md` |
| Subscriptions, one-time purchases, checkout, billing portal, gating a feature on a plan, payment webhooks, changing payment provider | `guide-payments.md`, `guide-db.md` |
| Sending email, adding a sender | `guide-mail.md` |
| Product analytics, error tracking, client logs, adding an event, changing vendor | `guide-analytics.md`, `guide-lint.md` |
| Host routing: apex and `admin.{ROOT_DOMAIN}`, prerendering, go-live domains | `guide-route.md`, `guide-split-workers.md` |
| Shared UI package | `guide-ds.md` |
| Lint, format, workspace tasks | `guide-lint.md` |
| Blog | `guide-blog.md` |

## Invariants

- `apps/main` calls `apps/api` over HTTP and holds no database access, bindings or secrets. `packages/db` is imported only by `apps/api`.
- Route files stay thin, and generated route IDs survive deliberate file moves. `routeTree.gen.ts` is generated output.
- Each package owns its env: an untracked `.env` (or `apps/api/.dev.vars` for Worker secrets) beside the code that reads it, with names and safe placeholders in the matching `.env.example`.
- Folders and workspace packages exist when they hold real code with a current consumer.
- No host under the root domain renders user-supplied HTML, scripts, embeds or CSS, because the session cookie reaches every subdomain.

## Names

| In the guides | Meaning |
| --- | --- |
| `apps/main`, `apps/api` | The web and api Workers |
| `@pkg/*`, `@app/*` | Workspace package scopes |
| `{ROOT_DOMAIN}`, `example.app` | The public domain |
| user | Someone signed up for the product |
| account, `accountId` | Who pays: the user today, an organisation if teams buy later |
| project, `first-project` | The main thing a user works on |
| `#/` | The web app's `src/` import alias |

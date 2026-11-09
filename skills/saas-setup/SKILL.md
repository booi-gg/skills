---
name: saas-setup
description: Full-stack SaaS setup with TanStack Start, Hono, Better Auth, Drizzle and Vite+, deployed on Cloudflare Workers. Use when scaffolding a project or changing its repo layout, Workers split, routes, marketing pages, feature modules, auth, database, payments, email, tenant subdomains, design system, lint config, blog or product copy.
---

# Project setup

A monorepo with two Cloudflare Workers: `apps/main` (TanStack Start, web app only) and `apps/api` (Hono: every API call, auth, all bindings and secrets). Shared code lives in `packages/`. The guides for copy, modules, functions, pages, design system, lint, payments and email apply on any host.

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
| A file route: loaders, search params, navigation, hosts, head | `guide-route.md` |
| A marketing page | `guide-pages.md`, `guide-copy.md` |
| A feature module | `guide-module.md`, `guide-functions.md`, `guide-copy.md` |
| Any user-facing words, `content/` JSON, `{placeholders}` | `guide-copy.md` |
| Sign-in, sessions, protecting endpoints | `guide-auth.md` |
| Google One Tap or Identity Services | `guide-gis.md`, `guide-auth.md` |
| Schema, migrations, atomic writes | `guide-db.md` |
| Checkout, orders, Stripe webhooks, plan billing | `guide-payments.md` |
| Sending email, adding a sender | `guide-mail.md` |
| `{handle}.{ROOT_DOMAIN}`, custom domains, host routing | `guide-subdomain.md`, `guide-route.md` |
| Shared UI package | `guide-ds.md` |
| Lint, format, workspace tasks | `guide-lint.md` |
| Blog | `guide-blog.md` |

## Invariants

- `apps/main` calls `apps/api` over HTTP and holds no database access, bindings or secrets. `packages/db` is imported only by `apps/api`.
- Route files stay thin, and generated route IDs survive deliberate file moves. `routeTree.gen.ts` is generated output.
- Each package owns its env: an untracked `.env` (or `apps/api/.dev.vars` for Worker secrets) beside the code that reads it, with names and safe placeholders in the matching `.env.example`.
- Folders and workspace packages exist when they hold real code with a current consumer.
- Tenant pages render tenant content only, with HTML, scripts, embeds and CSS kept out, because the session cookie reaches every tenant subdomain.

## Names

| In the guides | Meaning |
| --- | --- |
| `apps/main`, `apps/api` | The web and api Workers |
| `@pkg/*`, `@app/*` | Workspace package scopes |
| `{ROOT_DOMAIN}`, `example.app` | The public domain |
| tenant, `acme` | A customer organisation with its own subdomain |
| handle | The tenant's subdomain name |
| owner | The person running a tenant |
| customer | Someone buying from or signing up with a tenant |
| project, `first-project` | The main thing a tenant publishes |
| `#/` | The web app's `src/` import alias |

---
version: 1.1.0
---

# Blog Guide

Where the blog lives and how it is served. The blog is **not** a marketing page and does not live in `apps/main/src/pages/`.

Companion docs: [`guide-structure.txt`](guide-structure.txt) for the repo tree, [`guide-pages.md`](guide-pages.md) for marketing pages, [`guide-route.md`](guide-route.md#hosts-apex-admin-and-prerendering) for hosts.

---

## Why the blog is separate

A marketing page is a handful of sections with copy in JSON. A blog is a growing set of long-form posts with its own needs: Markdown/MDX authoring, an index, tags, RSS, a sitemap, per-post meta. Building that inside `pages/` would mean re-creating a content tool by hand, and every post would ship through the web Worker's build.

So the blog is its own site, built by a content tool, deployed on its own.

| Thing | Goes to |
| --- | --- |
| Landing, about, pricing, legal | `apps/main/src/pages/<page>/` |
| Blog index, posts, tags, RSS | `apps/blog/` (separate deployable) |
| Link from the site to the blog | a plain `<a href>` to the blog URL in the page's nav/footer config |

## Tool: not decided yet

Pick one when the first post is written. Any choice must output **static HTML** (no server, no data access) so the invariants below hold.

| Option | Fits when |
| --- | --- |
| Docusaurus | we want docs and blog in one site, versioning, search plugins |
| Astro (Markdown/MDX content collections) | we want a light, fast blog with full control of the design |
| Plain Markdown rendered by a small static generator | a few posts, minimal tooling |

Record the decision in this file when it is made, and replace this section with the chosen setup.

## Where it lives

- **`apps/blog/`**, a workspace app like `apps/main` and `apps/api`. Create it only when it has real content (see AGENTS.md: add folders when they contain real code).
- Posts are Markdown/MDX files in the repo, committed with the app. No CMS, no database.
- The blog has its own `package.json`, build, and deploy. Root scripts (`pnpm build`, `pnpm check`) pick it up through `vp run -r` like the other apps.

## Invariants

- **Static only.** The blog has no bindings, no secrets, and never calls `apps/api`. If a post needs live data, that part belongs in `apps/main`.
- **It imports nothing from `apps/main`.** It may use `packages/ui`, `packages/icons`, and design tokens if the chosen tool can consume them; otherwise it keeps its own styles. Nothing imports from the blog.
- **`apps/main` links to it by URL**, never by route. The blog is not in the TanStack route tree and never appears in `routeTree.gen.ts`.

## Host

**Recommended: `blog.{ROOT_DOMAIN}`** (subdomain), deployed as its own Cloudflare Worker with static assets (or Pages).

1. Give the blog Worker a custom domain `blog.{ROOT_DOMAIN}`. The web Worker answers only the apex and `admin.{ROOT_DOMAIN}`, so nothing else claims it.
2. Do the same for staging (`blog.staging.{ROOT_DOMAIN}`) if the blog has a staging deploy.

**Alternative: `{ROOT_DOMAIN}/blog`** (path). Better for sharing SEO with the apex, but the apex is a custom domain on the web Worker today, so the blog path would need either a route split on the apex or the web Worker proxying `/blog/*` — which breaks the "web is stock TanStack Start" rule in [`guide-split-workers.md`](guide-split-workers.md). Do not take this option without updating that guide first.

# Pages Guide

How a marketing page is structured in `apps/main/src/pages/`, and how it renders. Paths below are relative to `apps/main/src/`.

Companion docs: [`guide-structure.txt`](guide-structure.txt) for the repo tree, [`guide-module.md`](guide-module.md) for feature modules.

---

## What a page is

A page is a **marketing page with static content**: landing, about, pricing, legal. Its job is to be read and indexed, not to run the product.

**The test — all three must hold:**

1. **It is public.** No session needed to see it.
2. **Its content is copy, not user data.** What it shows comes from JSON in the repo, not from the API.
3. **It renders the same for every visitor.** No per-user or per-request content in the HTML.

If any of these fail, it is product UI: it belongs in `src/screens` behind a route under `routes/app/`.

| Thing | Goes to |
| --- | --- |
| Landing, about, pricing, legal | `src/pages/<page>/` |
| Blog | `apps/blog/`, not a page — see [`guide-blog.md`](guide-blog.md) |
| Product screen (dashboard, editor, results) | `src/screens/` |
| Interactive widget a page needs (handle check) | the page's own `ui/`, calling a feature hook |
| Reusable primitive or icon | `packages/ui/` |

## Rendering: SSR on every request, static-ready

- **Every page is server-rendered.** The full copy is in the HTML response: no loading states, no client-only fetches for content. Crawlers and link previews get the real page.
- **Pages are not prerendered.** `vite.config.ts` has no `prerender` config, so the web Worker renders every page on every request. The same Worker serves tenant subdomains, and Cloudflare serves static files by path on every host, so a prerendered `/pricing` would also answer `acme.{rootHost}/pricing`. Before adding a page to a prerender list, read [Hosts: apex, tenant subdomains and prerendering](./guide-route.md#hosts-apex-tenant-subdomains-and-prerendering) and pick an option there.
- **Write pages as if they were static.** Rendering depends only on the repo, never on the request. That keeps them cheap to SSR, and lets them be prerendered later without changes.
- **Interactivity is an island, not the page.** A small client widget (for example `ui/handle-claim.tsx`, which checks a handle through the `useHandleCheck` hook from `features/tenant`) hydrates on top of the server-rendered HTML. It must render a sensible initial state on the server and must not block or replace the page's content.
- **No `loader` that calls the API for content.** If a page needs data at render time, it is either build-time content (put it in JSON) or it is not a page.
- **Config, not requests.** Values like `rootHost` and plan limits come from build-time config and shared packages, so they render the same for every request.

## Anatomy

Add a folder only when it holds real code.

```text
pages/<page>/
  index.tsx            the page component: composes sections in order, nothing else
  content/
    en/
      meta.json        <title>, description, og:* for the route's head()
      <section>.json   one file per section, all visible copy
      <ui>.json        copy for a ui/ component that carries its own (handle-claim.json)
  data/
    copy.ts            loads content/en/*.json, fills {placeholders} via #/lib/copy; exports one object per JSON file
  sections/
    <n>.<name>-section.tsx one exported component per section, <n> = its position on the page
  ui/
    section.tsx        building blocks shared by this page's sections
    ...
```

A page renders only its `<main>`. The header nav and footer belong to the site chrome (below), so a page has no `navs/` or `footer/`.

The route file stays thin. It wires the page and its head, and nothing more. Every page route lives under `routes/_site/`. This is the real `routes/_site/index.tsx`; copy all of it:

```tsx
// routes/_site/index.tsx
import { createFileRoute } from "@tanstack/react-router";

import { LandingPage } from "#/pages/landing";
import { meta as landingMeta } from "#/pages/landing/data/copy";

export const Route = createFileRoute("/_site/")({
  component: LandingPage,
  head: () => ({
    meta: [
      { title: landingMeta.title },
      { content: landingMeta.description, name: "description" },
      { content: landingMeta.ogTitle, property: "og:title" },
      { content: landingMeta.ogDescription, property: "og:description" },
      { content: "website", property: "og:type" },
      { content: "summary_large_image", name: "twitter:card" },
    ],
  }),
});
```

**Every page route sets the full head.** That means `title`, `description`, `og:title`, `og:description`, `og:type` and `twitter:card`. Without the `og:*` and `twitter:card` tags, links to the page show no social preview. Text values come from the page's `meta.json` (`title`, `description`, `ogTitle`, `ogDescription`). Fixed values like `og:type` stay in the route.

## Copy lives in JSON

- **All visible text is in `content/<locale>/*.json`**: headings, body, button labels, aria labels, alt text, and the head meta. Components hold no literal copy.
- **One JSON file per section**, named like the section without its number (`hero.json` ↔ `1.hero-section.tsx`). A `ui/` component that carries its own copy gets its own JSON file, named like the component (`handle-claim.json` ↔ `ui/handle-claim.tsx`).
- **Dynamic values are `{placeholders}`** (`{rootHost}`, `{proPrice}`), filled in `data/copy.ts` from config with `fillDeep` from `#/lib/copy`. Unknown placeholders are left in place so a component can fill them at runtime with `fill` from `#/lib/copy` (`fill(copy.available, { handle })`). Feature modules follow the same rules — see [`guide-module.md`](./guide-module.md#copy-lives-in-json).
- **Only `en` exists today.** `copy.ts` imports `content/en/*.json` directly. A second locale means choosing the locale in `copy.ts`, not in components.
- **Emphasis is `**bold**`**, rendered by `RichText`. Don't put markup in JSON.
- **No fake numbers, logos, or testimonials.** Every figure is a real limit or sits inside a mock labelled "Example".

## Sections

- **One section, one file, one export.** `index.tsx` imports them and lists them in page order.
- **Section files are numbered by page order**: `<n>.<name>-section.tsx`, starting at `1`, no zero-padding, no gaps. The first section on the page is `1.`, the next `2.`, and so on, so the folder listing reads as the page. Example from `pages/landing/sections/`:

  ```text
  1.hero-section.tsx
  2.problem-section.tsx
  3.how-it-works-section.tsx
  ...
  10.final-cta-section.tsx
  ```

- **Inserting, removing or reordering a section renumbers the files after it**, and updates their imports in `index.tsx`. The number lives in the file name only: export names (`Hero`, `PricingSection`) and JSON files (`hero.json`) stay unnumbered.
- **A section reads its own copy** from `data/copy.ts`. It takes no copy props.
- **Every component in `sections/` renders the shared `Section` from `ui/section.tsx`**, the hero included. That keeps the eyebrow, heading and body layout, `aria-labelledby` and the `scroll-mt` anchor offset consistent. Never write a bare `<section>`. For a layout `Section` lacks, extend it with a prop. Existing props: `size="hero"` for the display heading, `aside` for a second column, `decoration` for background art.
- **Chrome is not a section.** The header nav and the footer belong to the site chrome and render their own landmark (`<header>`, `<footer>`), not `Section`.
- **Anchor ids live on the section** (`id="faq"`). Renaming an id means updating every `hash` that points at it in `pages/site/navs/config.ts` and `pages/site/footer/config.ts`.

## Site chrome

Every marketing page shares one header nav and one footer. They live in `pages/site/` and render from the pathless layout route `routes/_site.tsx`, which wraps every page route in `routes/_site/`. Moving between pages swaps only the page; the nav stays mounted.

```text
pages/site/
  index.tsx            SiteLayout: nav, <Outlet />, footer
  content/en/          nav.json, footer.json (labels only)
  data/copy.ts         loads and fills them
  navs/                config.ts (navConfig) + site-nav.tsx
  footer/              config.ts (footerConfig) + footer-section.tsx
```

- **JSON holds only labels**, keyed by link (`"links": { "pricing": "pricing" }`). No routes or ids in JSON.
- **`config.ts` holds the structure**: each link is a route `to`, plus a `hash` for a section on that page (`{ hash: "faq", to: "/" }`), in display order.
- **Links are router `<Link>`s, never plain `<a href>`.** A plain anchor reloads the document, which remounts the chrome. Hash links use `siteLinkActive`, so a section link counts as current only on its section.
- **The component renders only that config object.** It does not import `data/copy` directly and does not hard-code a target.
- Adding a link means adding its label to the JSON and its `{ to, hash?, label }` entry to `config.ts`.
- Adding a page means adding its route under `routes/_site/`; it gets the chrome for free.

## Rules

- **The page column is `pageWidth` from `@pkg/ui`**: the header bar's width and gutters. Every section's content wrapper, the footer and any full-page layout use `cn(pageWidth, …)`, so content lines up with the nav at every breakpoint. Never hand-write `mx-auto max-w-* px-*` for a page column; a deliberately narrower block (a reading column, a centred form) sits inside it.
- `index.tsx` is not a barrel. Oxlint's `oxc/no-barrel-file` rejects re-exports; import `data/copy` directly where needed.
- **UI comes from two places only**: the page's own folder (`sections/`, `ui/`) or `packages/ui`. A page never imports components from `features/`, `src/components/`, or another page. Icons follow the same rule.
- A page never imports another page, and never imports `pages/site/`. Only the `_site` layout route renders the chrome. A primitive two pages need goes to `packages/ui`.
- A page may import a hook from `features/` to power an interactive island in its `ui/`. It never imports a feature's components or content.
- Before adding a page, check that it passes the three-part test above. If it fails, build a screen in `src/screens/` instead.

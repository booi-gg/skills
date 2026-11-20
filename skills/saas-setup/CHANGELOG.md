# Changelog

`SKILL.md` and every file in `references/` carry their own version (`metadata.version` in `SKILL.md`, `version` in each guide's frontmatter). This file is the history for all of them. Agents using the skill never need to read it.

## Versioning

Semver, per file:

| Bump | When | Example |
| --- | --- | --- |
| Major | A rule changed, so a project built to the old version must migrate | a module renamed or removed, a different provider or pattern |
| Minor | Something added or reworded with a new instruction, and old projects stay correct | a new section, a new checklist item, a new example |
| Patch | Wording or example names only, no new instruction | a typo, a renamed placeholder |

Bump `SKILL.md`'s major whenever any guide's major moves, or when a guide is added or removed. Every change adds an entry here under a new skill version, naming each file and its new version.

## 3.0.0 (2026-11-20)

Icons get their own guide. Major because a guide was added; no existing rule forces a migration.

- **`guide-icons.md` 1.0.0.** New. `packages/icons` (`@pkg/icons`): Phosphor re-exported per icon from its own subpath, only icons in use, custom icons on `IconBase`, the lint boundary, usage (accessibility, size, colour, weight), Lucide kept to vendored shadcn output, changing library, checklist.
- **`SKILL.md` 3.0.0.** Icons task row; "icons" in the description and the any-host line.
- **`guide-pages.md` 1.2.0.** Icons come from `@pkg/icons`, not `packages/ui` or the page folder. This corrects a clash with `guide-structure.txt`, which already put every icon in `packages/icons`.
- **`guide-lint.md` 1.2.0.** Icon library boundary (`@phosphor-icons/*` banned outside `packages/icons`); `oxc/no-barrel-file` off for the icons index.
- **`guide-ds.md` 1.1.0.** Lucide only in shadcn-generated files; hand-written components import from `@pkg/icons`.
- **`guide-structure.txt` 1.0.2.** Links `guide-icons.md` from the tree and from structure rule 10.

## 2.0.0 (2026-11-20)

The skill now targets a SaaS that sells software (subscriptions and one-time purchases) to its own users. Tenants, tenant subdomains, Stripe Connect stores and physical goods are gone.

- **`SKILL.md` 2.0.0.** Scope line, task table, the cookie invariant (now any user-supplied code on any subdomain) and Names (`user`, `account`; no `tenant`, `handle`, `owner`, `customer`). Versioning added.
- **`guide-payments.md` 2.0.0.** Rewritten. A billing module in `features/billing` (`startCheckout`, `openPortal`, `getAccess`, `hasFeature`) over a `PaymentProvider` interface, with one adapter per provider in `integrations/payment/`. A catalog in `packages/shared`, access read from our own tables, the webhook used as a hint followed by a fresh read, `provider` stored on every row, and a Stripe adapter over `fetch` (form encoding, pinned version, signature check). Includes changing provider (Polar, Paddle) and a checklist. Stripe Connect, orders, stock, shipping and early-access grants are removed.
- **`guide-subdomain.md` removed.** Its non-tenant go-live items moved to `guide-split-workers.md`.
- **`guide-route.md` 2.0.0.** Hosts are now the apex plus `admin.{ROOT_DOMAIN}` only: no wildcard, `p/$handle` routes, `handleFromHost` or `tenantUrl`. The prerender options are reframed around the admin host (`isAdminHost`). Examples renamed (`useMyProfile`, `emailSearchSchema`).
- **`guide-mail.md` 2.0.0.** One module (`features/mail`). The tenant outbox (`features/email`, per-tenant consent, broadcasts, auto-pause, sending limits) is removed.
- **`guide-split-workers.md` 1.1.0.** Go-live checklist added. Dev note no longer mentions tenant subdomains.
- **`guide-blog.md` 1.1.0.** `blog.{ROOT_DOMAIN}` is a plain custom domain; there is no wildcard to claim it from.
- **`guide-pages.md` 1.1.0.** Prerender warning is about the admin host. Example island is `ui/waitlist-form.tsx`.
- **`guide-api-client.md` 1.1.0.** The `no_tenant` branch is removed from the app-wide error handler. Examples now say "public pages".
- **`guide-lint.md` 1.1.0.** Payment SDK boundary in `apps/api`.
- **`guide-copy.md` 1.0.1, `guide-module.md` 1.0.1.** Placeholder examples (`{email}`, `{name}`) and the email-voice line.
- **`guide-auth.md` 1.0.1, `guide-gis.md` 1.0.1.** Tenant wording removed.
- **`guide-structure.txt` 1.0.1.** `integrations/payment/` annotated. Prerender note mentions the admin host.
- **`guide-analytics.md`, `guide-backend.md`, `guide-db.md`, `guide-ds.md`, `guide-functions.md`, `guide-stacks.md` 1.0.0.** Unchanged; versioned from here.

## 1.0.0

Baseline: every file as it was before versioning started (commit `3f7ee8c`, "add analytics guide with vendor migration"), including tenants, tenant subdomains and the Stripe Connect payments guide.

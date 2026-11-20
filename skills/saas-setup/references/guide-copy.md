---
version: 1.0.1
---

# Content and Copy Guide

How copy is decided, written and loaded into the product. Paths are relative to `apps/main/src/` unless they start with `apps/`, `packages/` or `docs/`.

Page anatomy is in [`guide-pages.md`](./guide-pages.md), feature modules in [`guide-module.md`](./guide-module.md), sending email in [`guide-mail.md`](./guide-mail.md).

## Steps

1. **Ground it in the customer.** Read the project's customer profile (`docs/icp.md`). The user's decisions in conversation outrank it. If the project has none, ask for the audience, the positioning and the headline, and write that file. Done when you can name who reads this copy and which moment it serves.
2. **Plan a rewrite in `docs/`.** Applies when the change spans a whole page or several sections. List each section as a checkbox with its word count today and its target ("117 → 30"). Done when every section has both numbers.
3. **Write the words** in the location below. Done when every visible string sits there: headings, body, labels, hints, placeholders, errors, button text, `aria` labels, alt text, head meta, and sample data inside mocks.
4. **Make every product fact a placeholder.** Prices, fees, limits, the domain and the product name come from config, so copy can't drift. Done when the changed copy holds none of them as literals.
5. **Load it through `data/copy.ts`.** Done when the only importer of each JSON file is its `data/copy.ts`.
6. **Check the [truth](#truth).** Done when every figure traces to config or sits in a labelled mock, and every promised feature exists or is tracked.
7. **Read it rendered**, at desktop and 375px. Done when no raw `{name}` or `**` shows on the page.

## Where copy lives

| Copy | Location | Loaded by |
| --- | --- | --- |
| Marketing page section | `pages/<page>/content/en/<section>.json` | `pages/<page>/data/copy.ts` |
| Page head (title, description, `og:*`) | `pages/<page>/content/en/meta.json` | the same `copy.ts`, read in the route's `head()` |
| A page `ui/` component with its own copy | `pages/<page>/content/en/<component>.json` | the same `copy.ts` |
| Header nav and footer labels | `pages/site/content/en/{nav,footer}.json` | `pages/site/data/copy.ts` |
| Long-form legal text | `pages/<page>/content/en/document.json` | that page's `copy.ts`, rendered by a shared document component |
| Feature module | `features/<module>/content/en/<component>.json` | `features/<module>/data/copy.ts` |
| Shared app components | `components/shared/content/en/<component>.json` | `components/shared/data/copy.ts` |
| Emails | `apps/api`, in TypeScript templates beside the mail code | render functions returning `{ subject, html, text }` |

Email copy stays in `apps/api` because it renders there. Name a JSON file after what it serves: `hero.json` for `1.hero-section.tsx`, `onboarding-view.json` for `views/onboarding-view.tsx`. A section reads its own copy and takes no copy props.

## The utilities

Create `lib/copy.ts` once:

```ts
import { PLATFORM_NAME } from "@pkg/shared/platform";

import { rootHost } from "#/lib/routing/host";

export type TTemplateValues = Record<string, number | string>;

/** In every copy file: `{platform}` is the product name, `{rootHost}` the public domain. */
export const SITE_VALUES = { platform: PLATFORM_NAME, rootHost } as const;

const PLACEHOLDER = /\{(\w+)\}/gu;

/** Replaces known `{name}` placeholders; unknown ones are left for later. */
export function fill(template: string, values: TTemplateValues): string {
  return template.replace(PLACEHOLDER, (match, name: string) =>
    name in values ? String(values[name]) : match
  );
}

/** `fill` over every string in a JSON value, keeping its shape. */
export function fillDeep<T>(value: T, values: TTemplateValues): T {
  if (typeof value === "string") {
    return fill(value, values) as T;
  }
  if (Array.isArray(value)) {
    return value.map((entry) => fillDeep(entry, values)) as T;
  }
  if (value && typeof value === "object") {
    return Object.fromEntries(
      Object.entries(value).map(([key, entry]) => [key, fillDeep(entry, values)])
    ) as T;
  }
  return value;
}
```

Each folder with copy has a `data/copy.ts` exporting one filled object per JSON file:

```ts
import { PLANS } from "@pkg/shared/plans";

import { fillDeep, SITE_VALUES, type TTemplateValues } from "#/lib/copy";

import heroJson from "../content/en/hero.json";
import metaJson from "../content/en/meta.json";

const CONFIG_VALUES: TTemplateValues = {
  ...SITE_VALUES,
  proPrice: PLANS.pro.priceUsd,
};

const fillConfig = <T>(value: T): T => fillDeep(value, CONFIG_VALUES);

export const meta = fillConfig(metaJson);
export const hero = fillConfig(heroJson);
```

Components fill runtime values at render:

```tsx
<RichText text={fill(copy.joined, { email })} />
```

`RichText` renders `**bold**` runs. Put it in `packages/ui` so every page can share it:

```tsx
const BOLD = /\*\*(.+?)\*\*/u;

export function RichText({ text }: { text: string }) {
  const nodes: ReactNode[] = [];
  let offset = 0;
  for (const [index, part] of text.split(BOLD).entries()) {
    nodes.push(
      index % 2 === 1 ? (
        <span className="font-heavy" key={offset}>
          {part}
        </span>
      ) : (
        part
      )
    );
    offset += part.length;
  }
  return nodes;
}
```

Keep one source of truth for each value in `packages/shared`: the product name, plans and prices, company details for legal pages, and form limits. Keep one money formatter, and make its input unit clear from its name (`formatCents`, `formatDollars`).

## Placeholders

| Kind | Example | Filled | With |
| --- | --- | --- | --- |
| Config | `{platform}`, `{rootHost}`, `{proPrice}`, `{titleMax}` | once, at load | `fillDeep` in `data/copy.ts` |
| Runtime | `{email}`, `{count}`, `{when}` | at render | `fill` in the component |

- **Format before filling.** `fill` only calls `String()`. Pass a formatted string when the format matters.
- **A typo ships silently.** Unknown placeholders stay in place by design, so `{proPirce}` reaches the page as written.
- **Keep runtime names apart from config names.** Config fills first, so a runtime `{email}` in a file whose loader also has an `email` value is gone before render.
- **The dollar sign is literal.** Write `${proPrice}` in JSON for `$19`. The placeholder is only `{proPrice}`.
- **Keep sentences whole in JSON** and join values with `fill`, so a second locale can reorder them.
- **Handle plurals deliberately.** `fill` has no plural logic, so `"{count} members"` reads "1 members". Use two keys, or `Intl.PluralRules`.

## Voice

- **Every message serves the project's positioning**, in the words from the customer profile.
- **Lowercase, short, plain** on marketing pages and in product UI: "free to start. no card." Names the customer typed keep their case. Third-party names follow the lowercase in marketing copy.
- **Email is sentence case.** It is direct and says what happens next.
- **Feelings over features** on the landing page.
- **Art carries the idea** on the landing page. Copy is a noun headline plus at most 12 words, and each section stays within 40 words.

## JSON formatting

- **`**bold**` is the only markup.** It renders only where `RichText` or the document component renders the string.
- **Use typographic apostrophes** (`you’re`), and `·` to separate short facts on one line.
- **Use ` `** to hold words together in a display heading.

## Truth

- **Every figure is a real limit or sits inside a mock labelled "example".** Logos and testimonials are real or absent.
- **Placeholder proof stays behind a flag.** A `live: false` in the JSON keeps sample social proof out of production while you design against it in development. Set `live` only when the numbers are real.
- **Mocks show what the product does today**, or what a tracked plan ships before launch. For a promised feature that isn't built, ship it first or take it out of the copy.
- **Market benchmarks stay internal** unless the source is primary.

# Content — `content/<locale>/`

Every user-facing string in the module, as pure JSON. No `.ts`, no barrel, no logic, no derived values.

## Split

One file per thing a developer can point at, named in kebab-case after it: `PricingHeader.tsx` → `pricing-header.json`.

| Split by  | When the module is…                    | Example                                  |
| --------- | -------------------------------------- | ---------------------------------------- |
| Page      | multi-page (flow, wizard, tabs)        | `checkout-page.json`, `review-page.json` |
| Component | one page of big, distinct blocks       | `pricing-header.json`                    |
| Dialog    | anything modal                         | `cancel-plan-card.json`                  |
| Shared    | copy reused across several of the above | `common.json`                            |

- Small module → one file is fine. Split when a file passes a screen or two, or when two people edit it for unrelated reasons.
- One file, one owner: a component's copy lives in exactly one file.

## Shape and wiring

A file holds its fields directly, with no wrapping top-level key:

```json
// content/en/cancel-plan-card.json
{
  "title": "Cancel plan",
  "keepAllNote": "Keep all {0} products"
}
```

The service imports each file once and keys it by the filename in camelCase:

```ts
const MODULE_CONTENT = Object.freeze({
  cancelPlanCard, // ./content/en/cancel-plan-card.json
  common,         // ./content/en/common.json
} satisfies TModuleContent);
```

Components read it through the service:

```tsx
const copy = ModuleService.content.cancelPlanCard;
```

- Keys come from filenames, so two files can never collide. Spreading files into one object silently overwrites duplicate keys, and the type does not catch it.
- Switching locale is one edit, in the service.

## Typing

Hand-write one type per file in `types.<module>.ts`. Name it `T<File>Content` and add it to `TModuleContent`. `satisfies` in the service checks every JSON file against it. The type is the only place a placeholder can be documented:

```ts
export type TCancelPlanCardContent = {
  title: string;
  /** `{0}` — number of products in the bundle */
  keepAllNote: string;
};
```

## Placeholders — `{0}`, `{1}`

Never concatenate in JSX. Put a positional placeholder in the JSON and interpolate at render time:

```tsx
<p>{formatTemplateString(copy.keepAllNote, String(bundleSize))}</p>
```

- Zero-indexed, numbered in reading order.
- Format before passing (`formatCurrency(x)`, `n.toFixed(2)`). The JSON never carries formatting.
- Pass strings and convert numbers at the call site.
- Markup goes through `parse()` (html-react-parser) **after** interpolation.
- Why: the sentence stays one unit a translator can reorder, and the number is computed in one place.

## Why only JSON

- The service is the merge point: it is the one place deciding what `content` holds.
- Adding a locale should mean copying a folder of JSON and translating it, with no code inside to break.

## vs runtime i18n (i18next, `public/locales`)

|                          | `content/<locale>/`     | runtime i18n       |
| ------------------------ | ----------------------- | ------------------ |
| Loaded                   | bundled at build        | fetched at runtime |
| Follows language switch  | no                      | yes                |
| Interpolation            | `{0}` + formatter       | `t()`, `{{name}}`  |
| Lives with module        | yes                     | no                 |

Default to `content/`. Use runtime i18n when the module must follow the user's selected language.

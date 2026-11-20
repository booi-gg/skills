---
version: 1.0.0
---

# Icons package

Every icon the apps render comes from one workspace package, `packages/icons` (`@pkg/icons`). It re-exports the icons in use from [Phosphor](https://phosphoricons.com) (`@phosphor-icons/react`), one module per icon, and holds any custom icons. Read this before adding an icon, drawing a custom one or changing the icon library.

**The rule:** apps and packages import icons only from `@pkg/icons`, never from the library. A lint rule enforces it. The one exception is vendored shadcn output (see [packages/ui](#packagesui-and-shadcn)).

## The shape

| Piece | Choice |
| --- | --- |
| Library | `@phosphor-icons/react`, pinned exactly |
| Distribution | exports `src/index.ts` directly; no build step |
| Public API | one `index.ts`: the types, then one named re-export per icon, sorted |
| Import path | per-icon subpath (`@phosphor-icons/react/House`), never the root barrel |
| Names | the `*Icon` names (`HouseIcon`); the bare names are deprecated |
| Custom icons | one file each in `src/icons/`, built on Phosphor's `IconBase` |
| React | peer and dev dependency, as in `packages/ui` |
| Consumers | `apps/main`, `packages/ui` (hand-written components), `apps/blog` if its tool can use React |

## Files

```txt
packages/icons/
├── package.json
├── tsconfig.json
└── src/
    ├── icons/          # one file per custom icon; created with the first one
    └── index.ts        # every icon the apps use
```

### `package.json`

```json
{
  "name": "@pkg/icons",
  "version": "0.0.0",
  "private": true,
  "type": "module",
  "sideEffects": false,
  "exports": {
    ".": "./src/index.ts"
  },
  "scripts": {
    "typecheck": "tsc --noEmit"
  },
  "dependencies": {
    "@phosphor-icons/react": "2.1.10"
  },
  "devDependencies": {
    "@types/react": "^19.3.0",
    "react": "^19.2.0",
    "react-dom": "^19.2.0",
    "typescript": "^6.0.3"
  },
  "peerDependencies": {
    "react": "^19.0.0",
    "react-dom": "^19.0.0"
  }
}
```

- **`sideEffects: false`** lets the bundler drop any icon no file imports.
- **Pinned library version.** A minor Phosphor release can redraw icons; bump it on purpose and look at the screens.
- Match the React and TypeScript versions the rest of the workspace uses. The versions above are a known-good snapshot, not an instruction to downgrade.

### `tsconfig.json`

```json
{
  "compilerOptions": {
    "target": "ES2023",
    "lib": ["ES2023", "DOM", "DOM.Iterable"],
    "module": "ESNext",
    "moduleResolution": "Bundler",
    "moduleDetection": "force",
    "noEmit": true,
    "jsx": "react-jsx",
    "strict": true,
    "skipLibCheck": true,
    "verbatimModuleSyntax": true,
    "noUnusedLocals": true,
    "noUnusedParameters": true,
    "erasableSyntaxOnly": true,
    "noFallthroughCasesInSwitch": true,
    "noUncheckedSideEffectImports": true
  },
  "include": ["src"]
}
```

### `src/index.ts`

```ts
/**
 * Every icon the apps use. Apps import icons only from here, never from
 * Phosphor directly, so the set stays in one place.
 *
 * Add a Phosphor icon from its own module, by its `*Icon` name (the bare names
 * are deprecated), keeping the list sorted:
 *
 *   export { HouseIcon } from "@phosphor-icons/react/House";
 *
 * Browse names at https://phosphoricons.com. A custom icon gets its own file
 * in `src/icons/` and is exported here.
 */

export type { Icon, IconProps, IconWeight } from "@phosphor-icons/react";

export { ArrowUpRightIcon } from "@phosphor-icons/react/ArrowUpRight";
export { ImageIcon } from "@phosphor-icons/react/Image";
export { XIcon } from "@phosphor-icons/react/X";
```

- **Per-icon subpaths.** `@phosphor-icons/react/House` resolves to that one icon's module. The root entry re-exports all 1,500+ icons: tree shaking removes them from the production bundle, but the dev server still loads them all.
- **Types from the root.** `export type` is erased at build time, so it costs nothing.
- **Only icons in use.** An icon is added with its first consumer and removed with its last.

## Wiring

1. Add the package to the consumer's `package.json`: `"@pkg/icons": "workspace:*"`. No Vite or tsconfig changes: the package ships TypeScript source and the app's bundler compiles it.
2. Add the lint boundary below.
3. Turn off `oxc/no-barrel-file` for `packages/icons/src/index.ts`: the index is the package's whole public API on purpose.

### Lint boundary

In the root `vite.config.ts`, the `no-restricted-imports` override that already bans `@pkg/db` (see [`guide-lint.md`](./guide-lint.md)) gets one more pattern, for every package except `packages/icons` itself:

```ts
patterns: [
  // …the @pkg/db pattern
  {
    group: ["@phosphor-icons/*", "@phosphor-icons/**"],
    message: "Import icons from @pkg/icons.",
  },
],
```

`apps/api` renders no UI, so it needs no icon rule.

## Adding a library icon

1. Find it at [phosphoricons.com](https://phosphoricons.com). The site shows the bare name (`House`); the export is `HouseIcon`, from `@phosphor-icons/react/House`.
2. Add one line to `src/index.ts`, in alphabetical order.
3. Import it from `@pkg/icons` where it is used.

One name per icon. Do not alias an icon to a product name (`export { RocketLaunchIcon as LaunchIcon }`): the package lists what the icons are, and the code that uses them says what they mean.

## Adding a custom icon

A brand mark or an icon Phosphor lacks. Draw it on Phosphor's 256 × 256 grid, so it lines up with its neighbours, and build it on `IconBase`, so it takes the same props (`size`, `weight`, `color`, `mirrored`) and the same `Icon` type:

```tsx
// src/icons/logo-mark.tsx
import type { Icon, IconWeight } from "@phosphor-icons/react";
import { IconBase } from "@phosphor-icons/react/lib";
import { forwardRef, type ReactElement } from "react";

const weights = new Map<IconWeight, ReactElement>([
  ["regular", <path d="M128 24 …" key="regular" />],
  ["fill", <path d="M128 24 …" key="fill" />],
]);

/** The product's logo mark. Has regular and fill weights only. */
export const LogoMarkIcon: Icon = forwardRef((props, ref) => (
  <IconBase ref={ref} {...props} weights={weights} />
));
LogoMarkIcon.displayName = "LogoMarkIcon";
```

```ts
// src/index.ts
export { LogoMarkIcon } from "./icons/logo-mark";
```

- **`viewBox` is fixed at `0 0 256 256`** by `IconBase`. Scale the source SVG to that grid; do not pass a different `viewBox`.
- **Each weight is one entry.** A weight the map lacks renders an empty `<svg>`. Supply every weight the apps use, and say which ones exist in the doc comment.
- **`fill="currentColor"`** is set by `IconBase`. Strip hard-coded `fill` and `stroke` colours from the paths so the icon follows the text colour.
- **`forwardRef` is deliberate.** Phosphor's `Icon` type is a forwardRef component; using it lets a custom icon go into the same `Record<…, Icon>` maps as library icons.
- **Import `IconBase` from `@phosphor-icons/react/lib`,** not the root, for the same reason as the per-icon subpaths. This file is inside `packages/icons`, so the lint rule does not apply.

## Using icons

```tsx
import { ArrowUpRightIcon, type Icon, XLogoIcon } from "@pkg/icons";

<Button render={<a href={url} />}>
  Open
  <ArrowUpRightIcon aria-hidden />
</Button>

<IconButton aria-label="Remove image">
  <XIcon aria-hidden />
</IconButton>

const PLATFORM_ICONS: Record<Platform, Icon> = { x: XLogoIcon, /* … */ };
```

- **Decorative by default.** An icon beside text gets `aria-hidden`. An icon-only control is named by its control (`aria-label`, or `sr-only` text), not by the icon.
- **`alt` only for an icon that stands alone and means something,** with no control around it. It renders a `<title>` inside the `<svg>`.
- **Size from CSS or `size`.** With no `size` prop and no `IconContext`, the `<svg>` has no width or height, so the parent's CSS sizes it (shadcn buttons size child `svg`s). Use `className="size-6"` or `size={24}` when there is no such parent. Do not mix the two on one icon.
- **Colour from the text.** Icons fill with `currentColor`; set the text colour on the icon or its parent. Use the `color` prop only for a colour the design tokens cannot express.
- **`weight`** (`thin`, `light`, `regular`, `bold`, `fill`, `duotone`) picks the drawing. `regular` is the default; use `fill` for selected or emphasised states.
- **`Icon` for maps and props.** A component that takes an icon takes `Icon` (the component), not a rendered element, so it can set the props itself.
- **No `IconContext` provider by default.** Add one at the app root only if the whole product changes its default weight or size; it is one more thing to know when an icon looks wrong.

Icons render on the server. The default (non-SSR) Phosphor build works in SSR because it reads `IconContext` only for defaults; do not switch to the `ssr` entry.

## `packages/ui` and shadcn

shadcn writes components that import `lucide-react` directly (`iconLibrary: "lucide"` in `components.json`, see [`guide-ds.md`](./guide-ds.md)). That output lives in `packages/ui/src/shadcn/`, is vendored, and is excluded from lint, so its Lucide imports stay as the CLI wrote them. Rewriting them would be undone by the next `shadcn add`.

Everything else in `packages/ui` (hand-written components, stories) imports from `@pkg/icons` like the apps, and `packages/ui` lists `@pkg/icons` as a dependency once it has one such import. Lucide never appears outside `packages/ui/src/shadcn/`.

## Changing the icon library

Because nothing outside `packages/icons` names the library, a swap is contained to it:

1. Re-export each current name from the new library's equivalent, keeping the export names, or rename in one commit with every consumer.
2. Re-export `Icon`, `IconProps` and `IconWeight` as types with the same shape, or adapt the custom icons and consumers that use them.
3. Rebuild each custom icon on the new library's base component.
4. Point the lint pattern at the new library's package name.
5. Look at every screen: different libraries draw at different optical sizes.

## Checklist

- [ ] `packages/icons` exists only when an app or package renders an icon.
- [ ] `@phosphor-icons/react` is pinned exactly and is a dependency of `packages/icons` only.
- [ ] `src/index.ts` exports the `Icon`, `IconProps` and `IconWeight` types, then one sorted line per icon in use, each from its per-icon subpath and by its `*Icon` name.
- [ ] No icon in `src/index.ts` is unused, and no icon is exported twice under different names.
- [ ] Each custom icon is one file in `src/icons/`, built on `IconBase` from `@phosphor-icons/react/lib`, on the 256 grid, with no hard-coded colours, typed as `Icon`.
- [ ] Every consumer lists `"@pkg/icons": "workspace:*"`.
- [ ] The `no-restricted-imports` pattern bans `@phosphor-icons/*` in every package but `packages/icons`, and `oxc/no-barrel-file` is off for `packages/icons/src/index.ts`.
- [ ] Lucide appears only in `packages/ui/src/shadcn/`.
- [ ] Icons beside text are `aria-hidden`; icon-only controls carry an accessible name.

## Why it's built this way

| Decision | Why |
| --- | --- |
| A package, not a folder in `apps/main` | `packages/ui` and the blog need the same icons; a package is the only place both can import from. |
| Re-export, not wrap | Phosphor's components already take the props we need. A wrapper would be a pass-through to maintain. |
| Only icons in use | `index.ts` doubles as the inventory: one file shows every icon the product draws, so a designer can review the set and a duplicate is easy to spot. |
| Per-icon subpaths | The dev server loads one module per icon instead of the whole library, and the import says exactly which drawing ships. |
| Phosphor | Six weights from one set, a consistent 256 grid, and a base component that makes custom icons first-class. |
| Lint rule, not convention | A direct import works and looks harmless in review; only the rule keeps the set in one place. |
| Lucide left in vendored shadcn | Fighting the generator costs more than a second library inside one folder that nobody edits by hand. |

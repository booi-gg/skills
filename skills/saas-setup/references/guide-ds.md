---
version: 1.0.0
---

# Set up the design-system package

Build a shared `packages/ds` package, taking the new project's name, visual tokens, fonts, and required components from that project. The result is a private workspace package consumed directly from TypeScript source. It owns reusable UI, its theme, and its Storybook; applications own product screens and app-shell CSS.

## Outcome

Finish with this boundary:

```text
workspace root
├── package.json
├── pnpm-workspace.yaml
├── packages/
│   ├── ds/
│   │   ├── .storybook/
│   │   │   ├── main.ts
│   │   │   ├── preview.css
│   │   │   └── preview.ts
│   │   ├── src/
│   │   │   ├── components/
│   │   │   │   ├── index.ts
│   │   │   │   └── <component>.tsx
│   │   │   ├── labs/
│   │   │   │   └── index.ts
│   │   │   ├── lib/
│   │   │   │   ├── index.ts
│   │   │   │   └── utils.ts
│   │   │   ├── fonts/                  optional self-hosted fonts
│   │   │   ├── styles/
│   │   │   │   ├── ds.css              imports only
│   │   │   │   ├── tokens.css          tier 1: primitives
│   │   │   │   ├── semantic.css        tier 2: roles + tones
│   │   │   │   ├── theme.css           tier 3: Tailwind registration
│   │   │   │   ├── base.css            element defaults
│   │   │   │   └── overrides.css       portal pieces with no className hook
│   │   │   ├── index.ts
│   │   │   └── vite-env.d.ts
│   │   ├── stories/
│   │   │   └── <component>.stories.tsx
│   │   ├── components.json
│   │   ├── package.json
│   │   └── tsconfig.json
│   └── typescript-config/
│       └── base.json
└── apps/
    └── <consumer>/
        ├── src/styles/globals.css
        ├── package.json
        └── vite.config.ts
```

The setup is complete when:

- the DS package typechecks;
- Storybook builds and renders styled components;
- a consumer imports JavaScript from the package root;
- a consumer imports CSS from the explicit CSS subpath;
- Tailwind generates utilities used inside both the DS source and consumer source;
- a component can be added through shadcn, adapted, exported, documented, and consumed without a deep import.

## Establish the boundary first

Inspect the target workspace before changing files. Resolve these facts from existing config; ask only when the repository cannot answer them:

- package scope and name, such as `@acme/ds`;
- workspace glob and package manager;
- React, TypeScript, Vite, and Tailwind major versions;
- shared TypeScript config location;
- first consumer application;
- whether the package is private source code or a published compiled library;
- visual tokens and font source;
- which components are actually needed now.

Use this guide unchanged for a private monorepo package compiled by its consumer. A publishable package is a different boundary: it needs a build output, declaration emission, published CSS handling, an externalization policy, and `exports` pointing to `dist`. Confirm that architecture before adapting this guide.

## Reference architecture studied

The reference package has these defining choices:

| Concern | Choice |
| --- | --- |
| Package | private ESM workspace package named `@acme/ds` |
| Distribution | exports `src/index.ts` directly; no DS build artifact |
| React | peer dependency and dev dependency |
| Styling | Tailwind CSS v4, CSS-first configuration |
| Theme | three tiers: primitives (`tokens.css`) → roles (`semantic.css`) → Tailwind registration (`theme.css`) |
| shadcn | `base-nova`, Base UI, CSS variables, Lucide icons, no RSC |
| Components | typed wrappers, `data-slot`, `className` override via `cn` |
| Variants | `class-variance-authority` only when a real variant matrix exists |
| Public API | `src/components/index.ts` → `src/index.ts` |
| Experimental UI | `src/labs`, still exported through the package root |
| Docs | colocated package-level Storybook with stories outside `src` |
| Consumer | imports `@scope/ds` and `@scope/ds/ds.css` |

These choices are coupled. In particular, direct source exports make `@source "."` and consumer-side Tailwind/Vite compilation essential.

## 1. Register the workspace package

The root workspace must include `packages/*`:

```yaml
# pnpm-workspace.yaml
packages:
  - "apps/*"
  - "packages/*"
```

Create `packages/ds/package.json`. Match versions already used by the target repository. The versions below are the known-good snapshot from September 2026; they are a fallback, not an instruction to downgrade or duplicate another workspace version.

```json
{
  "name": "@your-scope/ds",
  "version": "0.0.0",
  "private": true,
  "type": "module",
  "exports": {
    ".": "./src/index.ts",
    "./ds.css": "./src/ds.css"
  },
  "imports": {
    "#components/*": "./src/components/*.tsx",
    "#lib/*": "./src/lib/*.ts",
    "#hooks/*": "./src/hooks/*.ts"
  },
  "scripts": {
    "storybook": "storybook dev -p 6006",
    "build-storybook": "storybook build",
    "typecheck": "tsc --noEmit"
  },
  "dependencies": {
    "@base-ui/react": "^1.5.0",
    "class-variance-authority": "^0.7.1",
    "cn": "^0.3.0",
    "lucide-react": "^1.16.0"
  },
  "devDependencies": {
    "@storybook/addon-docs": "^10.6.0",
    "@storybook/react-vite": "^10.6.0",
    "@tailwindcss/vite": "4.3.3",
    "@types/react": "^19.2.14",
    "@types/react-dom": "^19.2.3",
    "react": "^19.2.6",
    "react-dom": "^19.2.6",
    "shadcn": "^4.21.0",
    "storybook": "^10.6.0",
    "tailwindcss": "4.3.3",
    "tw-animate-css": "1.4.0",
    "typescript": "~6.0.2"
  },
  "peerDependencies": {
    "react": "^19.0.0",
    "react-dom": "^19.0.0"
  }
}
```

Add runtime dependencies only when an included component uses them:

| Dependency | Used for |
| --- | --- |
| `@base-ui/react` | accessible input, button, checkbox, dialog, popover, switch, context menu primitives |
| `class-variance-authority` | typed visual variants |
| `cn` | Tailwind-aware class composition |
| `lucide-react` | icons |
| `vaul` | drawer primitives |
| `input-otp` | OTP behavior and slot context |
| `sonner` | toast runtime |
| `next-themes` | theme-aware Sonner wrapper; omit if the app has no matching provider |
| `gsap`, `@gsap/react` | the animated side drawer; omit when unused |

Runtime imports belong in `dependencies`. React remains a peer so the app and DS share one React instance; it is also a dev dependency so Storybook and typechecking work inside the package.

Add the consumer dependency:

```json
{
  "dependencies": {
    "@your-scope/ds": "workspace:*"
  }
}
```

Expose the package's common tasks from the root when the workspace uses root-level orchestration:

```json
{
  "scripts": {
    "storybook": "pnpm --filter @your-scope/ds storybook",
    "typecheck": "vp run -r typecheck"
  }
}
```

The package needs no `build` task in this source-distributed architecture. Its meaningful pipeline task is `typecheck`; Storybook has its own explicit build command.

## 2. Configure TypeScript

Extend the workspace's strict base config. The DS override must use DOM types, React JSX, bundler resolution, and include Storybook files:

```json
{
  "extends": "../typescript-config/base.json",
  "compilerOptions": {
    "target": "ES2023",
    "lib": ["ES2023", "DOM"],
    "module": "ESNext",
    "moduleResolution": "Bundler",
    "moduleDetection": "force",
    "noEmit": true,
    "jsx": "react-jsx",
    "verbatimModuleSyntax": true,
    "noUnusedLocals": true,
    "noUnusedParameters": true,
    "erasableSyntaxOnly": true,
    "noFallthroughCasesInSwitch": true,
    "resolvePackageJsonImports": true
  },
  "include": ["src", "stories", ".storybook/**/*"]
}
```

Keep `vite-env.d.ts` when Vite types are needed:

```ts
/// <reference types="vite/client" />
```

`moduleResolution: "Bundler"` is deliberate: package `imports`, source exports, CSS imports, and Vite resolution are bundler concerns. Do not inherit a Node-only resolver here.

## 3. Create the internal and public import surfaces

The internal class utility is a single source of truth:

```ts
// src/lib/utils.ts
export { cn } from "cn";
```

```ts
// src/lib/index.ts
export { cn } from "./utils";
```

Use three API layers:

```ts
// src/components/index.ts
export { Button } from "./button";
export { Typography } from "./typography";
```

```ts
// src/labs/index.ts
export * from "./button-with-loader";
```

```ts
// src/index.ts
export * from "./components";
export * from "./labs";
export * from "./lib";
```

Apply these import rules:

- Package consumers import runtime UI and public types from `@your-scope/ds`.
- Package consumers import global styles once from `@your-scope/ds/ds.css`.
- Component files import siblings and internal utilities relatively; they do not import their own public barrel.
- shadcn may use `#components/*` and `#lib/*` while generating files inside the package.
- Export only supported public components and types. A type needed by consumers is exported explicitly with `type`.
- A new stable component is not complete until `src/components/index.ts` exports it.
- A provisional composed component can start in `src/labs`; promote it when its API is stable.

The public barrel is intentional even if a generic performance lint rule warns about barrels. It defines the package boundary. Configure a narrow lint exception for this file if warning-free CI requires it; do not replace consumer imports with deep paths.

## 4. Set up Tailwind CSS v4 and the theme

There is no `tailwind.config.js`. Tailwind v4 configuration lives in CSS, and Vite loads the Tailwind plugin.

The theme is three tiers of tokens, one file each, under `src/styles/`. `ds.css` only imports them:

```css
/* src/styles/ds.css: the consumer imports "tailwindcss" before this file. */
@import "tw-animate-css";
@import "shadcn/tailwind.css";
@import "./tokens.css"; /* tier 1: primitives */
@import "./semantic.css"; /* tier 2: roles + tones */
@import "./theme.css"; /* tier 3: Tailwind registration */
@import "./base.css"; /* element defaults, reduced motion */
@import "./overrides.css"; /* portal pieces with no className hook */

@source "..";
```

| Tier | File | Holds | Read by |
| --- | --- | --- | --- |
| 1. Primitives | `tokens.css` | Raw values in `:root`, named for what they are: `--cobalt: #2e4e9e`, `--type-label-size: 12px`, `--stroke-sm: 2px`, `--space-unit: 0.25rem` | `semantic.css` and `theme.css` only |
| 2. Semantic | `semantic.css` | Roles in `:root`, each pointing at a primitive: `--text-1: var(--ink)`. Tones (`.tone-inverse`) override roles here and nowhere else | `theme.css`, tone classes |
| 3. Tailwind | `theme.css` | `@theme` / `@theme inline` entries that only map names (`--color-text-1: var(--text-1)`). No literal values except `--breakpoint-*`, which Tailwind compiles into `@media`, where `var()` can't resolve | Tailwind, which generates the utilities |

### Naming

Tailwind theme names are `--<namespace>-<role>-<n>`, so the utilities read as role plus step:

| Kind | Theme variable | Utility | Steps |
| --- | --- | --- | --- |
| Text colour | `--color-text-1` | `text-text-1` | `1` body · `2` secondary · `3` hints · `4` placeholder · `inverse` on an accent fill |
| Background | `--color-surface-1` | `bg-surface-1` | `1` page ground · `2` cards, inputs · `3` focused field · `4` muted fill |
| Border colour | `--color-edge-1` | `border-edge-1` | `1` hairline · `2` strong, default, focus · `3` invalid · `4` soft |
| Brand fill | `--color-accent-1` | `bg-accent-1`, `text-accent-2` | `1` primary · `2` secondary · `-deep` hover/pressed |
| Fixed colour | `--color-black` | `shadow-black`, `bg-white` | `black` · `white`; the same under every tone and brand theme |
| Border width | `--border-width-sm` | `border-sm`, `border-t-sm` | `xs` 1px · `sm` 2px · `md` 3px · `lg` 4px |
| Spacing | `--spacing` (one unit) | `p-1`, `gap-4`, `h-14` | Tailwind's numeric scale: `n` × 4px |

Any role works with any colour utility (`ring-edge-2`, `bg-text-1`, `border-accent-2`), but pick the family that matches what is being coloured: `bg-*` reaches for `surface-*`, `border-*` for `edge-*`.

### Rules

- **Components use only the colours `theme.css` registers.** `theme.css` starts with `--color-*: initial`, so Tailwind's palette (`bg-red-500`, `bg-white`) and the primitives (`bg-cobalt`) produce no CSS. No hex or `var(--primitive)` in arbitrary values either; use `var(--<role>)`.
- **Register colours with `@theme inline`.** A plain `@theme` entry resolves `var(--text-1)` once on `:root`, and descendants inherit that resolved colour. A tone that overrides `--text-1` would then never reach `text-text-1`. `inline` puts `var(--text-1)` into the utility itself.
- **Scales use plain `@theme`.** This covers type, spacing, radius, shadow and stroke. They don't change per tone, and a plain entry keeps a real variable on `:root` for arbitrary values (`rounded-[var(--radius-md)]`).
- **Tones override tier 2 only.** For example, `.tone-inverse { --surface-1: var(--cobalt); --text-1: var(--field); }`. Never override a `--color-*` theme variable or a primitive.
- **Plain `:root` for anything that must not become a utility.** In `@theme`, the prefix decides what a variable does: `--text-*` is a font size, `--color-*` is a colour. `:root` variables generate nothing.
- **Teach `cn` every custom value that shares a prefix with a Tailwind group** (`src/lib/utils.ts`). Otherwise it drops `text-label` next to `text-text-1`, or `border-sm` next to `border-edge-2`.

### Adding a token

1. Add the raw value to `tokens.css` under a name that says what it is.
2. If components will colour something with it, add a role to `semantic.css`, plus a tone override if it should flip.
3. Register it in `theme.css`, colours under `@theme inline`.
4. Add it to the colour swatches in `stories/foundations.stories.tsx`.

### shadcn output

shadcn generates its own vocabulary (`bg-primary`, `ring-ring`, `border-input`). `theme.css` registers none of it, so `scripts/shadcn-add.mjs` runs `scripts/ds-classes.mjs` on every generated primitive. It rewrites those names onto the roles, and `border` / `border-2` onto `border-xs` / `border-sm`. When shadcn adds a name the map doesn't cover, extend the map in `ds-classes.mjs`; don't register shadcn's name.

Put a global override in `overrides.css` only when a portal or third-party library cannot be styled from the component.

### Consumer CSS

The consumer's global stylesheet must import Tailwind before the DS stylesheet and before normal CSS rules:

```css
@import "tailwindcss";
@import "@your-scope/ds/ds.css";

/* App-shell tokens, keyframes, and layout rules follow. */
```

This order gives the DS access to Tailwind and shadcn layers while keeping app-specific CSS outside the shared package. Import the stylesheet once at the application root, not from individual components.

The consumer Vite config must include Tailwind:

```ts
import tailwindcss from "@tailwindcss/vite";
import { defineConfig } from "vite";

export default defineConfig({
  plugins: [tailwindcss()],
});
```

Do not add a PostCSS or Tailwind config file unless another target tool actually requires it.

## 5. Choose and load fonts once

Font files and font tokens are separate responsibilities:

- `--font-*` tokens name the families used by components.
- The application document loads those families for production.
- Storybook loads the same families in `preview.css` because it has a separate document.

For remote fonts, add preconnect and stylesheet links through the consumer framework's document/head API. Storybook can use:

```css
@import url("https://fonts.googleapis.com/css2?family=Bricolage+Grotesque:opsz,wght@12..96,200..800&family=Caveat:wght@400;600&family=Space+Mono:wght@400;700&display=swap");
```

For self-hosted fonts, add `@font-face` declarations and ensure both the consumer build and Storybook can resolve the asset URLs. Choose one strategy. Do not keep unused local font files while runtime CSS loads different remote families.

## 6. Configure shadcn for the package

Place `components.json` at `packages/ds/components.json`:

```json
{
  "$schema": "https://ui.shadcn.com/schema.json",
  "style": "base-nova",
  "rsc": false,
  "tsx": true,
  "tailwind": {
    "config": "",
    "css": "src/ds.css",
    "baseColor": "neutral",
    "cssVariables": true,
    "prefix": ""
  },
  "aliases": {
    "components": "#components",
    "utils": "#lib/utils",
    "ui": "#components",
    "lib": "#lib",
    "hooks": "#hooks"
  },
  "iconLibrary": "lucide"
}
```

Why each choice matters:

- `base-nova` generates against Base UI, matching the package's primitive layer.
- `rsc: false` matches the Vite/TanStack consumer. Reconsider it for a Next.js RSC package.
- an empty Tailwind config is correct for Tailwind v4 CSS-first setup;
- `cssVariables: true` makes generated components consume the semantic theme;
- aliases match `package.json#imports`, so generated internal imports resolve;
- `ui` and `components` intentionally point to the same directory;
- `#hooks/*` is reserved for generated hooks and does not require an empty folder in advance.

From the workspace root, the package-local command shape is:

```sh
pnpm --filter @your-scope/ds exec shadcn add <component>
```

Treat generated code as a starting point. After every add:

1. inspect the generated runtime dependencies and keep them in the DS package;
2. confirm imports resolve through the configured aliases;
3. confirm `ds-classes.mjs` rewrote every colour onto a registered role (see §4, shadcn output);
4. retain the primitive's accessibility and state attributes;
5. add stable `data-slot` names to the public pieces;
6. preserve `className` as the final style override;
7. export the supported API from `src/components/index.ts`;
8. add a Storybook story covering interaction and states;
9. typecheck the package and build Storybook.

## 7. Follow the component contract

Use the smallest of these shapes that fits.

### Native or primitive wrapper

```tsx
import { Input as InputPrimitive } from "@base-ui/react/input";
import type { ComponentProps } from "react";

import { cn } from "../lib/utils";

function Input({ className, ...props }: ComponentProps<"input">) {
  return (
    <InputPrimitive
      data-slot="input"
      className={cn(
        "border-input bg-surface text-type rounded-xl border-[1.5px]",
        "focus-visible:border-ring focus-visible:ring-ring/20 focus-visible:ring-3",
        "disabled:cursor-not-allowed disabled:opacity-50",
        className
      )}
      {...props}
    />
  );
}

export { Input };
```

Extend the underlying element or primitive props instead of manually recreating them. Keep default classes first, state classes next, caller `className` last, and spread remaining props onto the rendered primitive.

### Variant component

Use CVA when variants form a real, reusable matrix:

```tsx
import { cva, type VariantProps } from "class-variance-authority";
import type { ComponentProps } from "react";

import { cn } from "../lib/utils";

const badgeVariants = cva("inline-flex items-center", {
  variants: {
    tone: {
      neutral: "bg-surface-raised text-type",
      danger: "bg-danger/10 text-danger",
    },
  },
  defaultVariants: { tone: "neutral" },
});

type TBadgeProps = ComponentProps<"span"> & VariantProps<typeof badgeVariants>;

function Badge({ className, tone, ...props }: TBadgeProps) {
  return (
    <span
      data-slot="badge"
      className={cn(badgeVariants({ tone }), className)}
      {...props}
    />
  );
}

export { Badge };
export type { TBadgeProps };
```

Use a plain union and conditional classes for one small component-specific branch. Do not introduce CVA for a single boolean.

### Compound component

Expose separately named pieces when callers need composition, as with `Card`, `Dialog`, `Drawer`, or `InputOTP`. Keep behavior in the accessible third-party root and style each public piece. Export the set together from the component file and public barrel.

### Typography composition

Labels and captions should reuse `Typography` rather than reimplement its font rules:

```tsx
type TFieldLabelProps = Omit<
  ComponentProps<typeof Typography>,
  "as" | "variant"
> & {
  htmlFor?: string;
};

function FieldLabel({ className, ...props }: TFieldLabelProps) {
  return (
    <Typography
      as="label"
      variant="caption"
      weight="medium"
      data-slot="field-label"
      className={cn("mb-2 block", className)}
      {...props}
    />
  );
}
```

### Component invariants

- Components are reusable UI primitives; product data, routing, network calls, and feature copy stay in the app.
- Files use kebab case; exported React components use PascalCase.
- Every meaningful public element gets a stable `data-slot`.
- Preserve native and primitive accessibility semantics.
- Use only registered role colours (`text-text-*`, `bg-surface-*`, `border-edge-*`, `*-accent-*`): no palette names, no hex.
- Include hover, focus-visible, disabled, invalid, open/closed, and reduced-motion behavior when applicable.
- Use `sr-only` text for icon-only controls.
- Compose primitives rather than wrapping away their APIs.
- Import directly inside the package to avoid cycles through its own barrel.
- Add an abstraction only after a real repeated contract exists.

## 8. Configure Storybook

Use React-Vite Storybook inside the package. `packages/ds/.storybook/main.ts`:

```ts
import { defineMain } from "@storybook/react-vite/node";
import tailwindcss from "@tailwindcss/vite";

export default defineMain({
  stories: ["../stories/**/*.stories.@(ts|tsx)"],
  addons: ["@storybook/addon-docs"],
  framework: {
    name: "@storybook/react-vite",
    options: {},
  },
  viteFinal(config) {
    config.plugins = [...(config.plugins ?? []), tailwindcss()];
    return config;
  },
});
```

`packages/ds/.storybook/preview.css`:

```css
/* Load the same fonts as the consumer above these imports. */
@import "tailwindcss";
@import "../src/ds.css";

/* Stories live outside src, so add their source explicitly. */
@source "../stories";

html,
body,
#storybook-root {
  min-height: 100%;
}

body {
  margin: 0;
  background: var(--color-surface);
  color: var(--color-type);
  font-family: var(--font-sans);
}
```

`packages/ds/.storybook/preview.ts`:

```ts
import type { Preview } from "@storybook/react-vite";

import "./preview.css";

const preview: Preview = {
  tags: ["autodocs"],
  parameters: {
    layout: "centered",
    controls: {
      matchers: {
        color: /(background|color|tint)$/i,
        date: /Date$/i,
      },
    },
    backgrounds: {
      options: {
        body: { name: "Body", value: "#141310" },
      },
    },
    options: {
      storySort: {
        order: ["Foundations", "Components", "Feedback", "Overlays"],
      },
    },
  },
};

export default preview;
```

Write one story file per public component:

```tsx
import type { Meta, StoryObj } from "@storybook/react-vite";

import { Button } from "../src";

const meta = {
  title: "Components/Button",
  component: Button,
  args: { children: "Create a roll" },
} satisfies Meta<typeof Button>;

export default meta;
type TStory = StoryObj<typeof meta>;

export const Playground: TStory = {};

export const Disabled: TStory = {
  args: { disabled: true },
};
```

Story requirements:

- import stable public APIs from `../src` so stories exercise the package boundary;
- use direct component imports only when Storybook's generic inference cannot represent a third-party discriminated union, and keep that exception local;
- include a playground plus meaningful states and compositions;
- show interactive states for overlays and controlled primitives;
- add decorators only for required context such as theme providers;
- keep product screens out of DS stories;
- use the title groups `Foundations`, `Components`, `Feedback`, and `Overlays` consistently.

The studied package relies on typechecking and stories rather than a package-local unit-test suite. Add focused tests when a component contains state transitions or non-trivial logic that interaction stories do not verify; pure style wrappers do not need ceremonial tests.

## 9. Integrate a consumer

The consumer needs four connections:

1. workspace dependency: `"@your-scope/ds": "workspace:*"`;
2. Tailwind Vite plugin;
3. global CSS imports in the required order;
4. application-level providers needed by selected components.

Use components only through the public API:

```tsx
import { Button, Card, Typography } from "@your-scope/ds";

export function EmptyState() {
  return (
    <Card>
      <Typography variant="heading">No rolls yet</Typography>
      <Button>Create a roll</Button>
    </Card>
  );
}
```

Mount package-wide infrastructure once. For example, a Sonner wrapper using `next-themes` requires the app to provide the matching theme context and render `<Toaster />` near the root. Portal components must be tested inside the real app because stacking contexts and safe-area rules are consumer concerns.

App-specific tokens, layout, route transitions, and product keyframes belong after the DS imports in the consumer's global stylesheet. Promote a style into `ds.css` only when a DS component itself requires it.

## 10. Add a component end to end

For each component request, execute this slice completely:

1. Confirm whether it is a stable primitive (`components`) or provisional composition (`labs`).
2. Choose native HTML, Base UI, or a specialized library for behavior.
3. Add only the runtime dependency that choice requires.
4. Implement typed props, accessibility, semantic tokens, states, `data-slot`, and `className` override.
5. Export every supported runtime symbol and consumer-facing type.
6. Add a Storybook playground and relevant states.
7. Verify the story exercises public imports where TypeScript permits it.
8. Typecheck the DS package.
9. Run the formatter/linter on changed files.
10. Build Storybook for changes involving CSS, portals, aliases, or Storybook config.
11. Render the component from a consumer when integration or global styling changed.

The component is complete only when the consumer can use it without a deep import or local CSS repair.

## Validation

Use the target repository's package manager and scripts. For a workspace shaped like this, the checks are:

```sh
pnpm --filter @your-scope/ds typecheck
vp check packages/ds/src/components/<component>.tsx packages/ds/stories/<component>.stories.tsx
pnpm --filter @your-scope/ds build-storybook
```

When package exports, CSS, dependencies, or providers changed, also run the consumer's typecheck/build. Do not claim success from Storybook alone: TypeScript can pass while Tailwind misses a source directory, and Storybook can pass while the consumer forgot the CSS subpath.

Validate these observable states:

- default, hover, focus-visible, disabled, and invalid where applicable;
- keyboard operation and accessible names;
- light/dark or surface variants actually supported by the project;
- portals above application content;
- animations under reduced motion;
- responsive sizing at the smallest supported viewport;
- consumer import and CSS behavior after a clean build.

## Reference-package drift to avoid copying

The reference package works, but a new project should make these decisions explicitly:

- `packages/ds/src/fonts` contains Arimo and Space Grotesk files, while the active app and Storybook load Bricolage Grotesque, Caveat, and Space Mono remotely. Pick one font strategy and remove the inactive one.
- The package is private and exports raw TypeScript. It is not ready to publish to npm unchanged.
- The `#hooks/*` alias exists before a hooks directory does. This is reserved shadcn capacity, not a requirement to create an empty directory.
- The public component barrel triggers the repository's generic `noBarrelFile` warning. The boundary is intentional; scope the lint exception rather than dissolving the API.
- Some older components contain one-off colors or app-flavored behavior. New components should prefer semantic tokens and remain product-agnostic.
- Specialized dependencies are component-driven. A new package that does not include SideDrawer, Drawer, OTP, or Sonner should not inherit GSAP, Vaul, input-otp, or next-themes automatically.

## Final checklist

- [ ] Package is included by the workspace glob
- [ ] Package is private ESM and exports source plus `./ds.css`
- [ ] React is a peer and a dev dependency
- [ ] Runtime component libraries are package dependencies
- [ ] TypeScript uses bundler resolution and includes stories/config
- [ ] `components.json` points shadcn to `src/ds.css` and package aliases
- [ ] Tailwind v4 is configured through CSS and the Vite plugin
- [ ] `ds.css` includes `@source "."`
- [ ] Consumer imports Tailwind before DS CSS
- [ ] Fonts load in both the app document and Storybook
- [ ] Theme split into `tokens.css` → `semantic.css` → `theme.css`; `--color-*: initial` clears every unregistered colour
- [ ] Components use typed primitive props, role colours only, `data-slot`, and caller class overrides
- [ ] Stable components and public types are exported
- [ ] Storybook covers meaningful states and compositions
- [ ] Consumer providers exist for provider-dependent components
- [ ] DS typecheck, changed-file lint, Storybook build, and consumer integration pass

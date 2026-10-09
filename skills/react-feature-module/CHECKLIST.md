# Checklist

Run `/booi-js-review` and `/ank-code-review` first if installed. This list covers what they can't know about this architecture.

## Scaffold

- [ ] `index.tsx` — resolves infra, inits (SPA) or creates + provides (SSR) the service, starts every page query in parallel, guards loading/error/`undefined`
- [ ] `service.<module>.ts` — accessor functions, variant fallback, frozen `content` keyed by filename; SPA singleton or SSR `createModuleService` + context
- [ ] `config.<module>.ts` — one entry per variant, no copy
- [ ] `constants.<module>.ts` — no functions, no in-module imports
- [ ] `types.<module>.ts` — `typeof`-derived unions, `T<File>Content` per JSON, `TModuleContent`, `TModuleDialog`
- [ ] `events.<module>.ts` — event names only
- [ ] `handlers/` — `request.<module>.ts` helper, one thin wrapper per call, token as param, throws on failure
- [ ] `hooks/queries`, `hooks/mutations`, domain/decorator hooks — token as param
- [ ] `use<Module>.ts` — grouped return, `handlers` namespace, no raw setters
- [ ] `<Module>Content.tsx` — JSX only, dialogs at bottom, heavy dialogs lazy
- [ ] `content/<locale>/*.json` — pure JSON, `{0}` placeholders
- [ ] `utils/`, `pages/`, `components/`, `dialogs/`, `ui/` — only those used
- [ ] No `index.ts` barrel anywhere; every import is a direct file path

## Review — flag any of these

**Layering**
- Content JSON imported anywhere but the service
- On-screen string in config, or behaviour flag in content
- Service initialised or created outside `index.tsx`
- Import pointing outward (handler → hook, hook → component, anything → `index.tsx`)
- Handler or util reading the service
- Barrel `index.ts`, or an import through one

**Structure**
- Handler repeating the call / unwrap / empty-check / throw shape instead of using the request helper
- File that fails the deletion test: one tiny function used once, or a pass-through wrapper
- Util type alias or lookup table copied across files instead of living in one concept file

**SSR**
- Module-level singleton or any module-level mutable state
- `ModuleService.x` instead of `useModuleService().x`
- `track` called during render

**Errors and async**
- Handler that catches and returns `null` or `undefined`
- `mutateAsync` in a click handler without a catch (prefer `mutate` + `onSuccess`)
- Tracking fired before the action succeeds
- Child component starting a query `index.tsx` could have started (waterfall)

**UI**
- `useState`, `useEffect` or async code in the render layer
- Tracking or fetching inside `components/`, `dialogs/` or `ui/`
- `isXOpen` booleans instead of `activeDialog`
- Heavy dialog imported statically
- `value && <X />` where `value` can be a number
- Config or copy drilled through props instead of read from the service
- String concatenation around copy instead of `{0}` placeholders

**Types**
- Literal union retyped by hand instead of `typeof`
- Content type named `*Config`
- `TModuleContent` key that doesn't match a filename

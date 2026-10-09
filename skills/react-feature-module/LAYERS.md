# Layers

Examples use a module called `Module` (`service.module.ts`, `useModule`, `ModuleContent`). Swap in the real name. Swap `formatTemplateString`, `eventTrackingHandler`, `useGetUserToken`, `useAppQueryParam`, `Loader`, `RouteErrorBoundary`, `DrawerDialog` for the project's real pieces and paths.

Examples show the SPA shape. SSR differences are in §2.

No barrels: every import below points at the file directly.

## Contents

1. Entry point — `index.tsx`
2. Service — `service.<module>.ts` (SPA and SSR)
3. Config — `config.<module>.ts`
4. Constants — `constants.<module>.ts`
5. Types — `types.<module>.ts`
6. Events — `events.<module>.ts`
7. Handlers — `handlers/`
8. Hooks — `hooks/`
9. Facade — `use<Module>.ts`
10. Render layer — `<Module>Content.tsx`
11. Utils — `utils/`

---

## 1. Entry point — `index.tsx`

Resolve infra from hooks → `init()` the service → start every page query in parallel → guard → render.

```tsx
const ModuleMain = () => {
  const { getQueryParam } = useAppQueryParam();
  const userToken = useGetUserToken();

  ModuleService.init({
    userToken,
    variant: getQueryParam(MODULE_QUERY_PARAM.VARIANT),
    track: eventTrackingHandler,
  });

  const variant = ModuleService.getVariant();
  const dataQuery = useModuleDataQuery({ userToken, variant });
  const plansQuery = useModulePlansQuery({ userToken });

  if (dataQuery.isLoading || plansQuery.isLoading) {
    return <Loader />;
  }
  if (dataQuery.data === undefined || plansQuery.data === undefined) {
    return <RouteErrorBoundary />;
  }
  return <ModuleContent data={dataQuery.data} plans={plansQuery.data} />;
};

export default ModuleMain;
```

- No business logic. Infra, init, fetch, guards only.
- Every query the page needs starts here, side by side, so they run in parallel. A child that fetches after its parent renders is a waterfall: the second request waits for the first to finish.
- SPA: `init()` runs every render, before any child renders. That keeps the token and variant current after re-login or token refresh.

## 2. Service — `service.<module>.ts`

Holds injected infra, the resolved variant config and the merged content. Pick the shape from the SPA/SSR answer.

### SPA — closure singleton

```ts
import { MODULE_CONFIG } from "./config.module";
import { DEFAULT_MODULE_VARIANT } from "./constants.module";
import cancelPlanCard from "./content/en/cancel-plan-card.json";
import common from "./content/en/common.json";
import type {
  TModuleContent,
  TModuleServiceDeps,
  TModuleServiceState,
  TModuleVariant,
} from "./types.module";

const MODULE_CONTENT = Object.freeze({
  cancelPlanCard,
  common,
} satisfies TModuleContent);

const isModuleVariant = (value: string | undefined): value is TModuleVariant =>
  value !== undefined && Object.hasOwn(MODULE_CONFIG, value);

const createModuleService = () => {
  let state: TModuleServiceState | undefined;

  const init = (deps: TModuleServiceDeps) => {
    const variant = isModuleVariant(deps.variant)
      ? deps.variant
      : DEFAULT_MODULE_VARIANT;
    state = Object.freeze({ ...deps, variant, config: MODULE_CONFIG[variant] });
  };

  const read = () => {
    if (state === undefined) {
      throw new Error("ModuleService used before init()");
    }
    return state;
  };

  return Object.freeze({
    init,
    getUserToken: () => read().userToken,
    getVariant: () => read().variant,
    getConfig: () => read().config,
    track: (...args: Parameters<TModuleServiceDeps["track"]>) =>
      read().track(...args),
    content: MODULE_CONTENT,
  });
};

export const ModuleService = createModuleService();
export type TModuleService = typeof ModuleService;
```

- Accessor functions, not getters. Reading before `init()` throws instead of returning `undefined`.
- An unknown or missing variant falls back to `DEFAULT_MODULE_VARIANT`. A config lookup never comes back `undefined`.
- `content` is static, so it is readable before `init()`.
- Mutable state lives only in `state`, and only `init()` writes it.

### SSR — per-render service through context

On the server, module state is shared by every request. A singleton holding `userToken` would serve one user's token to another user's render. So the service is created per render and passed down through context; nothing is mutable at module level.

```ts
// service.module.ts — same imports, MODULE_CONTENT and isModuleVariant as above
export const createModuleService = (deps: TModuleServiceDeps) => {
  const variant = isModuleVariant(deps.variant)
    ? deps.variant
    : DEFAULT_MODULE_VARIANT;
  const state = Object.freeze({ ...deps, variant, config: MODULE_CONFIG[variant] });

  return Object.freeze({
    getUserToken: () => state.userToken,
    getVariant: () => state.variant,
    getConfig: () => state.config,
    track: state.track,
    content: MODULE_CONTENT,
  });
};

export type TModuleService = ReturnType<typeof createModuleService>;

const ModuleServiceContext = createContext<TModuleService | undefined>(undefined);

export const ModuleServiceProvider = ModuleServiceContext.Provider;

export const useModuleService = () => {
  const service = useContext(ModuleServiceContext);
  if (service === undefined) {
    throw new Error("useModuleService used outside ModuleServiceProvider");
  }
  return service;
};
```

```tsx
// index.tsx — create, provide, then fetch and guard as in §1
const ModuleMain = () => {
  const { getQueryParam } = useAppQueryParam();
  const userToken = useGetUserToken();
  const variantParam = getQueryParam(MODULE_QUERY_PARAM.VARIANT);

  const service = useMemo(
    () =>
      createModuleService({
        userToken,
        variant: variantParam,
        track: eventTrackingHandler,
      }),
    [userToken, variantParam],
  );

  const dataQuery = useModuleDataQuery({ userToken, variant: service.getVariant() });
  // ...guards as in §1

  return (
    <ModuleServiceProvider value={service}>
      <ModuleContent data={dataQuery.data} />
    </ModuleServiceProvider>
  );
};
```

- No `init()`. `index.tsx` is still the only place the service is created.
- Everywhere the SPA examples read `ModuleService.x`, SSR reads `useModuleService().x`. Hooks and components only — that is why handlers and utils never touch the service.
- `track` only from event handlers, never during render (it would fire on the server).

## 3. Config — `config.<module>.ts`

Behaviour and structure per variant: section flags, limits, defaults, enum references. No copy, no logic.

```ts
export const MODULE_CONFIG = Object.freeze({
  [MODULE_VARIANT.MANAGE]: {
    sections: { statCard: true, addOns: true },
    cart: { allowPromoCode: true, maxItems: 5 },
    defaultBilling: BILLING_INTERVAL.YEARLY,
  },
  [MODULE_VARIANT.CREATE]: {
    sections: { statCard: false, addOns: false },
    cart: { allowPromoCode: false, maxItems: 1 },
    defaultBilling: BILLING_INTERVAL.MONTHLY,
  },
} as const);
```

- Keyed by every member of the variant union.
- Read only through the service's `getConfig()`.

## 4. Constants — `constants.<module>.ts`

```ts
export const MODULE_VARIANT = Object.freeze({
  MANAGE: "manage",
  CREATE: "create",
} as const);

export const DEFAULT_MODULE_VARIANT = MODULE_VARIANT.MANAGE;
export const MODULE_QUERY_PARAM = Object.freeze({ VARIANT: "variant" } as const);
export const MODULE_QUERY_KEY = "module";
export const MODULE_API_URL = SOME_SERVICE_ENDPOINT;
```

- No functions. Imports only from global constants, never from inside the module.

## 5. Types — `types.<module>.ts`

```ts
// domain
export type TModuleItem = { id: string; name: string; priceCents: number };
export type TModuleData = { items: TModuleItem[] };

// derived from constants/config — always typeof, never re-typed literals
export type TModuleVariant = (typeof MODULE_VARIANT)[keyof typeof MODULE_VARIANT];
export type TModuleVariantConfig = (typeof MODULE_CONFIG)[TModuleVariant];

// service
export type TModuleServiceDeps = {
  userToken: string | undefined;
  variant: string | undefined;
  track: typeof eventTrackingHandler;
};
export type TModuleServiceState = Omit<TModuleServiceDeps, "variant"> & {
  variant: TModuleVariant;
  config: TModuleVariantConfig;
};

// handlers
export type TModuleRequestParams = {
  path: string;
  userToken: string | undefined;
  method?: "get" | "post" | "put" | "patch" | "delete";
  query?: Record<string, string>;
  body?: unknown;
};
export type TGetModuleDataParams = {
  userToken: string | undefined;
  variant: TModuleVariant;
};

// content — one type per JSON file, hand-written (see CONTENT.md)
export type TCancelPlanCardContent = { title: string; keepAllNote: string };
export type TModuleContent = {
  cancelPlanCard: TCancelPlanCardContent;
  common: TCommonContent;
};

// dialogs
export type TModuleDialog = "none" | "confirm" | "success";
```

- Content types end in `Content`, never `Config`.

## 6. Events — `events.<module>.ts`

```ts
export const MODULE_EVENTS = Object.freeze({
  ITEM_ADDED: "module_item_added",
  SUBMITTED: "module_submitted",
} as const);
```

## 7. Handlers — `handlers/`

One shared request helper, then one thin file per API operation, named for it (`get*`, `create*`, `update*`, `delete*`).

```ts
// handlers/request.module.ts
export const requestModule = async <TData>(
  params: TModuleRequestParams,
): Promise<TData> => {
  const { path, userToken, method = "get", query, body } = params;
  const response = await axios.request<TApiResponse<TData>>({
    method,
    url: `${MODULE_API_URL}${path}`,
    headers: { Authorization: `Bearer ${userToken}` },
    params: query,
    data: body,
  });
  if (response.data.data === undefined) {
    throw new Error(`${method.toUpperCase()} ${path} returned no data`);
  }
  return response.data.data;
};
```

```ts
// handlers/getModuleData.ts
export const getModuleData = (params: TGetModuleDataParams) => {
  const { userToken, variant } = params;
  return requestModule<TModuleData>({ path: "/data", userToken, query: { variant } });
};
```

- The call, unwrap, empty check and error shape live once, in the helper. Handlers only name the operation and map params.
- The token comes in as a param. Handlers never read the service, so they work in SPA and SSR, and the "must init first" rule is gone from their interface.
- No React, no hooks.
- **Let errors throw.** Don't catch and return `null`: that hides the failure from TanStack Query, so `isError`, retries and `onError` never fire. Catch only to turn an error into a domain error, then rethrow.

## 8. Hooks — `hooks/`

```
hooks/
  queries/       useQuery wrappers
  mutations/     useMutation wrappers
  use<Domain>.ts domain / selector / decorator hooks
```

| Pattern   | Example              | Role                                        |
| --------- | -------------------- | ------------------------------------------- |
| Query     | `useModuleDataQuery` | Wraps `useQuery`, calls a handler           |
| Mutation  | `useSubmitMutation`  | Wraps `useMutation`, calls a handler        |
| Domain    | `useCart`            | Owns a slice of module state                |
| Selector  | `useOrderSummary`    | Read-only data computed from other state    |
| Decorator | `useCartActions`     | Wraps domain actions with tracking          |
| Facade    | `useModule`          | Wires everything for the render layer       |

```ts
export const useModuleDataQuery = (params: TGetModuleDataParams) => {
  const { variant } = params;
  return useQuery({
    queryKey: [MODULE_QUERY_KEY, "data", variant],
    queryFn: () => getModuleData(params),
  });
};

export const useSubmitMutation = () => useMutation({ mutationFn: submitModule });

export const useCartActions = (props: TUseCartActionsProps) => {
  const { cart } = props;

  const addItem = (item: TModuleItem) => {
    cart.addItem(item);
    ModuleService.track(MODULE_EVENTS.ITEM_ADDED, {
      types: ["posthog"],
      properties: { item_id: item.id },
    });
  };

  return { addItem };
};
```

- Query and mutation hooks take the token in their params, like handlers. The caller (`index.tsx` or the facade) reads it from the service.
- The UI gets domain actions from the decorator (`useCartActions`), never straight from the domain hook (`useCart`).

## 9. Facade — `use<Module>.ts`

Wires the domain hooks, mutations and dialog state into one object for the render layer.

```ts
export const useModule = (props: TUseModuleProps) => {
  const { data } = props;

  const cart = useCart({ items: data.items });
  const summary = useOrderSummary({ cart });
  const cartActions = useCartActions({ cart });
  const submitMutation = useSubmitMutation();
  const [activeDialog, setActiveDialog] = useState<TModuleDialog>("none");

  const openDialog = (dialog: TModuleDialog) => setActiveDialog(dialog);
  const closeDialog = () => setActiveDialog("none");

  const submit = () => {
    submitMutation.mutate(
      { userToken: ModuleService.getUserToken(), items: cart.items },
      {
        onSuccess: () => {
          ModuleService.track(MODULE_EVENTS.SUBMITTED, {
            types: ["posthog"],
            properties: { variant: ModuleService.getVariant() },
          });
          setActiveDialog("success");
        },
      },
    );
  };

  return {
    cart,
    summary,
    activeDialog,
    isSubmitting: submitMutation.isPending,
    hasSubmitError: submitMutation.isError,
    handlers: { addItem: cartActions.addItem, openDialog, closeDialog, submit },
  };
};
```

- Returns a named object grouped by concern, not a tuple.
- Mutations come from `hooks/mutations/` and are never built inline.
- `setActiveDialog` stays private. Only `openDialog` and `closeDialog` are exposed.
- Expose derived booleans (`isSubmitting`), not raw query or mutation objects.
- Tracking happens after the action succeeds: decorators track domain actions, facade handlers track module-level actions.

## 10. Render layer — `<Module>Content.tsx`

JSX only.

```tsx
const ConfirmCard = lazy(() => import("./dialogs/ConfirmCard"));

const ModuleContent = (props: TModuleContentProps) => {
  const config = ModuleService.getConfig();
  const copy = ModuleService.content.common;
  const { cart, activeDialog, handlers } = useModule(props);

  return (
    <>
      <h1>{copy.title}</h1>
      {config.sections.statCard ? <StatCard /> : null}
      <CartSection items={cart.items} onAddItem={handlers.addItem} />

      <DrawerDialog isOpen={activeDialog === "confirm"} onClose={handlers.closeDialog}>
        <Suspense fallback={null}>
          <ConfirmCard onConfirm={handlers.submit} />
        </Suspense>
      </DrawerDialog>
    </>
  );
};

export default ModuleContent;
```

- Calls `useModule` once.
- Config and copy come from the service, not from props. Components anywhere in the module do the same.
- Never imports content JSON.
- No `useState`, `useEffect` or async code.
- All dialogs go at the bottom, each gated by `activeDialog === "<key>"`.
- Heavy dialogs (forms, charts, big libraries) load with `lazy` + `Suspense`, so their code downloads only when opened. Small dialogs stay static imports. `lazy` needs a default export.
- Conditional render with a ternary, or a guaranteed boolean. `{items.length && <List />}` renders `0` when the list is empty.

## 11. Utils — `utils/`

Pure functions, grouped by concept: one file per thing they work on (`bundle.ts`, `last-active.ts`), several related functions per file. No React, no I/O, no service, no input mutation.

```ts
// utils/bundle.ts
export const getBundleTotal = (items: TModuleItem[]) =>
  items.reduce((total, item) => total + item.priceCents, 0);

export const getBundleSavings = (items: TModuleItem[], listPriceCents: number) =>
  listPriceCents - getBundleTotal(items);
```

- Deletion test: if a file holds one five-line function used in one place, move it back into its caller.
- Shared type aliases and lookup tables used by several utils live in the same concept file, not copied per file.

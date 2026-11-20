---
version: 2.0.0
---

# Payments

The app sells software: subscriptions and one-time purchases (a lifetime licence, an add-on). Everything goes through one billing module in the api Worker. Business logic calls that module's small API and never names the payment provider. One adapter file talks to the provider (Stripe today; Polar or Paddle later), so a provider swap means writing one new adapter. Read this before adding a product, gating a feature on a plan, touching checkout or webhooks, or changing provider.

Out of scope: physical goods, shipping, marketplaces (sellers paid through the platform), usage-based billing and credit balances. Each needs its own design.

## The shape

```text
business logic ──► features/billing (our API) ──► PaymentProvider ──► integrations/payment/<provider>.ts ──► provider REST API
                        │
                        └── reads our database only; the provider is never asked "does this account have access?"
```

| File | Holds | Knows about |
| --- | --- | --- |
| `packages/shared/src/billing.ts` | the catalog: `PlanId`, `ProductId`, `products`, `planFeatures`, `Access` | nothing |
| `apps/api/src/features/billing/billing.service.ts` | `startCheckout`, `openPortal`, `getAccess`, `hasFeature`, `syncCheckout`, `syncFromWebhook` | the catalog, the database, `PaymentProvider` |
| `apps/api/src/features/billing/billing.route.ts` | `POST /billing/checkout`, `POST /billing/portal`, `GET /billing/access`, `POST /billing/sync` | the service |
| `apps/api/src/features/webhooks/webhooks.route.ts` | `POST /webhooks/payments/:provider` | the service, the provider registry |
| `apps/api/src/integrations/payment/provider.ts` | the `PaymentProvider` interface, its record types, `getProvider`, `activeProvider` | the catalog |
| `apps/api/src/integrations/payment/stripe.ts` | the Stripe adapter | Stripe's API, `env.ts` |
| `apps/main/src/features/billing/` | `useAccess`, `useCheckout`, `usePortal`, the return screen | the api client |

**The rule:** only `integrations/payment/<provider>.ts` knows a provider exists. Business code imports from `features/billing`, never from `integrations/payment`.

## Who pays: `accountId`

Every billing row and call is keyed by `accountId`, a plain string. Today it is the user's id. If teams buy later, it becomes an organisation's id. The type doesn't change, so neither does the API. The billing tables have no foreign key to `users` for the same reason.

## The catalog

Products and plans are code, in `packages/shared`, so both Workers and the pricing page use the same names.

```ts
// packages/shared/src/billing.ts — export it as "./billing" in package.json
export const planFeatures = {
  free: [],
  pro: ["exports", "custom_domain"],
} as const satisfies Record<string, readonly string[]>;

export type PlanId = keyof typeof planFeatures;
export type Feature = (typeof planFeatures)[PlanId][number];

export const products = {
  pro_monthly: { kind: "subscription", plan: "pro" },
  pro_yearly: { kind: "subscription", plan: "pro" },
  pro_lifetime: { kind: "one_time", plan: "pro" },
} as const satisfies Record<string, { kind: "subscription" | "one_time"; plan: PlanId }>;

export type ProductId = keyof typeof products;

export interface Access {
  plan: PlanId;
  source: "free" | "subscription" | "purchase";
  subscription: {
    productId: ProductId;
    status: SubscriptionStatus;
    periodEnd: string; // ISO
    cancelAtPeriodEnd: boolean;
  } | null;
  purchases: ProductId[];
}

export type SubscriptionStatus = "trialing" | "active" | "past_due" | "incomplete" | "canceled";
```

- **Prices live in the provider, not here.** Each adapter maps a `ProductId` to its own price id (see [Env](#env)). Prices shown on the pricing page are copy in its `content/` JSON.
- **Features are the API that business logic uses.** Gate on `hasFeature(access, "exports")`, never on a plan or product name, so repackaging plans touches only `planFeatures`.
- **Renaming a `ProductId`:** don't. Stored rows use it. Add a new one and stop selling the old one.

## The billing API

This is what business logic uses. Keep it this small.

```ts
// apps/api/src/features/billing/billing.service.ts
startCheckout(env, db, { accountId, email, productId, returnUrl }): Promise<{ url: string }>
openPortal(env, db, { accountId, returnUrl }): Promise<{ url: string }>   // cancel, switch plan, card, invoices
getAccess(db, accountId): Promise<Access>                                  // our database only
hasFeature(access: Access, feature: Feature): boolean
```

- **`getAccess` never calls the provider.** Access is read from our tables, which webhooks and the return page keep current. A provider outage can't lock anyone out.
- **Which subscription statuses grant access:** `trialing`, `active` and `past_due`. `past_due` keeps access while the provider retries the card. It ends at `canceled`. `incomplete` (the first payment didn't go through) grants nothing.
- **A paid one-time purchase grants its plan for good.** A fully refunded purchase grants nothing.
- **Best plan wins.** Access is the highest plan among the granting subscription and the paid purchases, and `free` when there is neither.
- **One live subscription per account.** `startCheckout` answers `409 already_subscribed` for a subscription product when a granting subscription exists, and the web app sends the person to the portal to switch plans. A one-time product already owned answers `409 already_purchased`.
- **Payments off:** with the provider's keys missing, `startCheckout` and `openPortal` answer `503 payments_off`. `getAccess` keeps working.
- **No receipts of our own.** The provider emails receipts and invoices. Send our own mail (through `sendMail`, [`guide-mail.md`](./guide-mail.md)) only for product messages such as a welcome.

In the web app, `features/billing` exposes `useAccess()` (a query on `GET /billing/access`), and mutations that call `/billing/checkout` and `/billing/portal` and then set `window.location` to the returned URL. Hide or disable gated UI from `useAccess()`. The api still checks `hasFeature` on every gated endpoint, because the UI check is only cosmetic.

## The provider interface

```ts
// apps/api/src/integrations/payment/provider.ts
export type ProviderName = "stripe"; // add "polar" | "paddle" with their adapters

export interface SubscriptionRecord {
  accountId: string;
  customerRef: string;
  subscriptionRef: string;
  productId: ProductId;
  status: SubscriptionStatus;
  periodEnd: Date;
  cancelAtPeriodEnd: boolean;
}

export interface PurchaseRecord {
  accountId: string;
  customerRef: string;
  purchaseRef: string;
  productId: ProductId;
  amount: number;   // smallest currency unit (cents)
  currency: string; // ISO 4217, lowercase
  status: "paid" | "refunded"; // refunded = fully refunded
}

export type BillingRecord =
  | { kind: "subscription"; record: SubscriptionRecord }
  | { kind: "purchase"; record: PurchaseRecord };

export interface PaymentProvider {
  readonly name: ProviderName;
  createCheckout(input: {
    accountId: string;
    email: string;
    customerRef: string | null; // reuse the customer when the account has one with this provider
    productId: ProductId;
    returnUrl: string;          // the adapter appends its own checkout-ref placeholder
    cancelUrl: string;
  }): Promise<{ url: string }>;
  createPortal(input: { customerRef: string; returnUrl: string }): Promise<{ url: string }>;
  readCheckout(checkoutRef: string): Promise<BillingRecord | null>; // null until it's paid or a subscription exists
  readSubscription(subscriptionRef: string): Promise<SubscriptionRecord>;
  readPurchase(purchaseRef: string): Promise<PurchaseRecord>;
  /** Verifies the signature (throws WebhookSignatureError), then says what changed. Null for events we don't use. */
  parseWebhook(request: Request): Promise<{ kind: "subscription" | "purchase"; ref: string } | null>;
}
```

- **Our words only.** No session, price, PaymentIntent or transaction. Provider ids come back as opaque `*Ref` strings: store them, never parse them.
- **The adapter puts `accountId` (and `productId` for one-time purchases) on the provider's object** at checkout, in its metadata or custom data, and reads them back into the records.
- **Reads return the current state.** Provider objects change (plan switches, cancellations, refunds), so every record comes from a fresh read, never from a webhook payload.

## Keeping our tables current

```ts
// packages/db/src/schema/app.ts (columns, abridged)
billingCustomers: accountId (pk), provider, customerRef      unique (provider, customerRef)
subscriptions:    id, accountId, provider, subscriptionRef, productId, status,
                  periodEnd, cancelAtPeriodEnd, updatedAt     unique (provider, subscriptionRef)
purchases:        id, accountId, provider, purchaseRef, productId, amount, currency,
                  status, updatedAt                           unique (provider, purchaseRef)
```

Two paths write them. Either can arrive first, and both do the same thing.

1. **The webhook only says something changed.** `parseWebhook` returns `{ kind, ref }`. `syncFromWebhook` reads the current state (`readSubscription` or `readPurchase`) and upserts it on `(provider, ref)`. A repeated, late or out-of-order webhook writes the same current state, so it needs no event log or dedupe table. If the read or the write fails, answer `500`: the provider retries.
2. **The return page.** The adapter's return URL carries `provider` and the checkout ref. The web return screen calls `POST /billing/sync`, which runs `readCheckout` and upserts the record, then invalidates `useAccess`. It answers `403` if the record's `accountId` isn't the caller's. That way a customer who lands back before the webhook arrives already sees the new plan.

Every row stores its `provider`. `openPortal` and the syncs use the row's provider, not the active one, so during a provider change old customers keep working while new checkouts go to the new provider.

## Env

| Name | Where | Value |
| --- | --- | --- |
| `PAYMENT_PROVIDER` | `wrangler.jsonc` vars | `stripe`: the provider new checkouts use |
| `PAYMENT_PRICES` | `wrangler.jsonc` vars, per environment | JSON `{ "<ProductId>": "<provider price id>" }`, validated in `env.ts` against `products`: a missing product fails at the boundary |
| `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET` | secrets; `apps/api/.dev.vars` locally | test-mode keys locally, live keys in production |

Price ids aren't secret, and test mode and live mode have different ones, so they're per-environment vars. List every name with a safe placeholder in `.env.example`.

## The Stripe adapter

`integrations/payment/stripe.ts` calls Stripe's REST API with `fetch`, no SDK.

- **Pin the API version.** Send `Stripe-Version` on every call, set to the version current when the adapter is written. Without it the account's default version applies, and that changes when someone upgrades it in the dashboard.
- **Bodies are form-encoded,** with nested keys in brackets (`line_items[0][price]`), not JSON.
- **No POST is retried automatically,** so no `Idempotency-Key` is needed: a failed checkout is the person clicking again. If you add a POST that is retried, give it a key built from our ids.

```ts
type FormValue = string | number | boolean | undefined | FormValue[] | { [key: string]: FormValue };

/** Stripe's form encoding: { a: { b: [1] } } → a[b][0]=1 */
function appendForm(form: URLSearchParams, key: string, value: FormValue): void {
  if (value === undefined) {
    return;
  }
  if (Array.isArray(value)) {
    for (const [index, item] of value.entries()) {
      appendForm(form, `${key}[${index}]`, item);
    }
    return;
  }
  if (typeof value === "object") {
    for (const [name, item] of Object.entries(value)) {
      appendForm(form, key === "" ? name : `${key}[${name}]`, item);
    }
    return;
  }
  form.append(key, String(value));
}
```

| Method | Stripe call | Notes |
| --- | --- | --- |
| `createCheckout` | `POST /v1/checkout/sessions` | `mode` from the product's `kind`. `client_reference_id` and `metadata[accountId]`. `subscription_data[metadata][accountId]` for subscriptions. For one-time products: `payment_intent_data[metadata][accountId]`, `payment_intent_data[metadata][productId]` and `customer_creation=always`. `customer` when there's a `customerRef`, else `customer_email`. `success_url` = return URL + `checkout_ref={CHECKOUT_SESSION_ID}`. |
| `createPortal` | `POST /v1/billing_portal/sessions` | `customer`, `return_url`. Enable plan switching and cancellation in the portal settings. |
| `readCheckout` | `GET /v1/checkout/sessions/:id` | Has `subscription` → `readSubscription`. `mode=payment` and `payment_status=paid` → `readPurchase(payment_intent)`. Otherwise `null`. |
| `readSubscription` | `GET /v1/subscriptions/:id` | Product from `items.data[0].price.id`, mapped back through `PAYMENT_PRICES`. Status: `unpaid` → `past_due`, `incomplete_expired` and `paused` → `canceled`. In recent API versions the period end is on the item (`items.data[0].current_period_end`), not on the subscription. |
| `readPurchase` | `GET /v1/payment_intents/:id?expand[]=latest_charge` | Paid when `status=succeeded`. `refunded` when `latest_charge.refunded` is true (that flag means fully refunded). |
| `parseWebhook` | — | `customer.subscription.created`, `.updated`, `.deleted` → subscription `data.object.id`. `checkout.session.completed` and `.async_payment_succeeded` → purchase `data.object.payment_intent` when `mode=payment`. `charge.refunded` → purchase `data.object.payment_intent`. Anything else → `null`. |

**Verify the signature yourself.** Read the raw body with `request.text()` before any parsing:

```ts
const SIGNATURE_TOLERANCE_SECONDS = 300;
const encoder = new TextEncoder();
const toHex = (bytes: Uint8Array): string => Array.from(bytes, (byte) => byte.toString(16).padStart(2, "0")).join("");

async function isValidStripeSignature(rawBody: string, header: string | null, secret: string): Promise<boolean> {
  const fields = (header ?? "").split(",").map((field) => field.split("="));
  const timestamp = Number(fields.find(([name]) => name === "t")?.[1]);
  const signatures = fields.filter(([name]) => name === "v1").map(([, value]) => value ?? "");
  const isFresh = Number.isFinite(timestamp) && Math.abs(Date.now() / 1000 - timestamp) <= SIGNATURE_TOLERANCE_SECONDS;
  if (!isFresh || signatures.length === 0) {
    return false;
  }
  const key = await crypto.subtle.importKey("raw", encoder.encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const expected = encoder.encode(toHex(new Uint8Array(await crypto.subtle.sign("HMAC", key, encoder.encode(`${timestamp}.${rawBody}`)))));
  return signatures.some((signature) => {
    const given = encoder.encode(signature);
    return given.byteLength === expected.byteLength && crypto.subtle.timingSafeEqual(given, expected);
  });
}
```

`crypto.subtle.timingSafeEqual` is a Workers extension. It throws on unequal lengths, hence the length check first. The `Number.isFinite` guard matters: without it a missing `t` gives `NaN`, the age check never fails, and an old signature would pass.

## Lint boundary

`apps/api` may use a provider SDK only inside its adapter (Polar and Paddle adapters might use one). Add an override in the root `vite.config.ts` in the same shape as [`guide-analytics.md`](./guide-analytics.md#lint-boundary):

```ts
const paymentVendorRule = {
  group: ["stripe", "@polar-sh/*", "@paddle/*"],
  message: "Use features/billing. Only integrations/payment/<provider>.ts talks to a payment provider.",
};
// apps/api/** bans it; apps/api/src/integrations/payment/** allows it.
```

`fetch` calls to the provider's URL can't be linted, so review for them: the provider's hostname appears only in its adapter.

## Adding a product

1. Add it to `products` (and its features to `planFeatures` if it brings a new plan).
2. Create the price in the provider's test and live modes. Add both ids to `PAYMENT_PRICES` per environment.
3. Add its copy to the pricing page's JSON.
4. Done when the check passes and a test-mode checkout for it ends with the right `GET /billing/access`.

## Changing provider

1. Write `integrations/payment/<provider>.ts` implementing `PaymentProvider`, add its name to `ProviderName` and its secrets and price ids to env, and register its webhook at `/webhooks/payments/<provider>`.
2. Set `PAYMENT_PROVIDER` to it. New checkouts go there. Existing rows keep their provider, so their portal and syncs still use the old adapter.
3. Existing subscribers either stay on the old provider until they cancel, or move with the providers' own migration tooling. That is a business task, not code: check what the new provider supports for importing payment methods.
4. Remove the old adapter, its env and its lint group once no `subscriptions` row with a granting status uses it.

Check each provider's current docs while writing its adapter:

| | Stripe | Polar | Paddle |
| --- | --- | --- | --- |
| Merchant of record (they handle sales tax and VAT) | no: you do, or turn on Stripe Tax | yes | yes |
| Checkout | hosted page, redirect | hosted page, redirect | Paddle.js on a page you host. That means a checkout route in `apps/main` loading its script |
| Where `accountId` rides | `metadata` | `metadata` | `custom_data` |
| Portal | Billing portal session | customer portal | customer portal |

## Local testing

1. Put test-mode keys in `apps/api/.dev.vars` and test price ids in the dev `PAYMENT_PRICES`.
2. Forward webhooks. `listen` prints the signing secret for `STRIPE_WEBHOOK_SECRET`:

   ```sh
   stripe listen --forward-to localhost:8787/webhooks/payments/stripe
   ```

3. Buy with `4242 4242 4242 4242`, any future date and any CVC. `4000 0000 0000 0341` attaches but fails on renewal, which produces `past_due`.

Test `billing.service.ts` with a fake `PaymentProvider` (an in-memory object implementing the interface) against local Postgres: the webhook arriving before and after the return page, the same webhook twice, a cancellation, a full refund, a second subscription refused, and access computed from mixed rows. The test refuses any non-localhost database and cleans up after itself.

## Why it's built this way

| Decision | Why |
| --- | --- |
| Our billing API, not the provider's API spread through the app | A provider swap is one new adapter. Business code and tests never change. |
| Access from our database | Fast, works during a provider outage, and testable without the provider. |
| Gate on features, not plans | Plans get repackaged; feature checks in business code don't move. |
| Webhook as a hint, then a fresh read | Order and duplicates stop mattering. No event store, no ordering logic. |
| `provider` on every row | Two providers can run at once, so a migration needs no cutover day. |
| `accountId` as a plain string | Teams can buy later without changing the API. |
| Hosted checkout and portal | No card fields or payment scripts on our pages; plan switching, cancelling and invoices come free. |

## Checklist

- [ ] Every product and plan is in `packages/shared/src/billing.ts`; business code gates with `hasFeature`, never on a plan or product name.
- [ ] Gated api endpoints check `hasFeature(await getAccess(db, accountId), …)`; the web app's check is cosmetic only.
- [ ] Only `integrations/payment/<provider>.ts` calls or imports a provider; the lint rule fails on any other import.
- [ ] `getAccess` reads only our tables.
- [ ] Webhooks verify the signature on the raw body, read fresh state, upsert on `(provider, ref)`, and answer `500` on failure.
- [ ] `POST /billing/sync` refuses a checkout that belongs to another account.
- [ ] Every billing row stores `provider`; portal and syncs use the row's provider.
- [ ] A second subscription or a repeat one-time purchase answers `409`.
- [ ] Missing keys answer `503 payments_off`; `PAYMENT_PRICES` is validated against `products` in `env.ts`.
- [ ] `Stripe-Version` is pinned; `.env.example` lists every payment variable with placeholders.

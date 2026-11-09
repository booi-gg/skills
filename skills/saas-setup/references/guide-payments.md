# Payments

Stripe for a platform where tenants sell to their own customers. Two kinds of money move through it.

| Money | Whose Stripe account | Webhook |
| --- | --- | --- |
| An owner's plan subscription | the platform's | `POST /webhooks/stripe` (`STRIPE_WEBHOOK_SECRET`) |
| A customer paying a tenant | **the tenant's**, through Stripe Connect | `POST /webhooks/stripe-connect` (`STRIPE_CONNECT_WEBHOOK_SECRET`) |

Call Stripe's REST API with `fetch`, no SDK. Every POST carries an `Idempotency-Key`, and store calls carry the tenant's account in the `Stripe-Account` header.

## Money never touches the platform

- **Direct charges.** A Checkout Session is created on the connected account. The payment, balance and payouts are the tenant's, so the platform has no payouts or reserves to manage.
- **Tenant-owned risk.** Connected accounts get the full Stripe Dashboard, Stripe-owned losses, and pay their own Stripe fees. Owners handle refunds and disputes there.
- **The platform fee** is `application_fee_amount`, computed from the plan's fee in basis points and stored on the order. Round down, so the platform never over-takes a cent.
- **The tenant is the merchant of record** and owns sales tax.
- **Hosted Checkout only.** Customers are redirected to Stripe, so no Stripe script runs on a tenant page.

A tenant publishes products once their account is `active` (`charges_enabled`). One `syncStripeStatus` asks Stripe for the state, triggered by `account.updated` and `account.application.deauthorized`. A revoked account makes checkout answer "store paused".

## The order

`POST /checkout/sessions` takes the product, option and quantity. **The price comes from the database**, never the request. It inserts an `orders` row (`created`), creates the session (expires after 30 minutes) and returns Stripe's URL.

```text
created ──► pending ──► paid
   │           │         ├─► refunded            (ours, or the owner's in Stripe)
   │           │         └─► oversold_refunded   (paid after the last unit sold)
   └───────────┴──► failed                       (expired, or a delayed payment failed)
```

`finalizeOrder(orderId, payment)` is the only way an order moves. Every move is a conditional update on the current status, so running it twice changes nothing.

| Session | Order |
| --- | --- |
| `open` | unchanged |
| `complete`, `payment_status: unpaid` (a bank debit) | `pending` |
| `complete`, paid | `paid` |
| `expired` | `failed` |

`charge.refunded` marks a paid order `refunded`, which covers refunds made in the owner's dashboard.

## Two paths to "paid"

The customer's browser and the webhook race, and either may arrive first:

- **The thank-you page** (Stripe's `success_url`) checks the session with Stripe while the order is `created` or `pending`, then calls `finalizeOrder`.
- **The webhook** (`checkout.session.completed`, `async_payment_succeeded`, `async_payment_failed`, `expired`) calls `finalizeOrder` too.

Whichever runs first wins. A customer who closes the tab still ends `paid` through the webhook. Claim order emails once (a `receiptSentAt` column) and send with an idempotency key, so the race never sends two.

## Stock

`stockLimit` (null is unlimited) is checked when the session is created, but **taken only when payment succeeds**: inside `finalizeOrder`'s transaction, `soldCount` goes up only if it stays within the limit. Nothing is reserved while a customer is on Stripe's page.

When two customers pay for the last unit, the second update finds no stock. That order becomes `oversold_refunded` and is refunded automatically on the tenant's account.

With variants, keep stock on each variant row and take it the same way. On save, set the product's `stockLimit` to its variants' total, so everything reading product stock stays right.

## Shipping

Hosted Checkout can't reprice shipping after the address is typed. So the product page asks for the country first, and the session allows only that country (`shipping_address_collection`) with one fixed `shipping_options` rate. Keep the shipping formula in one shared function used by the product page and checkout. The platform fee applies to the items only.

## Early access

Checkout refuses a product that isn't live, unless the request carries a signed grant: HMAC with an app secret under its own label, with an expiry. A forged, edited or expired grant reads as none. It rides in the page URL.

For a shared password, store it hashed, rate-limit attempts per visitor and product, and return a short-lived grant for that product only.

## After the sale

- **CSV export:** quote cells and neutralise formulas.
- **Owner-only notes** stay out of customer emails, the thank-you page and packing slips.

## Local testing

1. Put Stripe test-mode keys in `apps/api/.dev.vars`. Keep the store off while the secret key or Connect webhook secret is missing.
2. Forward both webhooks. Each `listen` prints the signing secret to use:

   ```sh
   stripe listen --forward-to localhost:8787/webhooks/stripe
   stripe listen --forward-connect-to localhost:8787/webhooks/stripe-connect
   ```

3. Connect an account from the dashboard and finish onboarding with Stripe's test data.
4. Buy with `4242 4242 4242 4242`, any future date and CVC.

Test `finalizeOrder` against local Postgres: racing customers for the last unit, a payment finalized twice, pending then paid, expired. The test should refuse any non-localhost database and clean up after itself.

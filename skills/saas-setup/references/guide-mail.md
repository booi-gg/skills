# Sending email

Every email goes out through AWS SES (`apps/api/src/integrations/email/ses.ts`), from one of two modules. Read this before adding an email, a sender or anything that calls SES.

## Which module

| Mail | Module | Log table | Queue |
| --- | --- | --- | --- |
| A tenant to its customers: welcome, reminders, "it's live", broadcasts, thank-you, win-back | `features/email` | `email_messages` | `{project}-email` |
| Everything else: sign-in links, owner notices, order emails, platform news | `features/mail` (`sendMail`) | `mail_messages` | `{project}-mail` |

Customer mail has per-tenant consent, broadcasts, a monthly broadcast limit, opens and clicks, so it keeps its own outbox. Order emails go from the tenant's address but through `features/mail`: they're one email to one person about a purchase, not a project.

**The rule:** nothing calls `sendEmail()` except `features/mail/mail.queue.ts`, `features/email/email.queue.ts`, and the admin test email (`cli email`), which skips the log on purpose to check SES end to end.

## `sendMail()`

```ts
await sendMail(env, db, {
  stream: "transactional",
  kind: "order_receipt",              // what `cli mail list --kind` filters on
  to,
  ...renderOrderReceipt({ … }),       // subject, html, text
  from: `${tenantName} <${senderAddress(env, handle)}>`, // default: hello@ (EMAIL_ADDRESSES)
  replyTo: ownerEmail,               // default: contact@ (EMAIL_ADDRESSES)
  idempotencyKey: `order-receipt:${orderId}`,
});
```

It writes a `mail_messages` row and puts its id on the mail queue; the consumer sends it and records the SES message id. The caller never waits for SES, and a failed send is retried with backoff (up to 8 times, then the recovery cron re-queues it for up to a day).

- **`idempotencyKey`:** pass one whenever the same email could be asked for twice (a retried webhook, a cron overlapping itself). The second call returns the first row with `duplicate: true`.
- **`immediate`:** sends inside the request and throws if SES fails. Only for mail a person is waiting on (the sign-in link), so the form can show the error.
- **`sensitive`:** the body is never stored. Needs `immediate`. Use it for anything that grants access.
- **Streams:** `transactional` (everything today) and `marketing` (platform news to owners, not built yet). Marketing will need a one-click unsubscribe (`List-Unsubscribe` headers) before its first send.

## Suppression

`mail_suppressions` holds addresses that must not get mail, keyed by the normalized address. Both queues check it before every send, and `sendMail` checks it when the row is written.

| Event | What happens |
| --- | --- |
| Hard bounce, any mail | `all`: nothing more goes to the address, from any tenant or the platform |
| Complaint on platform mail | `all` |
| Complaint on tenant mail | the customer is unsubscribed from that tenant only; other tenants keep their consent |
| Transient bounce | nothing; SES retries it |
| By hand | `pnpm cli mail suppress <email>` / `unsuppress` |

A suppressed send is stored with status `suppressed`, so the log still shows it was asked for. The SES webhook (`features/webhooks/webhooks.route.ts`) writes the suppressions; tenant auto-pause above 3% bounce or 0.08% complaint (`EMAIL_HEALTH`) is in the same webhook and emails the owner once (`notifySendingPaused`). The daily allowance for tenant mail (a 30-day ramp, then none while list health is ok) is `features/email/sending-limits.ts`; emails over it stay queued and `recoverStuckMessages` retries them.

## Retention and local dev

- Bodies are cleared after 30 days (cron at 03:00 UTC); the row (who, what, when, status) stays.
- Without AWS keys, or when the sender is under `localhost`, nothing is sent: the email, text included, is written to the api log and the row is marked `sent`. Copy sign-in links from there.
- Local dev with the AWS keys in `apps/api/.dev.vars` sends platform mail for real, since `auth@` and `hello@` are always on the verified domain. Tenant mail (`mail@{handle}.localhost`) still only logs. Local sends name the production configuration set, so their bounces reach the production webhook, not your local database.

## Adding an email

1. Write the template next to its peers (`features/email/templates.ts` today) returning `{ subject, html, text }`.
2. Call `sendMail()` with a new `kind` in snake case and an `idempotencyKey` built from the ids that make it unique.
3. If it's marketing, stop: build the unsubscribe first.

## Why it's built this way

| Decision | Why |
| --- | --- |
| A module in `apps/api`, not its own Worker | `apps/api` owns every binding and secret. While `sendMail()` is the only way in, it can move to a Worker later. |
| Its own queue, separate from customer mail | A 5,000-email broadcast must never delay a receipt or an owner notice. |
| Sign-in sends inside the request | The form must fail if SES fails, instead of promising a link that never comes. It also keeps the link out of the queue and the log. |
| One suppression list for both queues | A dead inbox is dead for every tenant. One bounce is enough. |
| A complaint about a tenant only unsubscribes from that tenant | The customer complained about one tenant; another tenant's consent is its own. |
| Transient bounces aren't suppressed | SES retries them itself. Revisit if the bounce rate climbs. |
| Every platform address in `packages/shared/src/addresses.ts`, the same in every environment | The production domain is the verified identity and the only one with an inbox (Google Workspace: `admin@` is the mailbox, the others are its aliases). Sign-in from `auth@`, other platform mail from `hello@`, so inbox filters can tell access links from notices; replies go to `contact@`. |

## Checking what went out

```sh
pnpm cli mail list --to someone@example.com
pnpm cli mail list --kind sign_in --status failed
pnpm cli mail show <id>
pnpm cli mail            # the same as a menu
pnpm cli mail guide      # the bounce and complaint test, step by step
```

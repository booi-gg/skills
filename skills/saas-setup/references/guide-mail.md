---
version: 2.0.0
---

# Sending email

Every email goes out through AWS SES (`apps/api/src/integrations/email/ses.ts`), from one module: `features/mail` (`sendMail`), with the `mail_messages` log table and the `{project}-mail` queue. That covers sign-in links, notices, product messages and platform news. Read this before adding an email, a sender or anything that calls SES.

**The rule:** nothing calls `sendEmail()` except `features/mail/mail.queue.ts` and the admin test email (`cli email`), which skips the log on purpose to check SES end to end.

## `sendMail()`

```ts
await sendMail(env, db, {
  stream: "transactional",
  kind: "welcome",                    // what `cli mail list --kind` filters on
  to,
  ...renderWelcome({ … }),            // subject, html, text
  // from: default hello@, replyTo: default contact@ (EMAIL_ADDRESSES)
  idempotencyKey: `welcome:${userId}`,
});
```

It writes a `mail_messages` row and puts its id on the mail queue; the consumer sends it and records the SES message id. The caller never waits for SES, and a failed send is retried with backoff (up to 8 times, then the recovery cron re-queues it for up to a day).

- **`idempotencyKey`:** pass one whenever the same email could be asked for twice (a retried webhook, a cron overlapping itself). The second call returns the first row with `duplicate: true`.
- **`immediate`:** sends inside the request and throws if SES fails. Only for mail a person is waiting on (the sign-in link), so the form can show the error.
- **`sensitive`:** the body is never stored. Needs `immediate`. Use it for anything that grants access.
- **Streams:** `transactional` (everything today) and `marketing` (platform news to users, not built yet). Marketing will need a one-click unsubscribe (`List-Unsubscribe` headers) before its first send.

## Suppression

`mail_suppressions` holds addresses that must not get mail, keyed by the normalized address. The mail queue checks it before every send, and `sendMail` checks it when the row is written.

| Event | What happens |
| --- | --- |
| Hard bounce | `all`: nothing more goes to the address |
| Complaint | `all` |
| Transient bounce | nothing; SES retries it |
| By hand | `pnpm cli mail suppress <email>` / `unsuppress` |

A suppressed send is stored with status `suppressed`, so the log still shows it was asked for. The SES webhook (`features/webhooks/webhooks.route.ts`) writes the suppressions.

## Retention and local dev

- Bodies are cleared after 30 days (cron at 03:00 UTC); the row (who, what, when, status) stays.
- Without AWS keys, or when the sender is under `localhost`, nothing is sent: the email, text included, is written to the api log and the row is marked `sent`. Copy sign-in links from there.
- Local dev with the AWS keys in `apps/api/.dev.vars` sends platform mail for real, since `auth@` and `hello@` are always on the verified domain. Local sends name the production configuration set, so their bounces reach the production webhook, not your local database.

## Adding an email

1. Write the template next to its peers (`features/mail/templates.ts`) returning `{ subject, html, text }`.
2. Call `sendMail()` with a new `kind` in snake case and an `idempotencyKey` built from the ids that make it unique.
3. If it's marketing, stop: build the unsubscribe first.

## Why it's built this way

| Decision | Why |
| --- | --- |
| A module in `apps/api`, not its own Worker | `apps/api` owns every binding and secret. While `sendMail()` is the only way in, it can move to a Worker later. |
| Sign-in sends inside the request | The form must fail if SES fails, instead of promising a link that never comes. It also keeps the link out of the queue and the log. |
| One suppression list for all mail | A dead inbox is dead for every kind of mail. One bounce is enough. |
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

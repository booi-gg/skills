# Google Identity Services Guide

What Google Identity Services (GIS) is, how it differs from the Google sign-in we ship today, and how to switch to it with Better Auth if we ever want to.

Companion docs: [`guide-auth.md`](./guide-auth.md) for Better Auth itself, [`guide-split-workers.md`](./guide-split-workers.md) for why auth lives on `apps/api`.

Checked against `better-auth` 1.7.7.

---

## What GIS is

GIS is Google's JavaScript library for "Sign in with Google" (`https://accounts.google.com/gsi/client`). It runs entirely in the browser:

1. Google's script renders a button (or the One Tap card) on our page.
2. The user picks an account in a popup that Google opens and manages.
3. Google hands our page a signed **ID token** (a JWT saying who the user is) in a JavaScript callback.
4. We send the token to the api, which verifies it with Google and sets the session cookie.

No redirect leaves our page, and none of our routes sits in the middle of the flow.

## What we ship today: OAuth in a popup

Google sign-in is the standard OAuth redirect flow, run inside a popup we open ourselves:

```text
auth-view ── click ──▶ window.open("about:blank")            (synchronous, or it gets blocked)
          ── signIn.social({ disableRedirect: true }) ──▶ api returns Google's URL
popup     ──▶ accounts.google.com (account chooser)
          ──▶ api /auth/callback/google  (sets session cookie)
          ──▶ /app/auth/popup  ── BroadcastChannel AUTH_CHANNEL ──▶ auth-view
          ── window.close()
auth-view ── window.location.assign(callbackURL)
```

| Piece | File |
| --- | --- |
| Opens the popup, listens for the result, falls back to a full redirect when blocked | `apps/main/src/features/auth/hooks/use-google-sign-in.ts` |
| The popup's last stop: reports back, closes itself | `apps/main/src/features/auth/components/auth-popup-done.tsx` |
| Its route, `/app/auth/popup` | `apps/main/src/routes/app/auth_.popup.tsx` |
| Channel name and error copy | `apps/main/src/features/auth/utils/auth-channel.ts` |
| `prompt: "select_account"`, so Google always shows the chooser | `apps/api/src/lib/auth.ts` |

**Why a BroadcastChannel, not `window.opener.postMessage`:** Google's pages send a `Cross-Origin-Opener-Policy` header. Once the popup visits them it is cut off from its opener for good: `window.opener` is `null` when it comes back, and `popup.closed` reads `true` while it is still open. A same-origin BroadcastChannel is unaffected. The same reason is why a closed popup is only noticed as focus returning to the sign-in page.

## The two compared

|  | OAuth popup (today) | GIS |
| --- | --- | --- |
| Who opens the popup | our code | Google's script |
| Our route in the flow | `/app/auth/popup` | none |
| Button | ours (`@pkg/ui` `Button`) | Google's, in an iframe: theme, size, text, shape and width only |
| Third-party script on the auth page | none | `accounts.google.com/gsi/client` |
| Always shows the account chooser | yes (`prompt: "select_account"`) | no: the personalised button ("Continue as …") signs in with that account; others are behind its dropdown |
| One Tap card | not possible | same plugin |
| Popup blocked | falls back to redirect | GIS handles it (`ux_mode`) |
| Google access token (Drive, Calendar, …) | yes, stored on the `account` row | no: ID token only |

Stay on the OAuth popup while the button has to match the design system or we need Google API access. Move to GIS when Google's button is acceptable and we want One Tap.

## Better Auth support

Better Auth covers both ends of GIS through the **`oneTap` plugin**. There is no separate "GIS" plugin; the name undersells it.

- **Server, `oneTap()`** from `better-auth/plugins`: adds `POST /auth/one-tap/callback`. It verifies the ID token against Google's keys with `audience` = `socialProviders.google.clientId`, then signs in or signs up through the same path as the OAuth callback. It writes `providerId: "google"`, so users and linked accounts are shared with the OAuth flow, and `account.accountLinking` in `apps/api/src/lib/auth.ts` applies unchanged.
- **Client, `oneTapClient({ clientId })`** from `better-auth/client/plugins`: adds `authClient.oneTap(options)`, which loads the GIS script itself.
  - Without `button`: shows the One Tap card, retrying with backoff (`promptOptions`).
  - With `button: { container, config }`: renders Google's button into `container` instead.

## Switching to GIS

1. **Google Cloud console.** On the OAuth client used by `GOOGLE_CLIENT_ID`, add every origin that renders the button to **Authorized JavaScript origins** (`http://localhost:3000` and the deployed main origin). GIS checks these; the redirect URIs only matter to the OAuth flow.
2. **Web env.** Add `CLIENT_GOOGLE_CLIENT_ID` to `apps/main/src/env.ts` and `apps/main/.env.example`. It is the same value as `GOOGLE_CLIENT_ID` in `apps/api/.dev.vars`. The client id is public; the secret stays on the api.
3. **api.** Add `oneTap()` to `plugins` in `createAuth`. It reads the client id from `socialProviders.google`.
4. **Auth client.** Add `oneTapClient({ clientId: env.CLIENT_GOOGLE_CLIENT_ID })` to `apps/main/src/lib/auth/auth-client.ts`. Skip it when the id is unset, as the api skips Google when its keys are.
5. **Auth view.** Replace the Google `Button` with a container `div`, and in an effect:

   ```ts
   void authClient.oneTap({
     button: {
       container: ref.current,
       config: {
         size: "large",
         text: "continue_with",
         theme: "outline",
         width: 400,
       },
     },
     // Absolute, as in `callbackUrls`: the client navigates here on success.
     callbackURL,
     fetchOptions: {
       onError: ({ error }) =>
         setError(error.message ?? "Google sign-in didn’t work."),
     },
   });
   ```

6. **Delete the popup flow**: the hook, `auth-popup-done.tsx`, `auth_.popup.tsx` and `auth-channel.ts` (keep `errorMessage`, which the magic link uses). Regenerate the route tree with `pnpm --filter ./apps/main generate-routes`.
7. **Keep or drop `prompt: "select_account"`.** GIS ignores it; it only matters if the OAuth flow stays as a fallback.

## Gotchas

- **Errors are silent by default.** `authClient.oneTap` returns quietly when `/one-tap/callback` fails. Pass `fetchOptions.onError`, or a failed sign-in looks like nothing happened.
- **`fetchOptions` turns off the redirect unless `callbackURL` is set.** With both, the client navigates to `callbackURL` on success; don't also navigate in `onSuccess`, or it happens twice.
- **Render once.** `oneTap` calls `google.accounts.id.initialize` each time it runs. Guard the effect so React strict mode doesn't render two buttons.
- **The button is an iframe.** Our classes, fonts and `Typography` don't reach inside it. Width tops out at 400px.
- **FedCM.** In Chrome, One Tap runs on FedCM by default (`promptOptions.fedCM`), and its prompt UI is the browser's, not Google's. `cancelOnTapOutside` only works with FedCM off.
- **Tenant subdomains.** Only `apps/main` renders sign-in. If a tenant page ever does, its origin has to be added to the console list; a wildcard isn't accepted.

# Layers

Examples use a `User` service. Swap in the real name. Swap `createHttpClient`, `eStore`, `USER_POLL_MS` and the entry-point files for the project's real pieces and paths.

No barrels: every import points at the file directly.

## Contents

1. Contract — `user-service.types.ts`
2. Electron implementation
3. Web implementation
4. Facade — `user.service.ts`
5. Entry points
6. Hooks
7. UI — container and presentational

---

## 1. Contract — `user-service.types.ts`

Write this first. Every platform implements it; the hooks layer only ever sees it.

```ts
export type TUser = {
  id: string;
  name: string;
  isAuthenticated: boolean;
};

export type TUserService = {
  getUser: () => TUser | undefined; // synchronous, referentially stable snapshot
  subscribe: (listener: () => void) => () => void; // returns unsubscribe
  logout: () => Promise<void>;
  destroy: () => void;
};
```

- `subscribe` + `getUser` is exactly what `useSyncExternalStore` needs. No callback payloads: listeners re-read the snapshot.
- Anything a hook calls lives here. A method missing from the contract is a hook reaching around it.

## 2. Electron implementation

```ts
import type { TElectronStore } from "./electron-store.types";
import type { TUser, TUserService } from "./user-service.types";

export const createUserElectronService = (deps: { store: TElectronStore }): TUserService => {
  const { store } = deps;
  const listeners = new Set<() => void>();

  // Cache the snapshot: store.get() deserialises a new object on every call.
  let user: TUser | undefined = store.get("user");

  const notify = () => {
    for (const listener of listeners) {
      listener();
    }
  };

  const stopWatching = store.onDidChange("user", (next: TUser | undefined) => {
    user = next;
    notify();
  });

  return Object.freeze({
    getUser: () => user,
    subscribe: (listener: () => void) => {
      listeners.add(listener);
      return () => {
        listeners.delete(listener);
      };
    },
    logout: async () => {
      store.delete("user"); // onDidChange updates the snapshot and notifies
    },
    destroy: () => {
      stopWatching();
      listeners.clear();
    },
  });
};
```

## 3. Web implementation

No store on the web — data comes from an API. The API wrapper stays thin; the service owns caching, polling and change detection.

```ts
import type { THttpClient } from "./http-client.types";
import type { TUser } from "./user-service.types";

export type TUserApi = {
  getUser: () => Promise<TUser | undefined>;
  logout: () => Promise<void>;
};

export const createUserApi = (deps: { httpClient: THttpClient }): TUserApi => {
  const { httpClient } = deps;
  return Object.freeze({
    getUser: () => httpClient.get<TUser | undefined>("/user"),
    logout: () => httpClient.post<void>("/logout"),
  });
};
```

```ts
import type { TUserApi } from "./user-api";
import type { TUser, TUserService } from "./user-service.types";

export const createUserWebService = (deps: {
  userApi: TUserApi;
  initialUser: TUser | undefined;
  pollMs: number;
}): TUserService => {
  const { userApi, initialUser, pollMs } = deps;
  const listeners = new Set<() => void>();
  let user = initialUser;
  let timer: ReturnType<typeof setInterval> | undefined;

  const notify = () => {
    for (const listener of listeners) {
      listener();
    }
  };

  const setUser = (next: TUser | undefined) => {
    // Replace the snapshot only on real change: keeps it stable and avoids empty re-renders.
    if (JSON.stringify(next) === JSON.stringify(user)) {
      return;
    }
    user = next;
    notify();
  };

  const refresh = async () => {
    try {
      setUser(await userApi.getUser());
    } catch {
      // Network blip: keep the last known user, try again next tick.
    }
  };

  // Poll only while someone is listening. Survives StrictMode's mount → unmount → mount.
  const start = () => {
    timer = setInterval(() => {
      void refresh();
    }, pollMs);
  };

  const stop = () => {
    clearInterval(timer);
    timer = undefined;
  };

  return Object.freeze({
    getUser: () => user,
    subscribe: (listener: () => void) => {
      listeners.add(listener);
      if (listeners.size === 1) {
        start();
      }
      return () => {
        listeners.delete(listener);
        if (listeners.size === 0) {
          stop();
        }
      };
    },
    logout: async () => {
      await userApi.logout();
      setUser(undefined);
    },
    destroy: () => {
      stop();
      listeners.clear();
    },
  });
};
```

## 4. Facade — `user.service.ts`

The only service file the hooks layer imports. Delegates to whatever the entry point injected.

```ts
import type { TUserService } from "./user-service.types";

let impl: TUserService | undefined;

const getImpl = (): TUserService => {
  if (impl === undefined) {
    throw new Error("UserService.init() must run in the entry point before anything reads it");
  }
  return impl;
};

export const UserService = Object.freeze({
  init: (next: TUserService) => {
    impl = next;
  },
  getUser: () => getImpl().getUser(),
  subscribe: (listener: () => void) => getImpl().subscribe(listener),
  logout: () => getImpl().logout(),
  destroy: () => getImpl().destroy(),
});
```

- Methods are arrow properties, so `UserService.subscribe` can be passed by reference to `useSyncExternalStore`.
- SSR: don't use this module-level facade. Create the service per request and provide it through context.

## 5. Entry points

All wiring lives here. Init happens before `render`, outside React, so StrictMode can't double-run or tear it down.

```tsx
// app.web.tsx
const bootstrap = async () => {
  const httpClient = createHttpClient({ getToken });
  const userApi = createUserApi({ httpClient });
  const initialUser = await userApi.getUser(); // hydrate: no logged-out flash

  UserService.init(createUserWebService({ userApi, initialUser, pollMs: USER_POLL_MS }));

  createRoot(getRootElement()).render(<App />);
};

void bootstrap();
```

```tsx
// app.electron.tsx — only this file differs from web
UserService.init(createUserElectronService({ store: eStore }));

createRoot(getRootElement()).render(<App />);
```

Call `UserService.destroy()` only on real teardown (tests, Electron window close) — never in a React effect cleanup.

## 6. Hooks

Bridge the facade into React. The signature is the contract: it stays the same whichever service is behind it.

### `useIsAuthenticated`

```ts
import { useSyncExternalStore } from "react";
import { UserService } from "./user.service";

const getIsAuthenticated = () => UserService.getUser()?.isAuthenticated === true;

export const useIsAuthenticated = (): boolean =>
  useSyncExternalStore(UserService.subscribe, getIsAuthenticated);
```

- Selecting a primitive means components re-render only when the boolean flips, not on every user change.
- Same signature backed by Zustand — components don't change:

```ts
export const useIsAuthenticated = (): boolean =>
  useUserStore((state) => state.user?.isAuthenticated === true);
```

### `useLogout`

Non-React work (API call, clearing tokens, resetting the snapshot) is in the service. The hook owns only React concerns: loading and error state.

```ts
import { useState } from "react";
import { UserService } from "./user.service";

export const useLogout = () => {
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<Error | undefined>(undefined);

  const logout = async () => {
    if (isLoading) {
      return;
    }
    setIsLoading(true);
    setError(undefined);
    try {
      await UserService.logout(); // service notifies subscribers; no manual store update
    } catch (caught) {
      setError(caught instanceof Error ? caught : new Error("Logout failed"));
    } finally {
      setIsLoading(false);
    }
  };

  return { logout, isLoading, error };
};
```

Repo already uses TanStack Query? Wrap `UserService.logout` in `useMutation` instead of hand-rolled state.

## 7. UI — container and presentational

Container knows hooks. Presentational knows props.

```tsx
export const UserMenuContainer = () => {
  const isAuthenticated = useIsAuthenticated();
  const { logout, isLoading } = useLogout();

  const handleLogout = () => {
    void logout();
  };

  return <UserMenu isAuthenticated={isAuthenticated} isBusy={isLoading} onLogout={handleLogout} />;
};
```

```tsx
type TUserMenuProps = {
  isAuthenticated: boolean;
  isBusy: boolean;
  onLogout: () => void;
};

export const UserMenu = (props: TUserMenuProps) => {
  const { isAuthenticated, isBusy, onLogout } = props;

  if (!isAuthenticated) {
    return <LoginButton />;
  }
  return (
    <button type="button" disabled={isBusy} onClick={onLogout}>
      Log out
    </button>
  );
};
```

### Visual prop names

```tsx
// ❌ knows about "history views"
<DropdownItem isHistoryView />

// ✅ describes the visual treatment
<DropdownItem isIndented />
```

### Compose, don't monolith

```tsx
<DropdownMenu>
  <DropdownHeader label="Recent" />
  <DropdownItem isIndented label="Item A" />
  <DropdownItem isIndented label="Item B" />
  <DropdownDivider />
  <DropdownItem label="Item C" />
</DropdownMenu>
```

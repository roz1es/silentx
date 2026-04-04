import type { User } from '@/types';

const KEY = 'messenger_auth';
const LEGACY_KEY = 'messenger_user';

export type StoredAuth = { user: User; token: string };

export function loadAuth(): StoredAuth | null {
  try {
    const raw = localStorage.getItem(KEY);
    if (raw) {
      const data = JSON.parse(raw) as { user?: User; token?: unknown };
      if (
        data?.user?.id &&
        data?.user?.username &&
        typeof data.token === 'string' &&
        data.token.length > 0
      ) {
        return { user: data.user, token: data.token };
      }
    }
    if (localStorage.getItem(LEGACY_KEY)) {
      localStorage.removeItem(LEGACY_KEY);
    }
  } catch {
    /* ignore */
  }
  localStorage.removeItem(KEY);
  return null;
}

export function saveAuth(user: User, token: string): void {
  localStorage.setItem(KEY, JSON.stringify({ user, token }));
}

export function updateStoredUser(user: User): void {
  const prev = loadAuth();
  if (!prev?.token) return;
  saveAuth(user, prev.token);
}

export function clearAuth(): void {
  localStorage.removeItem(KEY);
  if (localStorage.getItem(LEGACY_KEY)) localStorage.removeItem(LEGACY_KEY);
}

/** Только пользователь (для начального состояния UI) */
export function loadUser(): User | null {
  return loadAuth()?.user ?? null;
}

export function loadToken(): string | null {
  return loadAuth()?.token ?? null;
}

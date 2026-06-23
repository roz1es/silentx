import type { User } from '@/types';

const KEY = 'messenger_auth';
const LEGACY_KEY = 'messenger_user';

export type StoredUser = { user: User };

export function loadAuth(): StoredUser | null {
  try {
    const raw = localStorage.getItem(KEY);
    if (raw) {
      const data = JSON.parse(raw) as { user?: User };
      if (data?.user?.id && data?.user?.username) {
        return { user: data.user };
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

export function saveAuth(user: User): void {
  localStorage.setItem(KEY, JSON.stringify({ user }));
}

export function updateStoredUser(user: User): void {
  const prev = loadAuth();
  if (!prev) return;
  saveAuth(user);
}

export function clearAuth(): void {
  localStorage.removeItem(KEY);
  if (localStorage.getItem(LEGACY_KEY)) localStorage.removeItem(LEGACY_KEY);
}

/** Только пользователь (для начального состояния UI) */
export function loadUser(): User | null {
  return loadAuth()?.user ?? null;
}

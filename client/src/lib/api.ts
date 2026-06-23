import type { Chat, Message, User } from '@/types';

/** Base URL для API. Если задан в env — используем его, иначе относительный путь (для прокси) */
const API_BASE = import.meta.env.VITE_API_URL || '';
const REQUEST_TIMEOUT_MS = 20000;

async function request<T>(
  path: string,
  options: RequestInit = {}
): Promise<T> {
  const controller = new AbortController();
  const timeout = window.setTimeout(() => controller.abort(), REQUEST_TIMEOUT_MS);
  const headers = new Headers(options.headers);
  headers.set('Content-Type', 'application/json');
  const url = API_BASE + path;
  try {
    const res = await fetch(url, {
      ...options,
      headers,
      signal: controller.signal,
      credentials: 'include',
    });
    if (!res.ok) {
      const err = (await res.json().catch(() => ({}))) as { error?: string };
      throw new Error(err.error ?? res.statusText);
    }
    return res.json() as Promise<T>;
  } catch (err) {
    if (err instanceof DOMException && err.name === 'AbortError') {
      throw new Error('Сервер долго не отвечает. Попробуйте еще раз.');
    }
    throw err;
  } finally {
    window.clearTimeout(timeout);
  }
}

export type AuthSuccess = { user: User };
export type EmailCodeChallenge = {
  emailCodeRequired: true;
  ticket: string;
  emailMasked: string;
};
export type EmailVerificationChallenge = {
  emailVerificationRequired: true;
  ticket: string;
  emailMasked: string;
};
export type PasswordResetChallenge = {
  ok: true;
  ticket?: string;
  emailMasked?: string;
  message?: string;
};

export async function register(
  username: string,
  email: string,
  password: string
): Promise<AuthSuccess | EmailVerificationChallenge> {
  return request('/api/register', {
    method: 'POST',
    body: JSON.stringify({ username, email, password }),
  });
}

export async function login(
  username: string,
  password: string,
  rememberMe: boolean
): Promise<AuthSuccess | EmailCodeChallenge> {
  return request('/api/login', {
    method: 'POST',
    body: JSON.stringify({ username, password, rememberMe }),
  });
}

export async function confirmLogin(
  ticket: string,
  code: string,
  rememberMe: boolean
): Promise<AuthSuccess> {
  return request('/api/login/confirm', {
    method: 'POST',
    body: JSON.stringify({ ticket, code, rememberMe }),
  });
}

export async function confirmRegister(
  ticket: string,
  code: string
): Promise<AuthSuccess> {
  return request('/api/register/confirm', {
    method: 'POST',
    body: JSON.stringify({ ticket, code }),
  });
}

export async function requestPasswordReset(
  login: string
): Promise<PasswordResetChallenge> {
  return request('/api/password-reset/request', {
    method: 'POST',
    body: JSON.stringify({ login }),
  });
}

export async function confirmPasswordReset(
  ticket: string,
  code: string,
  password: string
): Promise<{ ok: true }> {
  return request('/api/password-reset/confirm', {
    method: 'POST',
    body: JSON.stringify({ ticket, code, password }),
  });
}

export async function logout(): Promise<{ ok: true }> {
  return request('/api/logout', {
    method: 'POST',
    body: JSON.stringify({}),
  });
}

export async function requestEmailBind(
  email: string
): Promise<{ ticket: string; emailMasked: string }> {
  return request('/api/me/email/request', {
    method: 'POST',
    body: JSON.stringify({ email }),
  });
}

export async function confirmEmailBind(
  ticket: string,
  code: string
): Promise<{ user: User }> {
  return request('/api/me/email/confirm', {
    method: 'POST',
    body: JSON.stringify({ ticket, code }),
  });
}

export async function fetchMe(): Promise<{ user: User }> {
  return request('/api/me');
}

export type AuthSessionInfo = {
  id: string;
  createdAt: number;
  expiresAt: number;
  current: boolean;
  remembered: boolean;
};

export async function fetchAuthSessions(): Promise<{
  sessions: AuthSessionInfo[];
}> {
  return request('/api/me/sessions');
}

export async function revokeAuthSession(
  sessionId: string
): Promise<{ ok: boolean }> {
  return request(`/api/me/sessions/${encodeURIComponent(sessionId)}`, {
    method: 'DELETE',
  });
}

export async function revokeOtherAuthSessions(): Promise<{
  ok: boolean;
  revoked: number;
}> {
  return request('/api/me/sessions/revoke-others', {
    method: 'POST',
    body: JSON.stringify({}),
  });
}

export type IceServerConfig = {
  urls: string | string[];
  username?: string;
  credential?: string;
};

export async function fetchCallIceServers(): Promise<{
  iceServers: IceServerConfig[];
}> {
  return request('/api/calls/ice-servers');
}

export type E2eeKeyBackup = {
  version: 1;
  salt: string;
  iv: string;
  ciphertext: string;
  iterations: number;
  updatedAt: number;
};

export async function fetchE2eeKeyBackup(): Promise<{
  backup: E2eeKeyBackup | null;
}> {
  return request('/api/e2ee/key-backup');
}

export async function saveE2eeKeyBackup(
  backup: Omit<E2eeKeyBackup, 'updatedAt'>
): Promise<{ ok: true }> {
  return request('/api/e2ee/key-backup', {
    method: 'PUT',
    body: JSON.stringify(backup),
  });
}

export type ProfilePatch = {
  avatarUrl?: string | null;
  bio?: string | null;
  displayName?: string | null;
  phone?: string | null;
  birthDate?: string | null;
  privacy?: {
    showOnline?: boolean;
    allowCalls?: boolean;
    showEmail?: boolean;
  };
};

export async function patchProfile(patch: ProfilePatch): Promise<{ user: User }> {
  return request('/api/me', {
    method: 'PATCH',
    body: JSON.stringify(patch),
  });
}

export async function fetchUserProfile(
  userId: string
): Promise<{ user: User }> {
  return request(`/api/users/${encodeURIComponent(userId)}`);
}

export type DirectoryUser = {
  id: string;
  username: string;
  displayName?: string;
  avatarUrl?: string;
};

export async function fetchUserDirectory(): Promise<{ users: DirectoryUser[] }> {
  return request('/api/users/directory');
}

export async function fetchContactDirectory(): Promise<{ users: DirectoryUser[] }> {
  return request('/api/users/contacts');
}

export async function searchUsers(
  query: string
): Promise<{ users: DirectoryUser[] }> {
  return request(
    `/api/users/search?q=${encodeURIComponent(query.trim())}`
  );
}

export const searchUsersByUsername = searchUsers;

export type AdminOverview = {
  userCount: number;
  blockedUserCount: number;
  chatCount: number;
  directChatCount: number;
  groupChatCount: number;
  channelChatCount: number;
  messageCount: number;
  users: Array<{
    id: string;
    username: string;
    displayName?: string;
    isAdmin: boolean;
    email?: string;
    emailVerified: boolean;
    banned: boolean;
    messageCount: number;
    chatCount: number;
  }>;
};

export async function fetchAdminOverview(): Promise<AdminOverview> {
  return request('/api/admin/overview');
}

export async function fetchAdminDatabaseLink(): Promise<{ url: string | null }> {
  return request('/api/admin/database');
}

export async function setAdminUserBlocked(
  userId: string,
  banned: boolean
): Promise<{ user: User }> {
  return request(`/api/admin/users/${encodeURIComponent(userId)}/block`, {
    method: 'POST',
    body: JSON.stringify({ banned }),
  });
}

export async function fetchChats(): Promise<{ chats: Chat[] }> {
  return request('/api/chats');
}

export async function fetchMessages(
  chatId: string
): Promise<{ messages: Message[] }> {
  return request(`/api/chats/${encodeURIComponent(chatId)}/messages`);
}

export type E2eeDevicePublicKey = {
  userId: string;
  deviceId: string;
  publicKey: string;
  createdAt: number;
  lastSeenAt: number;
};

export async function registerE2eeDevice(
  deviceId: string,
  publicKey: string
): Promise<{ ok: true; deviceId: string }> {
  return request('/api/e2ee/devices', {
    method: 'POST',
    body: JSON.stringify({ deviceId, publicKey }),
  });
}

export async function fetchChatE2eeDevices(chatId: string): Promise<{
  chatId: string;
  participantIds: string[];
  devices: E2eeDevicePublicKey[];
}> {
  return request(
    `/api/chats/${encodeURIComponent(chatId)}/e2ee-devices`
  );
}

export async function createDirectChat(body: {
  targetUsername?: string;
  targetUserId?: string;
}): Promise<{ chat: Chat }> {
  return request('/api/chats/direct', {
    method: 'POST',
    body: JSON.stringify(body),
  });
}

export async function createSavedChat(): Promise<{ chat: Chat }> {
  return request('/api/chats/saved', {
    method: 'POST',
    body: JSON.stringify({}),
  });
}

export async function createGroupChat(
  name: string,
  memberIds: string[]
): Promise<{ chat: Chat }> {
  return request('/api/chats/group', {
    method: 'POST',
    body: JSON.stringify({ name, memberIds }),
  });
}

export async function createChannelChat(
  name: string,
  subscriberIds: string[]
): Promise<{ chat: Chat }> {
  return request('/api/chats/channel', {
    method: 'POST',
    body: JSON.stringify({ name, memberIds: subscriberIds }),
  });
}

export async function deleteChat(chatId: string): Promise<{ ok: boolean }> {
  return request(`/api/chats/${encodeURIComponent(chatId)}`, {
    method: 'DELETE',
  });
}

export type ChatProfilePatch = {
  name?: string;
  avatarUrl?: string | null;
};

export async function patchChat(
  chatId: string,
  patch: ChatProfilePatch
): Promise<{ chat: Chat }> {
  return request(`/api/chats/${encodeURIComponent(chatId)}`, {
    method: 'PATCH',
    body: JSON.stringify(patch),
  });
}

export async function addChatMembersApi(
  chatId: string,
  memberIds: string[]
): Promise<{ chat: Chat }> {
  return request(`/api/chats/${encodeURIComponent(chatId)}/members`, {
    method: 'POST',
    body: JSON.stringify({ memberIds }),
  });
}

export async function setChatMuted(
  chatId: string,
  muted: boolean
): Promise<{ ok: boolean }> {
  return request(`/api/chats/${encodeURIComponent(chatId)}/mute`, {
    method: 'POST',
    body: JSON.stringify({ muted }),
  });
}

export async function setChatPinnedTop(
  chatId: string,
  pinned: boolean
): Promise<{ ok: boolean }> {
  return request(`/api/chats/${encodeURIComponent(chatId)}/pin-top`, {
    method: 'POST',
    body: JSON.stringify({ pinned }),
  });
}

export async function setPinnedMessage(
  chatId: string,
  messageId: string | null
): Promise<{ ok: boolean }> {
  return request(`/api/chats/${encodeURIComponent(chatId)}/pin-message`, {
    method: 'POST',
    body: JSON.stringify({ messageId }),
  });
}

export async function clearChatMessages(
  chatId: string
): Promise<{ ok: boolean }> {
  return request(`/api/chats/${encodeURIComponent(chatId)}/clear`, {
    method: 'POST',
    body: JSON.stringify({}),
  });
}

export async function getPushVapidPublicKey(): Promise<{ publicKey: string }> {
  return request('/api/push/vapid-public-key');
}

export async function subscribePush(subscription: {
  endpoint: string;
  keys: { p256dh: string; auth: string };
}): Promise<{ ok: boolean }> {
  return request('/api/push/subscribe', {
    method: 'POST',
    body: JSON.stringify(subscription),
  });
}

export async function unsubscribePush(endpoint: string): Promise<{ ok: boolean }> {
  return request('/api/push/unsubscribe', {
    method: 'POST',
    body: JSON.stringify({ endpoint }),
  });
}

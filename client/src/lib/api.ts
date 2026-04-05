import type { Chat, Message, User } from '@/types';
import { loadAuth } from '@/lib/storage';

async function request<T>(
  path: string,
  options: RequestInit = {}
): Promise<T> {
  const auth = loadAuth();
  const headers = new Headers(options.headers);
  headers.set('Content-Type', 'application/json');
  if (auth?.token) {
    headers.set('Authorization', `Bearer ${auth.token}`);
  }
  const res = await fetch(path, { ...options, headers });
  if (!res.ok) {
    const err = (await res.json().catch(() => ({}))) as { error?: string };
    throw new Error(err.error ?? res.statusText);
  }
  return res.json() as Promise<T>;
}

export async function register(
  username: string,
  password: string
): Promise<{ user: User; token: string }> {
  return request('/api/register', {
    method: 'POST',
    body: JSON.stringify({ username, password }),
  });
}

export async function login(
  username: string,
  password: string
): Promise<{ user: User; token: string }> {
  return request('/api/login', {
    method: 'POST',
    body: JSON.stringify({ username, password }),
  });
}

export async function fetchMe(): Promise<{ user: User }> {
  return request('/api/me');
}

export type ProfilePatch = {
  avatarUrl?: string | null;
  bio?: string | null;
  displayName?: string | null;
  phone?: string | null;
  birthDate?: string | null;
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

export type AdminOverview = {
  userCount: number;
  chatCount: number;
  directChatCount: number;
  groupChatCount: number;
  messageCount: number;
  users: Array<{
    id: string;
    username: string;
    displayName?: string;
    isAdmin: boolean;
  }>;
};

export async function fetchAdminOverview(): Promise<AdminOverview> {
  return request('/api/admin/overview');
}

export async function fetchChats(): Promise<{ chats: Chat[] }> {
  return request('/api/chats');
}

export async function fetchMessages(
  chatId: string
): Promise<{ messages: Message[] }> {
  return request(`/api/chats/${encodeURIComponent(chatId)}/messages`);
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

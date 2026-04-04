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

export async function fetchChats(): Promise<{ chats: Chat[] }> {
  return request('/api/chats');
}

export async function fetchMessages(
  chatId: string
): Promise<{ messages: Message[] }> {
  return request(`/api/chats/${encodeURIComponent(chatId)}/messages`);
}

export async function createDirectChat(
  targetUsername: string
): Promise<{ chat: Chat }> {
  return request('/api/chats/direct', {
    method: 'POST',
    body: JSON.stringify({ targetUsername }),
  });
}

export async function createGroupChat(
  name: string,
  memberUsernames: string[]
): Promise<{ chat: Chat }> {
  return request('/api/chats/group', {
    method: 'POST',
    body: JSON.stringify({ name, memberUsernames }),
  });
}

import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import mysql from 'mysql2/promise';
import { v4 as uuid } from 'uuid';
import './env.js';

export const SHORT_SESSION_TTL_MS = 12 * 60 * 60 * 1000;
export const REMEMBERED_SESSION_TTL_MS = 30 * 24 * 60 * 60 * 1000;
const MAX_SESSIONS_PER_USER = 10;

export type AuthSession = {
  id: string;
  userId: string;
  createdAt: number;
  expiresAt: number;
};

export type PublicAuthSession = {
  id: string;
  createdAt: number;
  expiresAt: number;
  current: boolean;
  remembered: boolean;
};

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const SESSION_FILE = path.join(__dirname, '..', 'data', 'auth-sessions.json');
const sessions = new Map<string, AuthSession>();
let persistenceQueue = Promise.resolve();

function shouldUseMysql(): boolean {
  return process.env.PERSIST_BACKEND === 'mysql' && !!process.env.DATABASE_URL;
}

async function withMysql<T>(
  fn: (conn: mysql.Connection) => Promise<T>
): Promise<T> {
  if (!process.env.DATABASE_URL) throw new Error('DATABASE_URL не задан');
  const conn = await mysql.createConnection({
    uri: process.env.DATABASE_URL,
    dateStrings: true,
  });
  try {
    return await fn(conn);
  } finally {
    await conn.end();
  }
}

function queuePersistence(task: () => Promise<void>): Promise<void> {
  const next = persistenceQueue.then(task, task);
  persistenceQueue = next.catch(() => undefined);
  return next;
}

function removeExpiredFromMemory(now = Date.now()): string[] {
  const removed: string[] = [];
  for (const [id, session] of sessions) {
    if (session.expiresAt <= now) {
      sessions.delete(id);
      removed.push(id);
    }
  }
  return removed;
}

async function saveSessionFile(): Promise<void> {
  await fs.mkdir(path.dirname(SESSION_FILE), { recursive: true });
  const temp = `${SESSION_FILE}.tmp`;
  await fs.writeFile(temp, JSON.stringify([...sessions.values()]), {
    encoding: 'utf8',
    mode: 0o600,
  });
  await fs.rename(temp, SESSION_FILE);
}

export async function initializeSessionStore(): Promise<void> {
  sessions.clear();
  const now = Date.now();
  if (shouldUseMysql()) {
    await withMysql(async (conn) => {
      await conn.execute(`
        CREATE TABLE IF NOT EXISTS auth_sessions (
          id VARCHAR(64) PRIMARY KEY,
          user_id VARCHAR(96) NOT NULL,
          created_at BIGINT NOT NULL,
          expires_at BIGINT NOT NULL,
          INDEX idx_auth_sessions_user (user_id),
          INDEX idx_auth_sessions_expires (expires_at)
        )
      `);
      await conn.execute('DELETE FROM auth_sessions WHERE expires_at <= ?', [now]);
      const [rows] = await conn.execute<mysql.RowDataPacket[]>(
        'SELECT id, user_id, created_at, expires_at FROM auth_sessions'
      );
      for (const row of rows) {
        const session: AuthSession = {
          id: String(row.id),
          userId: String(row.user_id),
          createdAt: Number(row.created_at),
          expiresAt: Number(row.expires_at),
        };
        if (session.expiresAt > now) sessions.set(session.id, session);
      }
    });
    return;
  }

  try {
    const raw = JSON.parse(await fs.readFile(SESSION_FILE, 'utf8')) as AuthSession[];
    for (const session of raw) {
      if (
        session &&
        typeof session.id === 'string' &&
        typeof session.userId === 'string' &&
        Number.isFinite(session.createdAt) &&
        Number.isFinite(session.expiresAt) &&
        session.expiresAt > now
      ) {
        sessions.set(session.id, session);
      }
    }
  } catch {
    // Первый запуск без файла сессий.
  }
}

export async function createAuthSession(
  userId: string,
  persist = true,
  ttlMs = SHORT_SESSION_TTL_MS
): Promise<AuthSession> {
  removeExpiredFromMemory();
  const createdAt = Date.now();
  const safeTtlMs =
    Number.isFinite(ttlMs) && ttlMs > 0
      ? Math.min(ttlMs, REMEMBERED_SESSION_TTL_MS)
      : SHORT_SESSION_TTL_MS;
  const session: AuthSession = {
    id: uuid(),
    userId,
    createdAt,
    expiresAt: createdAt + safeTtlMs,
  };
  sessions.set(session.id, session);

  const userSessions = [...sessions.values()]
    .filter((item) => item.userId === userId)
    .sort((a, b) => b.createdAt - a.createdAt);
  const removedIds = userSessions
    .slice(MAX_SESSIONS_PER_USER)
    .map((item) => item.id);
  removedIds.forEach((id) => sessions.delete(id));

  if (!persist) return session;

  await queuePersistence(async () => {
    if (shouldUseMysql()) {
      await withMysql(async (conn) => {
        if (removedIds.length > 0) {
          await conn.query('DELETE FROM auth_sessions WHERE id IN (?)', [removedIds]);
        }
        await conn.execute(
          `INSERT INTO auth_sessions (id, user_id, created_at, expires_at)
           VALUES (?, ?, ?, ?)`,
          [session.id, session.userId, session.createdAt, session.expiresAt]
        );
      });
    } else {
      await saveSessionFile();
    }
  });
  return session;
}

export function getActiveSession(sessionId: string): AuthSession | undefined {
  const session = sessions.get(sessionId);
  if (!session) return undefined;
  if (session.expiresAt <= Date.now()) {
    sessions.delete(sessionId);
    void revokeAuthSession(sessionId);
    return undefined;
  }
  return session;
}

export function listUserSessions(
  userId: string,
  currentSessionId?: string
): PublicAuthSession[] {
  removeExpiredFromMemory();
  return [...sessions.values()]
    .filter((session) => session.userId === userId)
    .sort((a, b) => b.createdAt - a.createdAt)
    .map((session) => {
      const ttl = session.expiresAt - session.createdAt;
      return {
        id: session.id,
        createdAt: session.createdAt,
        expiresAt: session.expiresAt,
        current: session.id === currentSessionId,
        remembered: ttl > SHORT_SESSION_TTL_MS + 60_000,
      };
    });
}

export async function revokeUserSession(
  userId: string,
  sessionId: string
): Promise<boolean> {
  const session = sessions.get(sessionId);
  if (!session || session.userId !== userId) return false;
  await revokeAuthSession(sessionId);
  return true;
}

export async function revokeOtherUserSessions(
  userId: string,
  currentSessionId: string
): Promise<string[]> {
  const ids = [...sessions.values()]
    .filter(
      (session) =>
        session.userId === userId && session.id !== currentSessionId
    )
    .map((session) => session.id);
  for (const id of ids) {
    await revokeAuthSession(id);
  }
  return ids;
}

export async function revokeAuthSession(sessionId: string): Promise<void> {
  sessions.delete(sessionId);
  await queuePersistence(async () => {
    if (shouldUseMysql()) {
      await withMysql(async (conn) => {
        await conn.execute('DELETE FROM auth_sessions WHERE id = ?', [sessionId]);
      });
    } else {
      await saveSessionFile();
    }
  });
}

export async function revokeAllUserSessions(userId: string): Promise<void> {
  for (const [id, session] of sessions) {
    if (session.userId === userId) sessions.delete(id);
  }
  await queuePersistence(async () => {
    if (shouldUseMysql()) {
      await withMysql(async (conn) => {
        await conn.execute('DELETE FROM auth_sessions WHERE user_id = ?', [userId]);
      });
    } else {
      await saveSessionFile();
    }
  });
}

export function clearSessionStoreForTests(): void {
  sessions.clear();
}

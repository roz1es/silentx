import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import mysql from 'mysql2/promise';
import type { PersistedStateV1, PushSubscriptionData } from './store.js';
import type {
  EncryptedTextEnvelope,
  MessageMediaKind,
} from './types.js';
import * as store from './store.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const STATE_FILE = path.join(__dirname, '..', 'data', 'silentix-state.json');
const MYSQL_STATE_ID = 'main';

function shouldUseMysql(): boolean {
  return process.env.PERSIST_BACKEND === 'mysql' && !!process.env.DATABASE_URL;
}

function isPersistedState(data: unknown): data is PersistedStateV1 {
  const state = data as Partial<PersistedStateV1> | null;
  return !!state && state.v === 1 && Array.isArray(state.users) && Array.isArray(state.chats);
}

function readStateFromDisk(): PersistedStateV1 | null {
  if (!fs.existsSync(STATE_FILE)) return null;
  const raw = JSON.parse(fs.readFileSync(STATE_FILE, 'utf8')) as unknown;
  if (!isPersistedState(raw)) return null;
  return raw;
}

async function withMysql<T>(fn: (conn: mysql.Connection) => Promise<T>): Promise<T> {
  if (!process.env.DATABASE_URL) {
    throw new Error('DATABASE_URL не задан');
  }
  const conn = await mysql.createConnection({
    uri: process.env.DATABASE_URL,
    dateStrings: true,
  });
  try {
    await ensureMysqlSchema(conn);
    return await fn(conn);
  } finally {
    await conn.end();
  }
}

async function ensureMysqlSchema(conn: mysql.Connection): Promise<void> {
  await conn.execute(`
    CREATE TABLE IF NOT EXISTS app_state (
      id VARCHAR(32) PRIMARY KEY,
      data JSON NOT NULL,
      updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
    )
  `);
  await conn.execute(`
    CREATE TABLE IF NOT EXISTS users (
      id VARCHAR(96) PRIMARY KEY,
      username VARCHAR(191) NOT NULL UNIQUE,
      password TEXT NOT NULL,
      email VARCHAR(320) NULL,
      email_verified TINYINT(1) NOT NULL DEFAULT 0,
      avatar_url LONGTEXT NULL,
      display_name VARCHAR(191) NULL,
      bio TEXT NULL,
      phone VARCHAR(64) NULL,
      birth_date VARCHAR(10) NULL,
      is_admin TINYINT(1) NOT NULL DEFAULT 0,
      banned TINYINT(1) NOT NULL DEFAULT 0,
      privacy JSON NULL,
      updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
    )
  `);
  await conn.execute(`
    CREATE TABLE IF NOT EXISTS chats (
      id VARCHAR(96) PRIMARY KEY,
      type VARCHAR(24) NOT NULL,
      name VARCHAR(255) NOT NULL,
      avatar_url LONGTEXT NULL,
      last_message JSON NULL,
      unread JSON NOT NULL,
      last_read_at JSON NULL,
      pinned_message_id VARCHAR(96) NULL,
      channel_owner_id VARCHAR(96) NULL,
      updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
    )
  `);
  await conn.execute(`
    CREATE TABLE IF NOT EXISTS chat_participants (
      chat_id VARCHAR(96) NOT NULL,
      user_id VARCHAR(96) NOT NULL,
      position INT NOT NULL DEFAULT 0,
      PRIMARY KEY (chat_id, user_id),
      INDEX idx_chat_participants_user (user_id),
      CONSTRAINT fk_chat_participants_chat
        FOREIGN KEY (chat_id) REFERENCES chats(id) ON DELETE CASCADE
    )
  `);
  await conn.execute(`
    CREATE TABLE IF NOT EXISTS messages (
      id VARCHAR(96) PRIMARY KEY,
      chat_id VARCHAR(96) NOT NULL,
      sender_id VARCHAR(96) NOT NULL,
      text LONGTEXT NOT NULL,
      encrypted_text JSON NULL,
      image_url LONGTEXT NULL,
      media_kind VARCHAR(24) NULL,
      media_data_url LONGTEXT NULL,
      media_file_name VARCHAR(512) NULL,
      media_mime_type VARCHAR(191) NULL,
      media_duration_ms INT NULL,
      created_at BIGINT NOT NULL,
      deleted TINYINT(1) NOT NULL DEFAULT 0,
      edited_at BIGINT NULL,
      reply_to_message_id VARCHAR(96) NULL,
      reactions JSON NULL,
      INDEX idx_messages_chat_created (chat_id, created_at),
      CONSTRAINT fk_messages_chat
        FOREIGN KEY (chat_id) REFERENCES chats(id) ON DELETE CASCADE
    )
  `);
  const [encryptedTextColumns] = await conn.execute<mysql.RowDataPacket[]>(
    `
      SELECT COLUMN_NAME
      FROM information_schema.COLUMNS
      WHERE TABLE_SCHEMA = DATABASE()
        AND TABLE_NAME = 'messages'
        AND COLUMN_NAME = 'encrypted_text'
    `
  );
  if (encryptedTextColumns.length === 0) {
    await conn.execute(
      'ALTER TABLE messages ADD COLUMN encrypted_text JSON NULL AFTER text'
    );
  }
  await conn.execute(`
    CREATE TABLE IF NOT EXISTS user_chat_muted (
      user_id VARCHAR(96) NOT NULL,
      chat_id VARCHAR(96) NOT NULL,
      PRIMARY KEY (user_id, chat_id)
    )
  `);
  await conn.execute(`
    CREATE TABLE IF NOT EXISTS user_chat_pinned (
      user_id VARCHAR(96) NOT NULL,
      chat_id VARCHAR(96) NOT NULL,
      PRIMARY KEY (user_id, chat_id)
    )
  `);
  await conn.execute(`
    CREATE TABLE IF NOT EXISTS push_subscriptions (
      user_id VARCHAR(96) NOT NULL,
      endpoint VARCHAR(1024) NOT NULL,
      data JSON NOT NULL,
      PRIMARY KEY (user_id, endpoint(191))
    )
  `);
}

function parseJsonCell<T>(value: unknown, fallback: T): T {
  if (value == null) return fallback;
  if (typeof value === 'string') {
    try {
      return JSON.parse(value) as T;
    } catch {
      return fallback;
    }
  }
  return value as T;
}

async function readStateFromNormalizedMysql(): Promise<PersistedStateV1 | null> {
  const state = await withMysql(async (conn) => {
    const [userRows] = await conn.execute<mysql.RowDataPacket[]>('SELECT * FROM users');
    const [chatRows] = await conn.execute<mysql.RowDataPacket[]>('SELECT * FROM chats');
    if (userRows.length === 0 && chatRows.length === 0) return null;

    const [participantRows] = await conn.execute<mysql.RowDataPacket[]>(
      'SELECT chat_id, user_id FROM chat_participants ORDER BY chat_id, position'
    );
    const [messageRows] = await conn.execute<mysql.RowDataPacket[]>(
      'SELECT * FROM messages ORDER BY chat_id, created_at'
    );
    const [mutedRows] = await conn.execute<mysql.RowDataPacket[]>(
      'SELECT user_id, chat_id FROM user_chat_muted'
    );
    const [pinnedRows] = await conn.execute<mysql.RowDataPacket[]>(
      'SELECT user_id, chat_id FROM user_chat_pinned'
    );
    const [pushRows] = await conn.execute<mysql.RowDataPacket[]>(
      'SELECT user_id, data FROM push_subscriptions'
    );

    const participantsByChat = new Map<string, string[]>();
    for (const row of participantRows) {
      const chatId = String(row.chat_id);
      const arr = participantsByChat.get(chatId) ?? [];
      arr.push(String(row.user_id));
      participantsByChat.set(chatId, arr);
    }

    const messagesByChatMap = new Map<string, PersistedStateV1['messagesByChat'][number][1]>();
    for (const row of messageRows) {
      const chatId = String(row.chat_id);
      const mediaKind = row.media_kind ? String(row.media_kind) : undefined;
      const msg = {
        id: String(row.id),
        chatId,
        senderId: String(row.sender_id),
        text: String(row.text ?? ''),
        encryptedText: parseJsonCell<EncryptedTextEnvelope | undefined>(
          row.encrypted_text,
          undefined
        ),
        imageUrl: row.image_url == null ? undefined : String(row.image_url),
        media: mediaKind
          ? {
              kind: mediaKind as MessageMediaKind,
              dataUrl: String(row.media_data_url ?? ''),
              fileName: row.media_file_name == null ? undefined : String(row.media_file_name),
              mimeType: row.media_mime_type == null ? undefined : String(row.media_mime_type),
              durationMs:
                row.media_duration_ms == null ? undefined : Number(row.media_duration_ms),
            }
          : undefined,
        createdAt: Number(row.created_at),
        deleted: !!row.deleted,
        editedAt: row.edited_at == null ? undefined : Number(row.edited_at),
        replyToMessageId:
          row.reply_to_message_id == null ? undefined : String(row.reply_to_message_id),
        reactions: parseJsonCell(row.reactions, undefined),
      };
      const arr = messagesByChatMap.get(chatId) ?? [];
      arr.push(msg);
      messagesByChatMap.set(chatId, arr);
    }

    const groupPairs = (rows: mysql.RowDataPacket[]) => {
      const map = new Map<string, string[]>();
      for (const row of rows) {
        const userId = String(row.user_id);
        const arr = map.get(userId) ?? [];
        arr.push(String(row.chat_id));
        map.set(userId, arr);
      }
      return [...map.entries()];
    };

    const pushMap = new Map<string, PushSubscriptionData[]>();
    for (const row of pushRows) {
      const userId = String(row.user_id);
      const arr = pushMap.get(userId) ?? [];
      arr.push(parseJsonCell<PushSubscriptionData>(row.data, {
        endpoint: '',
        keys: { p256dh: '', auth: '' },
      }));
      pushMap.set(userId, arr.filter((sub) => sub.endpoint));
    }

    return {
      v: 1,
      users: userRows.map((row) => ({
        id: String(row.id),
        username: String(row.username),
        password: String(row.password),
        email: row.email == null ? undefined : String(row.email),
        emailVerified: !!row.email_verified,
        avatarUrl: row.avatar_url == null ? undefined : String(row.avatar_url),
        displayName: row.display_name == null ? undefined : String(row.display_name),
        bio: row.bio == null ? undefined : String(row.bio),
        phone: row.phone == null ? undefined : String(row.phone),
        birthDate: row.birth_date == null ? undefined : String(row.birth_date),
        isAdmin: !!row.is_admin,
        banned: !!row.banned,
        privacy: parseJsonCell(row.privacy, undefined),
      })),
      chats: chatRows.map((row) => ({
        id: String(row.id),
        type: String(row.type) as PersistedStateV1['chats'][number]['type'],
        name: String(row.name),
        avatarUrl: row.avatar_url == null ? undefined : String(row.avatar_url),
        participantIds: participantsByChat.get(String(row.id)) ?? [],
        lastMessage: parseJsonCell(row.last_message, null),
        unread: parseJsonCell<Record<string, number>>(row.unread, {}),
        lastReadAt: parseJsonCell(row.last_read_at, undefined),
        pinnedMessageId:
          row.pinned_message_id == null ? undefined : String(row.pinned_message_id),
        channelOwnerId:
          row.channel_owner_id == null ? undefined : String(row.channel_owner_id),
      })),
      messagesByChat: [...messagesByChatMap.entries()],
      muted: groupPairs(mutedRows),
      pinned: groupPairs(pinnedRows),
      pushSubscriptions: [...pushMap.entries()],
    } satisfies PersistedStateV1;
  });
  return state;
}

async function readStateFromLegacyMysql(): Promise<PersistedStateV1 | null> {
  const [rows] = await withMysql((conn) =>
    conn.execute<mysql.RowDataPacket[]>(
      'SELECT data FROM app_state WHERE id = ? LIMIT 1',
      [MYSQL_STATE_ID]
    )
  );
  const first = rows[0] as { data?: unknown } | undefined;
  const data =
    typeof first?.data === 'string' ? JSON.parse(first.data) : first?.data;
  if (!isPersistedState(data)) return null;
  return data;
}

async function readStateFromMysql(): Promise<PersistedStateV1 | null> {
  return (await readStateFromNormalizedMysql()) ?? (await readStateFromLegacyMysql());
}

async function flushToMysql(): Promise<void> {
  const state = store.exportPersistedState();
  await withMysql(async (conn) => {
    await conn.beginTransaction();
    try {
      await conn.execute('DELETE FROM push_subscriptions');
      await conn.execute('DELETE FROM user_chat_pinned');
      await conn.execute('DELETE FROM user_chat_muted');
      await conn.execute('DELETE FROM messages');
      await conn.execute('DELETE FROM chat_participants');
      await conn.execute('DELETE FROM chats');
      await conn.execute('DELETE FROM users');

      for (const user of state.users) {
        await conn.execute(
          `
            INSERT INTO users (
              id, username, password, email, email_verified, avatar_url,
              display_name, bio, phone, birth_date, is_admin, banned, privacy
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, CAST(? AS JSON))
          `,
          [
            user.id,
            user.username,
            user.password,
            user.email ?? null,
            user.emailVerified ? 1 : 0,
            user.avatarUrl ?? null,
            user.displayName ?? null,
            user.bio ?? null,
            user.phone ?? null,
            user.birthDate ?? null,
            user.isAdmin ? 1 : 0,
            user.banned ? 1 : 0,
            JSON.stringify(user.privacy ?? null),
          ]
        );
      }

      for (const chat of state.chats) {
        await conn.execute(
          `
            INSERT INTO chats (
              id, type, name, avatar_url, last_message, unread,
              last_read_at, pinned_message_id, channel_owner_id
            )
            VALUES (?, ?, ?, ?, CAST(? AS JSON), CAST(? AS JSON), CAST(? AS JSON), ?, ?)
          `,
          [
            chat.id,
            chat.type,
            chat.name,
            chat.avatarUrl ?? null,
            JSON.stringify(chat.lastMessage ?? null),
            JSON.stringify(chat.unread ?? {}),
            JSON.stringify(chat.lastReadAt ?? null),
            chat.pinnedMessageId ?? null,
            chat.channelOwnerId ?? null,
          ]
        );
        for (const [position, userId] of chat.participantIds.entries()) {
          await conn.execute(
            'INSERT INTO chat_participants (chat_id, user_id, position) VALUES (?, ?, ?)',
            [chat.id, userId, position]
          );
        }
      }

      for (const [, messages] of state.messagesByChat) {
        for (const message of messages) {
          await conn.execute(
            `
              INSERT INTO messages (
                id, chat_id, sender_id, text, encrypted_text, image_url, media_kind,
                media_data_url, media_file_name, media_mime_type, media_duration_ms,
                created_at, deleted, edited_at, reply_to_message_id, reactions
              )
              VALUES (?, ?, ?, ?, CAST(? AS JSON), ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, CAST(? AS JSON))
            `,
            [
              message.id,
              message.chatId,
              message.senderId,
              message.text,
              JSON.stringify(message.encryptedText ?? null),
              message.imageUrl ?? null,
              message.media?.kind ?? null,
              message.media?.dataUrl ?? null,
              message.media?.fileName ?? null,
              message.media?.mimeType ?? null,
              message.media?.durationMs ?? null,
              message.createdAt,
              message.deleted ? 1 : 0,
              message.editedAt ?? null,
              message.replyToMessageId ?? null,
              JSON.stringify(message.reactions ?? null),
            ]
          );
        }
      }

      for (const [userId, chatIds] of state.muted) {
        for (const chatId of chatIds) {
          await conn.execute(
            'INSERT INTO user_chat_muted (user_id, chat_id) VALUES (?, ?)',
            [userId, chatId]
          );
        }
      }
      for (const [userId, chatIds] of state.pinned) {
        for (const chatId of chatIds) {
          await conn.execute(
            'INSERT INTO user_chat_pinned (user_id, chat_id) VALUES (?, ?)',
            [userId, chatId]
          );
        }
      }
      for (const [userId, subscriptions] of state.pushSubscriptions) {
        for (const sub of subscriptions) {
          await conn.execute(
            'INSERT INTO push_subscriptions (user_id, endpoint, data) VALUES (?, ?, CAST(? AS JSON))',
            [userId, sub.endpoint, JSON.stringify(sub)]
          );
        }
      }
      await conn.commit();
    } catch (e) {
      await conn.rollback();
      throw e;
    }
  });
}

export async function bootstrapPersistence(): Promise<void> {
  if (shouldUseMysql()) {
    try {
      const mysqlState = await readStateFromMysql();
      if (mysqlState) {
        store.importPersistedState(mysqlState);
        store.ensureBuiltinAccounts();
        const migratedPasswords = await store.migrateLegacyPasswords();
        if (migratedPasswords > 0) {
          await flushToMysql();
          console.log(
            `[security] пароли переведены в Argon2id: ${migratedPasswords}`
          );
        }
        console.log('[persist] состояние загружено из MySQL');
        return;
      }
      const diskState = readStateFromDisk();
      if (diskState) {
        store.importPersistedState(diskState);
        store.ensureBuiltinAccounts();
        const migratedPasswords = await store.migrateLegacyPasswords();
        await flushToMysql();
        if (migratedPasswords > 0) {
          console.log(
            `[security] пароли переведены в Argon2id: ${migratedPasswords}`
          );
        }
        console.log('[persist] состояние перенесено из JSON в MySQL');
        return;
      }
    } catch (e) {
      console.warn('[persist] MySQL недоступен, пробую JSON:', e);
    }
  }

  try {
    const diskState = readStateFromDisk();
    if (diskState) {
      store.importPersistedState(diskState);
      store.ensureBuiltinAccounts();
      const migratedPasswords = await store.migrateLegacyPasswords();
      if (migratedPasswords > 0) {
        flushToDisk();
        console.log(
          `[security] пароли переведены в Argon2id: ${migratedPasswords}`
        );
      }
      console.log('[persist] состояние загружено из', STATE_FILE);
      return;
    }
  } catch (e) {
    console.warn('[persist] не удалось загрузить файл, старт с демо-данными:', e);
  }
  store.seedDatabase();
}

function flushToDisk(): void {
  try {
    fs.mkdirSync(path.dirname(STATE_FILE), { recursive: true });
    fs.writeFileSync(
      STATE_FILE,
      JSON.stringify(store.exportPersistedState()),
      'utf8'
    );
  } catch (e) {
    console.warn('[persist] сохранение не удалось:', e);
  }
}

export function startPeriodicPersistence(): void {
  const ms = Number(process.env.PERSIST_INTERVAL_MS) || 12_000;
  let flushing = false;
  const flush = (): Promise<void> | void => {
    if (flushing) return undefined;
    flushing = true;
    if (shouldUseMysql()) {
      const promise = flushToMysql()
        .catch((e) => {
          console.warn('[persist] сохранение в MySQL не удалось:', e);
        })
        .finally(() => {
          flushing = false;
        });
      return promise;
    }
    flushToDisk();
    flushing = false;
    return undefined;
  };
  setInterval(flush, ms);
  const onExit = () => {
    const forceExit = setTimeout(() => process.exit(0), 4_000);
    void Promise.resolve(flush()).finally(() => {
      clearTimeout(forceExit);
      process.exit(0);
    });
  };
  process.once('SIGINT', onExit);
  process.once('SIGTERM', onExit);
}

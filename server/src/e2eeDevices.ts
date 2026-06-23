import mysql from 'mysql2/promise';
import './env.js';

export type E2eeDevicePublicKey = {
  userId: string;
  deviceId: string;
  publicKey: string;
  createdAt: number;
  lastSeenAt: number;
};

export type E2eeKeyBackup = {
  version: 1;
  salt: string;
  iv: string;
  ciphertext: string;
  iterations: number;
  updatedAt: number;
};

const MAX_DEVICES_PER_USER = 20;
const devicesByUser = new Map<string, Map<string, E2eeDevicePublicKey>>();
const keyBackupsByUser = new Map<string, E2eeKeyBackup>();

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

function userDevices(userId: string): Map<string, E2eeDevicePublicKey> {
  let devices = devicesByUser.get(userId);
  if (!devices) {
    devices = new Map();
    devicesByUser.set(userId, devices);
  }
  return devices;
}

export function isValidDeviceId(value: unknown): value is string {
  return (
    typeof value === 'string' &&
    value.length >= 8 &&
    value.length <= 96 &&
    /^[A-Za-z0-9_-]+$/.test(value)
  );
}

export function isValidCurve25519PublicKey(
  value: unknown
): value is string {
  if (
    typeof value !== 'string' ||
    value.length < 40 ||
    value.length > 64 ||
    !/^[A-Za-z0-9_-]+$/.test(value)
  ) {
    return false;
  }
  try {
    return Buffer.from(value, 'base64url').length === 32;
  } catch {
    return false;
  }
}

export async function initializeE2eeDevices(): Promise<void> {
  devicesByUser.clear();
  keyBackupsByUser.clear();
  if (!shouldUseMysql()) return;
  await withMysql(async (conn) => {
    await conn.execute(`
      CREATE TABLE IF NOT EXISTS user_e2ee_devices (
        user_id VARCHAR(96) NOT NULL,
        device_id VARCHAR(96) NOT NULL,
        public_key VARCHAR(128) NOT NULL,
        created_at BIGINT NOT NULL,
        last_seen_at BIGINT NOT NULL,
        PRIMARY KEY (user_id, device_id),
        INDEX idx_user_e2ee_devices_seen (last_seen_at)
      )
    `);
    await conn.execute(`
      CREATE TABLE IF NOT EXISTS user_e2ee_key_backups (
        user_id VARCHAR(96) PRIMARY KEY,
        version TINYINT UNSIGNED NOT NULL,
        salt VARCHAR(128) NOT NULL,
        iv VARCHAR(128) NOT NULL,
        ciphertext MEDIUMTEXT NOT NULL,
        iterations INT UNSIGNED NOT NULL,
        updated_at BIGINT NOT NULL
      )
    `);
    const [rows] = await conn.execute<mysql.RowDataPacket[]>(
      `SELECT user_id, device_id, public_key, created_at, last_seen_at
       FROM user_e2ee_devices`
    );
    for (const row of rows) {
      const device: E2eeDevicePublicKey = {
        userId: String(row.user_id),
        deviceId: String(row.device_id),
        publicKey: String(row.public_key),
        createdAt: Number(row.created_at),
        lastSeenAt: Number(row.last_seen_at),
      };
      if (
        isValidDeviceId(device.deviceId) &&
        isValidCurve25519PublicKey(device.publicKey)
      ) {
        userDevices(device.userId).set(device.deviceId, device);
      }
    }
    const [backupRows] = await conn.execute<mysql.RowDataPacket[]>(
      `SELECT user_id, version, salt, iv, ciphertext, iterations, updated_at
       FROM user_e2ee_key_backups`
    );
    for (const row of backupRows) {
      const backup: E2eeKeyBackup = {
        version: 1,
        salt: String(row.salt),
        iv: String(row.iv),
        ciphertext: String(row.ciphertext),
        iterations: Number(row.iterations),
        updatedAt: Number(row.updated_at),
      };
      if (isValidE2eeKeyBackup(backup)) {
        keyBackupsByUser.set(String(row.user_id), backup);
      }
    }
  });
}

export function isValidE2eeKeyBackup(
  value: unknown
): value is E2eeKeyBackup {
  if (!value || typeof value !== 'object') return false;
  const backup = value as Partial<E2eeKeyBackup>;
  return (
    backup.version === 1 &&
    typeof backup.salt === 'string' &&
    backup.salt.length >= 16 &&
    backup.salt.length <= 128 &&
    /^[A-Za-z0-9_-]+$/.test(backup.salt) &&
    typeof backup.iv === 'string' &&
    backup.iv.length >= 12 &&
    backup.iv.length <= 128 &&
    /^[A-Za-z0-9_-]+$/.test(backup.iv) &&
    typeof backup.ciphertext === 'string' &&
    backup.ciphertext.length >= 64 &&
    backup.ciphertext.length <= 4096 &&
    /^[A-Za-z0-9_-]+$/.test(backup.ciphertext) &&
    Number.isInteger(backup.iterations) &&
    (backup.iterations ?? 0) >= 200_000 &&
    (backup.iterations ?? 0) <= 1_000_000 &&
    Number.isFinite(backup.updatedAt)
  );
}

export function getE2eeKeyBackup(
  userId: string
): E2eeKeyBackup | undefined {
  return keyBackupsByUser.get(userId);
}

export async function saveE2eeKeyBackup(
  userId: string,
  value: Omit<E2eeKeyBackup, 'updatedAt'>
): Promise<E2eeKeyBackup> {
  const backup: E2eeKeyBackup = {
    ...value,
    updatedAt: Date.now(),
  };
  if (!isValidE2eeKeyBackup(backup)) {
    throw new Error('Некорректная резервная копия ключа');
  }
  keyBackupsByUser.set(userId, backup);
  if (shouldUseMysql()) {
    await withMysql(async (conn) => {
      await conn.execute(
        `INSERT INTO user_e2ee_key_backups (
           user_id, version, salt, iv, ciphertext, iterations, updated_at
         )
         VALUES (?, ?, ?, ?, ?, ?, ?)
         ON DUPLICATE KEY UPDATE
           version = VALUES(version),
           salt = VALUES(salt),
           iv = VALUES(iv),
           ciphertext = VALUES(ciphertext),
           iterations = VALUES(iterations),
           updated_at = VALUES(updated_at)`,
        [
          userId,
          backup.version,
          backup.salt,
          backup.iv,
          backup.ciphertext,
          backup.iterations,
          backup.updatedAt,
        ]
      );
    });
  }
  return backup;
}

export async function registerE2eeDevice(
  userId: string,
  deviceId: string,
  publicKey: string
): Promise<'created' | 'existing' | 'key-mismatch' | 'limit'> {
  const devices = userDevices(userId);
  const existing = devices.get(deviceId);
  if (existing && existing.publicKey !== publicKey) return 'key-mismatch';
  if (!existing && devices.size >= MAX_DEVICES_PER_USER) return 'limit';

  const now = Date.now();
  const device: E2eeDevicePublicKey = {
    userId,
    deviceId,
    publicKey,
    createdAt: existing?.createdAt ?? now,
    lastSeenAt: now,
  };
  devices.set(deviceId, device);

  if (shouldUseMysql()) {
    await withMysql(async (conn) => {
      await conn.execute(
        `
          INSERT INTO user_e2ee_devices (
            user_id, device_id, public_key, created_at, last_seen_at
          )
          VALUES (?, ?, ?, ?, ?)
          ON DUPLICATE KEY UPDATE last_seen_at = VALUES(last_seen_at)
        `,
        [
          device.userId,
          device.deviceId,
          device.publicKey,
          device.createdAt,
          device.lastSeenAt,
        ]
      );
    });
  }
  return existing ? 'existing' : 'created';
}

export async function removeE2eeDevice(
  userId: string,
  deviceId: string
): Promise<boolean> {
  const removed = userDevices(userId).delete(deviceId);
  if (removed && shouldUseMysql()) {
    await withMysql(async (conn) => {
      await conn.execute(
        'DELETE FROM user_e2ee_devices WHERE user_id = ? AND device_id = ?',
        [userId, deviceId]
      );
    });
  }
  return removed;
}

export function listE2eeDevices(userIds: string[]): E2eeDevicePublicKey[] {
  const result: E2eeDevicePublicKey[] = [];
  for (const userId of userIds) {
    result.push(...(devicesByUser.get(userId)?.values() ?? []));
  }
  return result;
}

export function ownsE2eeDevice(userId: string, deviceId: string): boolean {
  return devicesByUser.get(userId)?.has(deviceId) ?? false;
}

export function isRegisteredE2eeDevice(
  userId: string,
  deviceId: string
): boolean {
  return ownsE2eeDevice(userId, deviceId);
}

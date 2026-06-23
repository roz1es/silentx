import type {
  EncryptedTextEnvelope,
  Message,
} from '@/types';
import * as api from '@/lib/api';

type Sodium = (typeof import('libsodium-wrappers'))['default'];

const DB_NAME = 'brenkschat-e2ee';
const DB_VERSION = 1;
const DEVICE_STORE = 'deviceKeys';
const KNOWN_STORE = 'knownDeviceKeys';
const DIRECTORY_TTL_MS = 30_000;
const BACKUP_PBKDF2_ITERATIONS = 310_000;

type DeviceKeyRecord = {
  userId: string;
  deviceId: string;
  publicKey: string;
  privateKey: string;
};

type KnownDeviceKey = {
  id: string;
  publicKey: string;
};

type DeviceDirectory = Awaited<ReturnType<typeof api.fetchChatE2eeDevices>>;

const directoryCache = new Map<
  string,
  { expiresAt: number; value: DeviceDirectory }
>();
const deviceKeyPromises = new Map<string, Promise<DeviceKeyRecord>>();
let dbPromise: Promise<IDBDatabase> | null = null;
let sodiumPromise: Promise<Sodium> | null = null;

export class E2eeKeyRestoreRequiredError extends Error {
  constructor() {
    super('Требуется восстановить ключ шифрования');
    this.name = 'E2eeKeyRestoreRequiredError';
  }
}

export function isE2eeKeyRestoreRequiredError(
  error: unknown
): error is E2eeKeyRestoreRequiredError {
  return (
    error instanceof E2eeKeyRestoreRequiredError ||
    (error instanceof Error && error.name === 'E2eeKeyRestoreRequiredError')
  );
}

function getSodium(): Promise<Sodium> {
  if (!sodiumPromise) {
    sodiumPromise = import('libsodium-wrappers').then(async ({ default: sodium }) => {
      await sodium.ready;
      return sodium;
    });
  }
  return sodiumPromise;
}

function openDatabase(): Promise<IDBDatabase> {
  if (dbPromise) return dbPromise;
  dbPromise = new Promise((resolve, reject) => {
    const request = indexedDB.open(DB_NAME, DB_VERSION);
    request.onupgradeneeded = () => {
      const db = request.result;
      if (!db.objectStoreNames.contains(DEVICE_STORE)) {
        db.createObjectStore(DEVICE_STORE, { keyPath: 'userId' });
      }
      if (!db.objectStoreNames.contains(KNOWN_STORE)) {
        db.createObjectStore(KNOWN_STORE, { keyPath: 'id' });
      }
    };
    request.onsuccess = () => resolve(request.result);
    request.onerror = () =>
      reject(request.error ?? new Error('Не удалось открыть хранилище ключей'));
  });
  return dbPromise;
}

async function getRecord<T>(
  storeName: string,
  key: IDBValidKey
): Promise<T | undefined> {
  const db = await openDatabase();
  return new Promise((resolve, reject) => {
    const tx = db.transaction(storeName, 'readonly');
    const request = tx.objectStore(storeName).get(key);
    request.onsuccess = () => resolve(request.result as T | undefined);
    request.onerror = () =>
      reject(request.error ?? new Error('Не удалось прочитать ключ'));
  });
}

async function putRecord(storeName: string, value: unknown): Promise<void> {
  const db = await openDatabase();
  await new Promise<void>((resolve, reject) => {
    const tx = db.transaction(storeName, 'readwrite');
    tx.objectStore(storeName).put(value);
    tx.oncomplete = () => resolve();
    tx.onerror = () =>
      reject(tx.error ?? new Error('Не удалось сохранить ключ'));
    tx.onabort = () =>
      reject(tx.error ?? new Error('Сохранение ключа отменено'));
  });
}

function bytesToBase64Url(value: Uint8Array): string {
  let binary = '';
  for (const byte of value) binary += String.fromCharCode(byte);
  return btoa(binary)
    .replaceAll('+', '-')
    .replaceAll('/', '_')
    .replace(/=+$/, '');
}

function base64UrlToBytes(value: string): Uint8Array {
  const base64 = value.replaceAll('-', '+').replaceAll('_', '/');
  const padded = base64.padEnd(Math.ceil(base64.length / 4) * 4, '=');
  const binary = atob(padded);
  return Uint8Array.from(binary, (char) => char.charCodeAt(0));
}

function toArrayBuffer(value: Uint8Array): ArrayBuffer {
  const copy = new Uint8Array(value.byteLength);
  copy.set(value);
  return copy.buffer;
}

async function deriveBackupKey(
  password: string,
  salt: Uint8Array,
  iterations: number
): Promise<CryptoKey> {
  const material = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(password),
    'PBKDF2',
    false,
    ['deriveKey']
  );
  return crypto.subtle.deriveKey(
    {
      name: 'PBKDF2',
      hash: 'SHA-256',
      salt: toArrayBuffer(salt),
      iterations,
    },
    material,
    { name: 'AES-GCM', length: 256 },
    false,
    ['encrypt', 'decrypt']
  );
}

function validDeviceRecord(
  value: unknown,
  userId: string
): value is DeviceKeyRecord {
  if (!value || typeof value !== 'object') return false;
  const record = value as Partial<DeviceKeyRecord>;
  return (
    record.userId === userId &&
    typeof record.deviceId === 'string' &&
    /^[A-Za-z0-9_-]{8,96}$/.test(record.deviceId) &&
    typeof record.publicKey === 'string' &&
    typeof record.privateKey === 'string'
  );
}

async function readUsableLocalDeviceKey(
  userId: string,
  sodium: Sodium
): Promise<DeviceKeyRecord | null> {
  const existing = await getRecord<DeviceKeyRecord>(DEVICE_STORE, userId);
  if (!existing) return null;
  try {
    if (
      fromBase64(sodium, existing.publicKey).length ===
        sodium.crypto_box_PUBLICKEYBYTES &&
      fromBase64(sodium, existing.privateKey).length ===
        sodium.crypto_box_SECRETKEYBYTES
    ) {
      return existing;
    }
  } catch {
    /* Повреждённая локальная запись будет восстановлена из резервной копии. */
  }
  return null;
}

async function encryptDeviceBackup(
  record: DeviceKeyRecord,
  password: string
): Promise<Omit<api.E2eeKeyBackup, 'updatedAt'>> {
  const salt = crypto.getRandomValues(new Uint8Array(16));
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const key = await deriveBackupKey(
    password,
    salt,
    BACKUP_PBKDF2_ITERATIONS
  );
  const additionalData = new TextEncoder().encode(
    `brenkschat:e2ee-backup:v1:${record.userId}`
  );
  const ciphertext = await crypto.subtle.encrypt(
    { name: 'AES-GCM', iv, additionalData },
    key,
    new TextEncoder().encode(JSON.stringify(record))
  );
  return {
    version: 1,
    salt: bytesToBase64Url(salt),
    iv: bytesToBase64Url(iv),
    ciphertext: bytesToBase64Url(new Uint8Array(ciphertext)),
    iterations: BACKUP_PBKDF2_ITERATIONS,
  };
}

async function createDeviceKeyRecord(userId: string): Promise<DeviceKeyRecord> {
  const sodium = await getSodium();
  const pair = sodium.crypto_box_keypair();
  return {
    userId,
    deviceId: crypto.randomUUID().replaceAll('-', ''),
    publicKey: toBase64(sodium, pair.publicKey),
    privateKey: toBase64(sodium, pair.privateKey),
  };
}

async function decryptDeviceBackup(
  backup: api.E2eeKeyBackup,
  userId: string,
  password: string
): Promise<DeviceKeyRecord> {
  const key = await deriveBackupKey(
    password,
    base64UrlToBytes(backup.salt),
    backup.iterations
  );
  const plaintext = await crypto.subtle.decrypt(
    {
      name: 'AES-GCM',
      iv: toArrayBuffer(base64UrlToBytes(backup.iv)),
      additionalData: new TextEncoder().encode(
        `brenkschat:e2ee-backup:v1:${userId}`
      ),
    },
    key,
    toArrayBuffer(base64UrlToBytes(backup.ciphertext))
  );
  const record = JSON.parse(new TextDecoder().decode(plaintext)) as unknown;
  if (!validDeviceRecord(record, userId)) {
    throw new Error('Некорректная копия ключа');
  }
  return record;
}

export async function syncE2eeKeyWithPassword(
  userId: string,
  password: string
): Promise<void> {
  if (!password || !crypto.subtle) return;
  const sodium = await getSodium();
  const local = await readUsableLocalDeviceKey(userId, sodium);
  const { backup } = await api.fetchE2eeKeyBackup();
  if (backup) {
    try {
      const restored = await decryptDeviceBackup(backup, userId, password);
      await putRecord(DEVICE_STORE, restored);
      deviceKeyPromises.set(userId, Promise.resolve(restored));
      await api.registerE2eeDevice(restored.deviceId, restored.publicKey);
      directoryCache.clear();
      return;
    } catch (error) {
      if (!local) {
        throw new Error(
          'Пароль не подошёл к резервной копии ключа. Если пароль менялся, попробуйте старый пароль или сбросьте ключ для новых сообщений.'
        );
      }
    }
  }
  const record = local ?? (await getOrCreateDeviceKey(userId));
  const encrypted = await encryptDeviceBackup(record, password);
  await api.saveE2eeKeyBackup(encrypted);
}

export async function resetE2eeKeyWithPassword(
  userId: string,
  password: string
): Promise<void> {
  if (!password || !crypto.subtle) {
    throw new Error('Введите пароль от аккаунта');
  }
  const record = await createDeviceKeyRecord(userId);
  await putRecord(DEVICE_STORE, record);
  deviceKeyPromises.set(userId, Promise.resolve(record));
  await api.registerE2eeDevice(record.deviceId, record.publicKey);
  const encrypted = await encryptDeviceBackup(record, password);
  await api.saveE2eeKeyBackup(encrypted);
  directoryCache.clear();
}

function toBase64(sodium: Sodium, value: Uint8Array): string {
  return sodium.to_base64(
    value,
    sodium.base64_variants.URLSAFE_NO_PADDING
  );
}

function fromBase64(sodium: Sodium, value: string): Uint8Array {
  return sodium.from_base64(
    value,
    sodium.base64_variants.URLSAFE_NO_PADDING
  );
}

async function loadOrCreateDeviceKey(
  userId: string
): Promise<DeviceKeyRecord> {
  const sodium = await getSodium();
  const existing = await readUsableLocalDeviceKey(userId, sodium);
  if (existing) return existing;

  const { backup } = await api.fetchE2eeKeyBackup();
  if (backup) {
    throw new E2eeKeyRestoreRequiredError();
  }

  const record = await createDeviceKeyRecord(userId);
  await putRecord(DEVICE_STORE, record);
  return record;
}

function getOrCreateDeviceKey(userId: string): Promise<DeviceKeyRecord> {
  const existing = deviceKeyPromises.get(userId);
  if (existing) return existing;
  const pending = loadOrCreateDeviceKey(userId).catch((error) => {
    deviceKeyPromises.delete(userId);
    throw error;
  });
  deviceKeyPromises.set(userId, pending);
  return pending;
}

async function pinDirectoryKeys(directory: DeviceDirectory): Promise<void> {
  for (const device of directory.devices) {
    await pinKnownDeviceKey(device.userId, device.deviceId, device.publicKey);
  }
}

async function fetchDirectory(
  chatId: string,
  force = false
): Promise<DeviceDirectory> {
  const cached = directoryCache.get(chatId);
  if (!force && cached && cached.expiresAt > Date.now()) return cached.value;
  const value = await api.fetchChatE2eeDevices(chatId);
  await pinDirectoryKeys(value);
  directoryCache.set(chatId, {
    expiresAt: Date.now() + DIRECTORY_TTL_MS,
    value,
  });
  return value;
}

async function pinKnownDeviceKey(
  userId: string,
  deviceId: string,
  publicKey: string
): Promise<void> {
  const id = `${userId}:${deviceId}`;
  const known = await getRecord<KnownDeviceKey>(KNOWN_STORE, id);
  if (known && known.publicKey !== publicKey) {
    throw new Error('Ключ устройства собеседника изменился.');
  }
  if (!known) {
    await putRecord(KNOWN_STORE, { id, publicKey });
  }
}

async function readKnownDeviceKey(
  userId: string,
  deviceId: string
): Promise<string | undefined> {
  const known = await getRecord<KnownDeviceKey>(
    KNOWN_STORE,
    `${userId}:${deviceId}`
  );
  return known?.publicKey;
}

function isValidPublicKeyString(sodium: Sodium, value: unknown): value is string {
  if (typeof value !== 'string') return false;
  try {
    return fromBase64(sodium, value).length === sodium.crypto_box_PUBLICKEYBYTES;
  } catch {
    return false;
  }
}

function isTransientE2eeDependencyError(error: unknown): boolean {
  if (isE2eeKeyRestoreRequiredError(error)) return false;
  if (error instanceof TypeError) return true;
  if (error instanceof DOMException) {
    return [
      'AbortError',
      'InvalidStateError',
      'NetworkError',
      'NotReadableError',
      'QuotaExceededError',
      'UnknownError',
    ].includes(error.name);
  }
  if (!(error instanceof Error)) return false;
  const message = error.message.toLowerCase();
  return [
    'failed to fetch',
    'load failed',
    'network',
    'сервер долго не отвечает',
    'требуется авторизация',
    'не удалось открыть хранилище',
    'не удалось прочитать ключ',
    'не удалось сохранить ключ',
    'сохранение ключа отменено',
  ].some((marker) => message.includes(marker));
}

export async function initializeE2eeForUser(
  userId: string
): Promise<void> {
  const device = await getOrCreateDeviceKey(userId);
  await api.registerE2eeDevice(device.deviceId, device.publicKey);
  directoryCache.clear();
}

export async function isDirectTextEncryptionAvailable(
  chatId: string,
  userId: string
): Promise<boolean> {
  await initializeE2eeForUser(userId);
  const directory = await fetchDirectory(chatId, true);
  return directory.participantIds.every((participantId) =>
    directory.devices.some((device) => device.userId === participantId)
  );
}

export async function encryptDirectText(
  chatId: string,
  senderId: string,
  text: string
): Promise<EncryptedTextEnvelope | null> {
  const sodium = await getSodium();
  const senderDevice = await getOrCreateDeviceKey(senderId);
  await api.registerE2eeDevice(
    senderDevice.deviceId,
    senderDevice.publicKey
  );
  const directory = await fetchDirectory(chatId, true);
  for (const participantId of directory.participantIds) {
    if (!directory.devices.some((device) => device.userId === participantId)) {
      if (participantId === senderId) {
        throw new Error('Не удалось зарегистрировать ключ этого устройства');
      }
      return null;
    }
  }

  const payload = sodium.from_string(
    JSON.stringify({
      version: 1,
      chatId,
      senderId,
      senderDeviceId: senderDevice.deviceId,
      text,
    })
  );
  const senderPrivateKey = fromBase64(sodium, senderDevice.privateKey);
  const recipients = directory.devices.map((device) => {
    const nonce = sodium.randombytes_buf(sodium.crypto_box_NONCEBYTES);
    const ciphertext = sodium.crypto_box_easy(
      payload,
      nonce,
      fromBase64(sodium, device.publicKey),
      senderPrivateKey
    );
    return {
      userId: device.userId,
      deviceId: device.deviceId,
      nonce: toBase64(sodium, nonce),
      ciphertext: toBase64(sodium, ciphertext),
    };
  });

  return {
    version: 1,
    algorithm: 'crypto_box_curve25519xsalsa20poly1305',
    senderDeviceId: senderDevice.deviceId,
    senderPublicKey: senderDevice.publicKey,
    recipients,
  };
}

async function failedMessage(
  message: Message,
  state: 'pending' | 'recovering' | 'failed' = 'failed'
): Promise<Message> {
  return {
    ...message,
    text:
      state === 'pending'
        ? 'Пробуем расшифровать сообщение…'
        : state === 'recovering'
        ? 'Ожидается восстановление ключа шифрования'
        : 'Не удалось расшифровать защищённое сообщение',
    encryptionState: state,
  };
}

export async function decryptMessage(
  message: Message,
  viewerId: string
): Promise<Message> {
  const envelope = message.encryptedText;
  if (!envelope) return message;
  try {
    const sodium = await getSodium();
    const viewerDevice = await getOrCreateDeviceKey(viewerId);
    const recipient = envelope.recipients.find(
      (item) =>
        item.userId === viewerId &&
        item.deviceId === viewerDevice.deviceId
    );
    if (!recipient) return failedMessage(message);

    let directory = await fetchDirectory(message.chatId);
    let senderDevice = directory.devices.find(
      (device) =>
        device.userId === message.senderId &&
        device.deviceId === envelope.senderDeviceId
    );
    if (!senderDevice) {
      directory = await fetchDirectory(message.chatId, true);
      senderDevice = directory.devices.find(
        (device) =>
          device.userId === message.senderId &&
          device.deviceId === envelope.senderDeviceId
      );
    }
    const senderPublicKey =
      senderDevice?.publicKey ??
      envelope.senderPublicKey ??
      (await readKnownDeviceKey(message.senderId, envelope.senderDeviceId));
    if (!isValidPublicKeyString(sodium, senderPublicKey)) {
      return failedMessage(message);
    }
    await pinKnownDeviceKey(
      message.senderId,
      envelope.senderDeviceId,
      senderPublicKey
    );

    const opened = sodium.crypto_box_open_easy(
      fromBase64(sodium, recipient.ciphertext),
      fromBase64(sodium, recipient.nonce),
      fromBase64(sodium, senderPublicKey),
      fromBase64(sodium, viewerDevice.privateKey)
    );
    const payload = JSON.parse(sodium.to_string(opened)) as {
      version?: number;
      chatId?: string;
      senderId?: string;
      senderDeviceId?: string;
      text?: string;
    };
    if (
      payload.version !== 1 ||
      payload.chatId !== message.chatId ||
      payload.senderId !== message.senderId ||
      payload.senderDeviceId !== envelope.senderDeviceId ||
      typeof payload.text !== 'string'
    ) {
      return failedMessage(message);
    }
    return {
      ...message,
      text: payload.text,
      encryptionState: 'encrypted',
    };
  } catch (error) {
    if (isE2eeKeyRestoreRequiredError(error)) {
      return failedMessage(message, 'recovering');
    }
    if (isTransientE2eeDependencyError(error)) {
      return failedMessage(message, 'pending');
    }
    return failedMessage(message);
  }
}

export async function decryptMessages(
  messages: Message[],
  viewerId: string
): Promise<Message[]> {
  return Promise.all(
    messages.map((message) => decryptMessage(message, viewerId))
  );
}

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import type { PersistedStateV1 } from './store.js';
import * as store from './store.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const STATE_FILE = path.join(__dirname, '..', 'data', 'silentix-state.json');

export function bootstrapPersistence(): void {
  try {
    if (fs.existsSync(STATE_FILE)) {
      const raw = JSON.parse(
        fs.readFileSync(STATE_FILE, 'utf8')
      ) as PersistedStateV1;
      if (raw?.v === 1 && Array.isArray(raw.users) && Array.isArray(raw.chats)) {
        store.importPersistedState(raw);
        store.ensureBuiltinAccounts();
        console.log('[persist] состояние загружено из', STATE_FILE);
        return;
      }
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
  setInterval(flushToDisk, ms);
  const onExit = () => {
    flushToDisk();
    process.exit(0);
  };
  process.once('SIGINT', onExit);
  process.once('SIGTERM', onExit);
}

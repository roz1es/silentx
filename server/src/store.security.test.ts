import assert from 'node:assert/strict';
import test from 'node:test';
import { DISABLED_PASSWORD, isPasswordHash, verifyPassword } from './password.js';
import * as store from './store.js';

test('migrates legacy credentials without resetting administrator passwords', async () => {
  store.importPersistedState({
    v: 1,
    users: [
      {
        id: 'user-admin-roz1es',
        username: 'roz1es',
        password: 'old-admin-password',
        isAdmin: true,
      },
      {
        id: 'user-regular',
        username: 'regular',
        password: 'old-user-password',
      },
      {
        id: 'user-bot',
        username: 'brenkschat',
        password: '',
      },
    ],
    chats: [],
    messagesByChat: [],
    muted: [],
    pinned: [],
    pushSubscriptions: [],
  });

  store.ensureBuiltinAccounts();
  assert.equal(await store.migrateLegacyPasswords(), 2);

  const state = store.exportPersistedState();
  const admin = state.users.find((user) => user.id === 'user-admin-roz1es');
  const regular = state.users.find((user) => user.id === 'user-regular');
  const bot = state.users.find((user) => user.id === 'user-bot');
  const missingAdmin = state.users.find((user) => user.id === 'user-admin-elzi');

  assert.ok(admin && isPasswordHash(admin.password));
  assert.ok(regular && isPasswordHash(regular.password));
  assert.equal(bot?.password, DISABLED_PASSWORD);
  assert.equal(missingAdmin?.password, DISABLED_PASSWORD);
  assert.equal((await verifyPassword(admin.password, 'old-admin-password')).valid, true);
  assert.equal((await verifyPassword(regular.password, 'old-user-password')).valid, true);

  const adminHash = admin.password;
  store.ensureBuiltinAccounts();
  assert.equal(store.getUser(admin.id)?.password, adminHash);
});

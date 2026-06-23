import assert from 'node:assert/strict';
import test from 'node:test';
import {
  clearSessionStoreForTests,
  createAuthSession,
  getActiveSession,
  REMEMBERED_SESSION_TTL_MS,
  SHORT_SESSION_TTL_MS,
} from './sessions.js';

test('creates isolated active sessions', async () => {
  clearSessionStoreForTests();
  const first = await createAuthSession('user-a', false);
  const second = await createAuthSession('user-a', false);

  assert.notEqual(first.id, second.id);
  assert.equal(getActiveSession(first.id)?.userId, 'user-a');
  assert.equal(getActiveSession(second.id)?.userId, 'user-a');
  assert.ok(first.expiresAt > first.createdAt);
});

test('uses a longer bounded session only for remembered devices', async () => {
  clearSessionStoreForTests();
  const short = await createAuthSession(
    'user-short',
    false,
    SHORT_SESSION_TTL_MS
  );
  const remembered = await createAuthSession(
    'user-remembered',
    false,
    REMEMBERED_SESSION_TTL_MS
  );
  const excessive = await createAuthSession(
    'user-excessive',
    false,
    REMEMBERED_SESSION_TTL_MS * 10
  );

  assert.equal(short.expiresAt - short.createdAt, SHORT_SESSION_TTL_MS);
  assert.equal(
    remembered.expiresAt - remembered.createdAt,
    REMEMBERED_SESSION_TTL_MS
  );
  assert.equal(
    excessive.expiresAt - excessive.createdAt,
    REMEMBERED_SESSION_TTL_MS
  );
});

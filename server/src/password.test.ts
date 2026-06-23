import assert from 'node:assert/strict';
import test from 'node:test';
import {
  DISABLED_PASSWORD,
  hashPassword,
  isAcceptableNewPassword,
  isPasswordHash,
  verifyPassword,
} from './password.js';

test('hashes and verifies passwords with Argon2id', async () => {
  const hash = await hashPassword('correct horse battery staple');
  assert.equal(isPasswordHash(hash), true);
  assert.deepEqual(await verifyPassword(hash, 'correct horse battery staple'), {
    valid: true,
    needsRehash: false,
  });
  assert.equal((await verifyPassword(hash, 'wrong password')).valid, false);
});

test('accepts a valid legacy password only for migration', async () => {
  assert.deepEqual(await verifyPassword('legacy-weak-password', 'legacy-weak-password'), {
    valid: true,
    needsRehash: true,
  });
  assert.equal((await verifyPassword('legacy-weak-password', 'wrong')).valid, false);
});

test('never permits disabled accounts and validates new password length', async () => {
  assert.equal((await verifyPassword(DISABLED_PASSWORD, '')).valid, false);
  assert.equal(isAcceptableNewPassword('short'), false);
  assert.equal(isAcceptableNewPassword('long-enough'), true);
});

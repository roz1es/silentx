import assert from 'node:assert/strict';
import test from 'node:test';
import {
  isValidCurve25519PublicKey,
  isValidDeviceId,
  isValidE2eeKeyBackup,
  listE2eeDevices,
  registerE2eeDevice,
} from './e2eeDevices.js';

test('validates and registers immutable Curve25519 device keys', async () => {
  const userId = `e2ee-test-${Date.now()}`;
  const deviceId = 'device_test_12345678';
  const publicKey = Buffer.alloc(32, 7).toString('base64url');
  const otherKey = Buffer.alloc(32, 9).toString('base64url');

  assert.equal(isValidDeviceId(deviceId), true);
  assert.equal(isValidCurve25519PublicKey(publicKey), true);
  assert.equal(isValidCurve25519PublicKey('not-a-key'), false);
  assert.equal(
    await registerE2eeDevice(userId, deviceId, publicKey),
    'created'
  );
  assert.equal(
    await registerE2eeDevice(userId, deviceId, publicKey),
    'existing'
  );
  assert.equal(
    await registerE2eeDevice(userId, deviceId, otherKey),
    'key-mismatch'
  );
  assert.deepEqual(
    listE2eeDevices([userId]).map(({ deviceId: id, publicKey: key }) => ({
      id,
      key,
    })),
    [{ id: deviceId, key: publicKey }]
  );
});

test('accepts only bounded encrypted E2EE key backups', () => {
  const backup = {
    version: 1 as const,
    salt: Buffer.alloc(16, 1).toString('base64url'),
    iv: Buffer.alloc(12, 2).toString('base64url'),
    ciphertext: Buffer.alloc(96, 3).toString('base64url'),
    iterations: 310_000,
    updatedAt: Date.now(),
  };
  assert.equal(isValidE2eeKeyBackup(backup), true);
  assert.equal(
    isValidE2eeKeyBackup({ ...backup, iterations: 1_000 }),
    false
  );
  assert.equal(
    isValidE2eeKeyBackup({ ...backup, ciphertext: '<script>' }),
    false
  );
});

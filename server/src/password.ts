import crypto from 'node:crypto';
import argon2 from 'argon2';

export const PASSWORD_MIN_LENGTH = 8;
export const PASSWORD_MAX_LENGTH = 128;
export const DISABLED_PASSWORD = '!disabled';

const ARGON2_OPTIONS = {
  type: argon2.argon2id,
  memoryCost: 19_456,
  timeCost: 2,
  parallelism: 1,
} as const;

export function isPasswordHash(value: string): boolean {
  return value.startsWith('$argon2id$');
}

export function isAcceptableNewPassword(value: unknown): value is string {
  return (
    typeof value === 'string' &&
    value.length >= PASSWORD_MIN_LENGTH &&
    value.length <= PASSWORD_MAX_LENGTH
  );
}

export async function hashPassword(password: string): Promise<string> {
  return argon2.hash(password, ARGON2_OPTIONS);
}

function safeLegacyCompare(stored: string, supplied: string): boolean {
  const storedBuffer = Buffer.from(stored);
  const suppliedBuffer = Buffer.from(supplied);
  return (
    storedBuffer.length === suppliedBuffer.length &&
    crypto.timingSafeEqual(storedBuffer, suppliedBuffer)
  );
}

export async function verifyPassword(
  stored: string,
  supplied: string
): Promise<{ valid: boolean; needsRehash: boolean }> {
  if (!stored || stored === DISABLED_PASSWORD) {
    return { valid: false, needsRehash: false };
  }

  if (!isPasswordHash(stored)) {
    const valid = safeLegacyCompare(stored, supplied);
    return { valid, needsRehash: valid };
  }

  try {
    const valid = await argon2.verify(stored, supplied);
    return {
      valid,
      needsRehash: valid && argon2.needsRehash(stored, ARGON2_OPTIONS),
    };
  } catch {
    return { valid: false, needsRehash: false };
  }
}

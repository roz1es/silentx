import { randomInt } from 'node:crypto';
import { v4 as uuid } from 'uuid';

const CODE_TTL_MS = 10 * 60 * 1000;
const MAX_ATTEMPTS = 5;

export type EmailPurpose = 'login' | 'register' | 'reset' | 'bind';

type BaseChallenge = {
  code: string;
  expiresAt: number;
  attempts: number;
};

export type LoginChallenge = BaseChallenge & {
  purpose: 'login';
  userId: string;
};

export type RegisterChallenge = BaseChallenge & {
  purpose: 'register';
  username: string;
  passwordHash: string;
  email: string;
};

export type ResetChallenge = BaseChallenge & {
  purpose: 'reset';
  userId: string;
};

export type BindEmailChallenge = BaseChallenge & {
  purpose: 'bind';
  userId: string;
  email: string;
};

export type EmailChallenge =
  | LoginChallenge
  | RegisterChallenge
  | ResetChallenge
  | BindEmailChallenge;

const challenges = new Map<string, EmailChallenge>();

export function normalizeEmail(email: string): string {
  return email.trim().toLowerCase();
}

export function isValidEmail(email: string): boolean {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email.trim());
}

export function maskEmail(email: string): string {
  const normalized = normalizeEmail(email);
  const [name, domain] = normalized.split('@');
  if (!name || !domain) return normalized;
  const visible = name.length <= 2 ? name[0] ?? '*' : name.slice(0, 2);
  return `${visible}${'*'.repeat(Math.max(2, name.length - visible.length))}@${domain}`;
}

function createCode(): string {
  return String(randomInt(100000, 1000000));
}

function cleanupExpired(): void {
  const now = Date.now();
  for (const [ticket, challenge] of challenges) {
    if (challenge.expiresAt <= now) challenges.delete(ticket);
  }
}

type ChallengeInput =
  | Omit<LoginChallenge, 'code' | 'expiresAt' | 'attempts'>
  | Omit<RegisterChallenge, 'code' | 'expiresAt' | 'attempts'>
  | Omit<ResetChallenge, 'code' | 'expiresAt' | 'attempts'>
  | Omit<BindEmailChallenge, 'code' | 'expiresAt' | 'attempts'>;

export function createChallenge(
  challenge: ChallengeInput
): { ticket: string; code: string } {
  cleanupExpired();
  const ticket = uuid();
  const code = createCode();
  challenges.set(ticket, {
    ...challenge,
    code,
    expiresAt: Date.now() + CODE_TTL_MS,
    attempts: 0,
  } as EmailChallenge);
  return { ticket, code };
}

export function consumeChallenge<T extends EmailPurpose>(
  ticket: string,
  code: string,
  purpose: T
): Extract<EmailChallenge, { purpose: T }> | null {
  cleanupExpired();
  const challenge = challenges.get(ticket);
  if (!challenge || challenge.purpose !== purpose) return null;
  if (challenge.attempts >= MAX_ATTEMPTS) {
    challenges.delete(ticket);
    return null;
  }
  challenge.attempts += 1;
  if (challenge.code !== code.trim()) return null;
  challenges.delete(ticket);
  return challenge as Extract<EmailChallenge, { purpose: T }>;
}

export function consumeLoginChallenge(ticket: string, code: string): LoginChallenge | null {
  cleanupExpired();
  const challenge = challenges.get(ticket);
  if (!challenge || challenge.purpose !== 'login') return null;
  if (challenge.attempts >= MAX_ATTEMPTS) {
    challenges.delete(ticket);
    return null;
  }
  challenge.attempts += 1;
  const cleanCode = code.trim();
  if (challenge.code === cleanCode) {
    challenges.delete(ticket);
    return challenge;
  }

  for (const [otherTicket, otherChallenge] of challenges) {
    if (
      otherTicket !== ticket &&
      otherChallenge.purpose === 'login' &&
      otherChallenge.userId === challenge.userId &&
      otherChallenge.code === cleanCode
    ) {
      challenges.delete(ticket);
      challenges.delete(otherTicket);
      return otherChallenge;
    }
  }

  return null;
}

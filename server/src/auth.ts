import './env.js';
import jwt from 'jsonwebtoken';
import type { Request, Response, NextFunction } from 'express';
import * as store from './store.js';
import {
  createAuthSession,
  getActiveSession,
  REMEMBERED_SESSION_TTL_MS,
  revokeAuthSession,
  SHORT_SESSION_TTL_MS,
} from './sessions.js';

export const AUTH_COOKIE_NAME = 'brenks_session';

function jwtSecret(): string {
  const fromEnv = process.env.JWT_SECRET;
  if (fromEnv && fromEnv.length >= 16) return fromEnv;
  if (process.env.NODE_ENV === 'production') {
    throw new Error(
      'JWT_SECRET must be set to a string of at least 16 characters in production'
    );
  }
  return 'dev-only-insecure-secret';
}

const SECRET = jwtSecret();

export async function issueUserToken(
  userId: string,
  rememberMe = false
): Promise<string> {
  const ttlMs = rememberMe
    ? REMEMBERED_SESSION_TTL_MS
    : SHORT_SESSION_TTL_MS;
  const session = await createAuthSession(userId, true, ttlMs);
  return jwt.sign({ sub: userId, sid: session.id }, SECRET, {
    expiresIn: Math.floor(ttlMs / 1000),
  });
}

export type AuthenticatedToken = {
  userId: string;
  sessionId: string;
};

export function verifyUserToken(token: string): AuthenticatedToken | null {
  try {
    const decoded = jwt.verify(token, SECRET) as jwt.JwtPayload;
    if (typeof decoded.sub !== 'string' || typeof decoded.sid !== 'string') {
      return null;
    }
    const session = getActiveSession(decoded.sid);
    if (!session || session.userId !== decoded.sub) return null;
    return { userId: decoded.sub, sessionId: decoded.sid };
  } catch {
    return null;
  }
}

function parseCookie(cookieHeader: string | undefined, name: string): string | undefined {
  if (!cookieHeader) return undefined;
  for (const part of cookieHeader.split(';')) {
    const eq = part.indexOf('=');
    if (eq < 0) continue;
    const key = part.slice(0, eq).trim();
    if (key !== name) continue;
    try {
      return decodeURIComponent(part.slice(eq + 1).trim());
    } catch {
      return undefined;
    }
  }
  return undefined;
}

export function tokenFromRequest(req: Request): string | undefined {
  const cookieToken = parseCookie(req.headers.cookie, AUTH_COOKIE_NAME);
  if (cookieToken) return cookieToken;
  const hdr = req.headers.authorization;
  return typeof hdr === 'string' && hdr.startsWith('Bearer ')
    ? hdr.slice(7).trim()
    : undefined;
}

export function tokenFromCookieHeader(cookieHeader: string | undefined): string | undefined {
  return parseCookie(cookieHeader, AUTH_COOKIE_NAME);
}

export async function revokeTokenSession(token: string | undefined): Promise<void> {
  if (!token) return;
  const authenticated = verifyUserToken(token);
  if (authenticated) await revokeAuthSession(authenticated.sessionId);
}

export function requireAuth(
  req: Request,
  res: Response,
  next: NextFunction
): void {
  const token = tokenFromRequest(req);
  if (!token) {
    res.status(401).json({ error: 'Требуется авторизация' });
    return;
  }
  const authenticated = verifyUserToken(token);
  const user = authenticated
    ? store.getUser(authenticated.userId)
    : undefined;
  if (!authenticated || !user) {
    res
      .status(401)
      .json({ error: 'Недействительный или просроченный токен' });
    return;
  }
  if (user.banned) {
    res.status(403).json({ error: 'Аккаунт заблокирован' });
    return;
  }
  req.userId = authenticated.userId;
  req.sessionId = authenticated.sessionId;
  next();
}

export function requireAdmin(
  req: Request,
  res: Response,
  next: NextFunction
): void {
  const userId = req.userId;
  if (!userId) {
    res.status(401).json({ error: 'Требуется авторизация' });
    return;
  }
  const u = store.getUser(userId);
  if (!u?.isAdmin) {
    res.status(403).json({ error: 'Недостаточно прав' });
    return;
  }
  next();
}

declare global {
  namespace Express {
    interface Request {
      userId?: string;
      sessionId?: string;
    }
  }
}

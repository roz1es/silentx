import jwt from 'jsonwebtoken';
import type { Request, Response, NextFunction } from 'express';
import * as store from './store.js';

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

export function signUserToken(userId: string): string {
  return jwt.sign({ sub: userId }, SECRET, { expiresIn: '7d' });
}

export function verifyUserToken(token: string): string | null {
  try {
    const decoded = jwt.verify(token, SECRET) as jwt.JwtPayload;
    return typeof decoded.sub === 'string' ? decoded.sub : null;
  } catch {
    return null;
  }
}

export function requireAuth(
  req: Request,
  res: Response,
  next: NextFunction
): void {
  const hdr = req.headers.authorization;
  const token =
    typeof hdr === 'string' && hdr.startsWith('Bearer ')
      ? hdr.slice(7).trim()
      : undefined;
  if (!token) {
    res.status(401).json({ error: 'Требуется авторизация' });
    return;
  }
  const userId = verifyUserToken(token);
  if (!userId || !store.getUser(userId)) {
    res
      .status(401)
      .json({ error: 'Недействительный или просроченный токен' });
    return;
  }
  req.userId = userId;
  next();
}

declare global {
  namespace Express {
    interface Request {
      userId?: string;
    }
  }
}

import { createHash, randomBytes, timingSafeEqual } from 'node:crypto';

import { hash as argonHash, verify as argonVerify } from '@node-rs/argon2';

/** Minimum password length from 02 §5. */
export const minPasswordLength = 12;

/** Failed attempts before a temporary lock (02 §5). */
export const maxFailedLogins = 5;

/** Lock duration after too many failures (02 §5). */
export const lockDurationMs = 15 * 60 * 1000;

/** Session lifetime (02 §3). */
export const sessionLifetimeMs = 14 * 24 * 60 * 60 * 1000;

export const sessionCookieName = 'qs_session';

export class PasswordPolicyError extends Error {}

export function assertPasswordPolicy(password: string): void {
  if (password.length < minPasswordLength) {
    throw new PasswordPolicyError(
      `Password must be at least ${minPasswordLength} characters.`,
    );
  }
}

/** argon2id hash of a password (02 §5). */
export function hashPassword(password: string): Promise<string> {
  return argonHash(password, { algorithm: 2 /* argon2id */ });
}

/** Constant-time password check; a malformed hash counts as a mismatch. */
export async function verifyPassword(
  passwordHash: string,
  password: string,
): Promise<boolean> {
  try {
    return await argonVerify(passwordHash, password);
  } catch {
    return false;
  }
}

/** 32 random bytes as an opaque session token (02 §3). */
export function newSessionToken(): string {
  return randomBytes(32).toString('base64url');
}

/** New CSRF token, echoed by the browser on writes (02 §5). */
export function newCsrfToken(): string {
  return randomBytes(32).toString('base64url');
}

/**
 * Session ids are stored only as a hash, so a database leak cannot be replayed
 * as a cookie (02 §3).
 */
export function hashSessionToken(token: string): string {
  return createHash('sha256').update(token).digest('hex');
}

/** Constant-time comparison for CSRF tokens of equal length. */
export function safeEqual(a: string, b: string): boolean {
  const left = Buffer.from(a, 'utf8');
  const right = Buffer.from(b, 'utf8');
  if (left.length !== right.length) return false;
  return timingSafeEqual(left, right);
}

/**
 * Daily, rotating IP hash for rate limiting only (02 §4): no full IP is
 * stored, and the salt changes every day.
 */
export function dailyIpHash(ip: string, now: Date = new Date()): string {
  const day = now.toISOString().slice(0, 10);
  return createHash('sha256').update(`${day}:${ip}`).digest('hex');
}

export interface LoginState {
  failedLoginCount: number;
  lockedUntil: Date | null;
}

export type LoginDecision =
  | { allowed: true }
  | { allowed: false; reason: 'locked'; until: Date };

/**
 * Whether an account may attempt a login right now (02 §5).
 *
 * The driver may hand back a timestamptz as a string, so the comparison goes
 * through `toDate` rather than relying on the declared type.
 */
export function loginAllowed(state: LoginState, now: Date = new Date()): LoginDecision {
  const until = toDate(state.lockedUntil);
  if (until && until > now) {
    return { allowed: false, reason: 'locked', until };
  }
  return { allowed: true };
}

/** Normalises a driver timestamp (Date or ISO-ish string) to a Date. */
export function toDate(value: Date | string | null | undefined): Date | null {
  if (!value) return null;
  if (value instanceof Date) return Number.isNaN(value.getTime()) ? null : value;
  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime()) ? null : parsed;
}

/**
 * The account state after a failed attempt: the fifth failure inside the
 * window locks the account for 15 minutes and resets the counter.
 */
export function afterFailedLogin(
  state: LoginState,
  now: Date = new Date(),
): LoginState & { locked: boolean } {
  const count = state.failedLoginCount + 1;
  if (count >= maxFailedLogins) {
    return {
      failedLoginCount: 0,
      lockedUntil: new Date(now.getTime() + lockDurationMs),
      locked: true,
    };
  }
  return { failedLoginCount: count, lockedUntil: null, locked: false };
}

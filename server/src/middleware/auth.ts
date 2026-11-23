import type { Database } from '../db/client.js';
import { sessionCookieName, safeEqual } from '../services/auth.js';
import type { ActiveSession, Role, SessionStore } from '../services/sessions.js';
import type { Context, MiddlewareHandler } from 'hono';
import { getCookie } from 'hono/cookie';

/** Set by `requireSession` and read by every authenticated handler. */
export type AdminContext = Context<{
  Variables: { session: ActiveSession };
}>;

/** Methods that change state and therefore require a CSRF token (02 §5). */
const writeMethods = new Set(['POST', 'PUT', 'PATCH', 'DELETE']);

const csrfHeader = 'X-CSRF-Token';

/**
 * Requires a live session cookie on every `/admin/api` route except login.
 * Rejects with the contract's error shape (01 §2.3).
 */
export function requireSession(
  sessions: SessionStore,
): MiddlewareHandler<{ Variables: { session: ActiveSession } }> {
  return async (c, next) => {
    const token = getCookie(c, sessionCookieName);
    if (!token) return unauthorized(c);

    const session = await sessions.find(token);
    if (!session) return unauthorized(c);

    c.set('session', session);
    await next();
  };
}

/**
 * Rejects a state-changing request whose `X-CSRF-Token` does not match the
 * session's token (02 §5).
 */
export function requireCsrf(): MiddlewareHandler<{ Variables: { session: ActiveSession } }> {
  return async (c, next) => {
    if (!writeMethods.has(c.req.method)) return next();

    const session = c.get('session');
    const provided = c.req.header(csrfHeader);
    if (!session || !provided || !safeEqual(provided, session.csrfToken)) {
      return c.json(
        { error: { code: 'invalid_request', message: 'Missing or invalid CSRF token.' } },
        403,
      );
    }
    await next();
  };
}

/** Restricts a route to specific roles (02 §5). */
export function requireRole(
  ...roles: Role[]
): MiddlewareHandler<{ Variables: { session: ActiveSession } }> {
  return async (c, next) => {
    const session = c.get('session');
    if (!session || !roles.includes(session.user.role)) {
      return c.json({ error: { code: 'not_found', message: 'Not allowed.' } }, 403);
    }
    await next();
  };
}

export function unauthorized(c: Context) {
  return c.json(
    { error: { code: 'not_found', message: 'Authentication required.' } },
    401,
  );
}

export type { Database };

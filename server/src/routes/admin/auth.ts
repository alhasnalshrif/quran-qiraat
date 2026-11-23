import { Hono, type Context } from 'hono';
import { deleteCookie, getCookie, setCookie } from 'hono/cookie';

import type { Database } from '../../db/client.js';
import {
  afterFailedLogin,
  dailyIpHash,
  loginAllowed,
  sessionCookieName,
  toDate,
  verifyPassword,
} from '../../services/auth.js';
import type { ActiveSession, SessionStore, Role } from '../../services/sessions.js';

export interface AuthRoutesOptions {
  sql: Database;
  sessions: SessionStore;
  /** Set the cookie Secure flag; false only for local HTTP development. */
  secureCookies: boolean;
  now?: (() => Date) | undefined;
}

interface UserRow {
  id: string;
  email: string;
  password_hash: string;
  role: Role;
  disabled: boolean;
  failed_login_count: number;
  locked_until: Date | string | null;
}

/**
 * `POST /login`, `POST /logout` and `GET /me` (02 §5). Login is the only
 * unauthenticated route; everything else is mounted behind `requireSession`.
 */
export function authRoutes(
  options: AuthRoutesOptions,
): Hono<{ Variables: { session: ActiveSession } }> {
  const app = new Hono<{ Variables: { session: ActiveSession } }>();
  const { sql, sessions, secureCookies } = options;
  const now = options.now ?? (() => new Date());

  app.post('/login', async (c) => {
    const body = await readJson(c);
    const email = typeof body.email === 'string' ? body.email.trim().toLowerCase() : '';
    const password = typeof body.password === 'string' ? body.password : '';
    if (!email || !password) {
      return c.json(
        { error: { code: 'invalid_request', message: 'Email and password are required.' } },
        400,
      );
    }

    await sessions.pruneExpired(now());
    await sessions.pruneIpHashes(now());

    const rows = await sql<UserRow[]>`
      select id, email, password_hash, role, disabled, failed_login_count, locked_until
      from admin_users where email = ${email} limit 1
    `;
    const user = rows[0];

    // Same answer for unknown email, disabled account and wrong password.
    if (!user || user.disabled) return loginFailed(c);

    const state = {
      failedLoginCount: user.failed_login_count,
      lockedUntil: toDate(user.locked_until),
    };

    const decision = loginAllowed(state, now());
    if (!decision.allowed) {
      return c.json(
        {
          error: {
            code: 'invalid_request',
            message: `Too many attempts. Try again after ${decision.until.toISOString()}.`,
          },
        },
        429,
      );
    }

    if (!(await verifyPassword(user.password_hash, password))) {
      const next = afterFailedLogin(state, now());
      await sql`
        update admin_users
        set failed_login_count = ${next.failedLoginCount},
            locked_until = ${next.lockedUntil ? next.lockedUntil.toISOString() : null}::timestamptz
        where id = ${user.id}
      `;
      return loginFailed(c);
    }

    await sql`
      update admin_users
      set failed_login_count = 0, locked_until = null, last_login_at = ${now().toISOString()}::timestamptz
      where id = ${user.id}
    `;

    const forwarded = c.req.header('x-forwarded-for')?.split(',')[0]?.trim();
    const ip = forwarded ?? c.req.header('x-real-ip') ?? '';
    const session = await sessions.create(
      { id: user.id, email: user.email, role: user.role },
      { ipHash: ip ? dailyIpHash(ip, now()) : undefined, now: now() },
    );

    setCookie(c, sessionCookieName, session.token, {
      httpOnly: true,
      secure: secureCookies,
      sameSite: 'Strict',
      path: '/',
      maxAge: Math.floor((session.expiresAt.getTime() - now().getTime()) / 1000),
    });

    return c.json({
      user: { email: session.user.email, role: session.user.role },
      csrfToken: session.csrfToken,
    });
  });

  app.post('/logout', async (c) => {
    const token = getCookie(c, sessionCookieName);
    if (token) await sessions.destroy(token);
    deleteCookie(c, sessionCookieName, { path: '/' });
    return c.json({ ok: true });
  });

  return app;
}

function loginFailed(c: Context) {
  return c.json(
    { error: { code: 'invalid_request', message: 'Wrong email or password.' } },
    401,
  );
}

async function readJson(c: Context): Promise<Record<string, unknown>> {
  try {
    const body = await c.req.json();
    return typeof body === 'object' && body !== null
      ? (body as Record<string, unknown>)
      : {};
  } catch {
    return {};
  }
}

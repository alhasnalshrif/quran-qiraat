import type { Database } from '../db/client.js';
import { hashSessionToken, newCsrfToken, newSessionToken, sessionLifetimeMs } from './auth.js';

export type Role = 'owner' | 'editor';

export interface SessionUser {
  id: string;
  email: string;
  role: Role;
}

export interface ActiveSession {
  token: string;
  csrfToken: string;
  user: SessionUser;
  expiresAt: Date;
}

/**
 * Database-backed sessions (02 §3, §5). Only a hash of the token is stored;
 * the raw token lives in the httpOnly cookie.
 */
export class SessionStore {
  constructor(private readonly sql: Database) {}

  /** Creates a session and returns the raw token with its CSRF token. */
  async create(
    user: SessionUser,
    options: { ipHash?: string | undefined; now?: Date } = {},
  ): Promise<ActiveSession> {
    const now = options.now ?? new Date();
    const token = newSessionToken();
    const csrfToken = newCsrfToken();
    const expiresAt = new Date(now.getTime() + sessionLifetimeMs);

    await this.sql`
      insert into admin_sessions (id, user_id, expires_at, created_ip_hash, csrf_token)
      values (${hashSessionToken(token)}, ${user.id}, ${expiresAt.toISOString()}::timestamptz, ${
        options.ipHash ?? null
      }, ${csrfToken})
    `;

    return { token, csrfToken, user, expiresAt };
  }

  /** Looks up a live session by its raw cookie token. */
  async find(token: string, now: Date = new Date()): Promise<ActiveSession | null> {
    const rows = await this.sql<
      {
        csrf_token: string;
        expires_at: Date;
        id: string;
        email: string;
        role: Role;
      }[]
    >`
      select s.csrf_token, s.expires_at, u.id, u.email, u.role
      from admin_sessions s
      join admin_users u on u.id = s.user_id
      where s.id = ${hashSessionToken(token)}
        and s.expires_at > ${now.toISOString()}::timestamptz
        and u.disabled = false
      limit 1
    `;

    const row = rows[0];
    if (!row) return null;
    return {
      token,
      csrfToken: row.csrf_token,
      user: { id: row.id, email: row.email, role: row.role },
      expiresAt: row.expires_at,
    };
  }

  /** Removes one session (logout). */
  async destroy(token: string): Promise<void> {
    await this.sql`delete from admin_sessions where id = ${hashSessionToken(token)}`;
  }

  /** Removes expired sessions; called opportunistically on login. */
  async pruneExpired(now: Date = new Date()): Promise<void> {
    await this.sql`delete from admin_sessions where expires_at <= ${now.toISOString()}::timestamptz`;
  }

  /**
   * The session IP hash is kept for rate-limit forensics only and is cleared
   * after 7 days (02 §4), well before the session itself would expire.
   */
  async pruneIpHashes(now: Date = new Date()): Promise<void> {
    const cutoff = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000);
    await this.sql`
      update admin_sessions set created_ip_hash = null
      where created_ip_hash is not null and created_at <= ${cutoff.toISOString()}::timestamptz
    `;
  }
}

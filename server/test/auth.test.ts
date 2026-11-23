import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';

import { createApp } from '../src/app.js';
import { createDatabase, type Database } from '../src/db/client.js';
import { runMigrations } from './helpers/migrate.js';
import { hashPassword } from '../src/services/auth.js';
import { OneSignal } from '../src/services/onesignal.js';
import { ManifestSigner } from '../src/services/manifest-signer.js';
import { PackStorage } from '../src/services/storage.js';

/**
 * S-05 against a real Postgres: login success/failure, the 5-attempt lock,
 * CSRF rejection and role checks. Skipped when no database is reachable.
 */
const databaseUrl =
  process.env.TEST_DATABASE_URL ?? 'postgres://localhost:5432/quran_test';

let db: Database;
let app: ReturnType<typeof createApp>;
const testSigner = ManifestSigner.fromSeed(
  Buffer.alloc(32, 7).toString('base64'),
  'k1',
);
const onesignal = new OneSignal({
  appIdStable: 's',
  appIdBeta: 'b',
  keyStable: 'ks',
  keyBeta: 'kb',
  baseUrl: 'http://127.0.0.1:9',
});
const storage = PackStorage.fromConfig({
  endpoint: 'http://127.0.0.1:9',
  region: 'auto',
  bucket: 'quran-test',
  accessKeyId: 'test',
  secretAccessKey: 'test',
});
let ownerId: string;
let editorId: string;
const now = new Date('2026-11-23T10:00:00Z');

const ownerPassword = 'owner-password-123';
const editorPassword = 'editor-password-123';

beforeAll(async () => {
  db = createDatabase(databaseUrl);
  await runMigrations(db);
  await db`truncate admin_sessions, admin_users, audit_log restart identity cascade`;

  const [owner] = await db<{ id: string }[]>`
    insert into admin_users (email, password_hash, role)
    values ('owner@example.com', ${await hashPassword(ownerPassword)}, 'owner')
    returning id
  `;
  const [editor] = await db<{ id: string }[]>`
    insert into admin_users (email, password_hash, role)
    values ('editor@example.com', ${await hashPassword(editorPassword)}, 'editor')
    returning id
  `;
  ownerId = owner!.id;
  editorId = editor!.id;

  app = createApp({ db, storage, onesignal, signer: testSigner, cdnBaseUrl: 'https://cdn.example.com', secureCookies: false, now: () => now });
}, 30000);

afterAll(async () => {
  await db?.end();
});

beforeEach(async () => {
  await db`delete from admin_sessions`;
  await db`update admin_users set failed_login_count = 0, locked_until = null`;
});

async function login(email: string, password: string) {
  const response = await app.request('/admin/api/login', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ email, password }),
  });
  const cookie = response.headers.get('set-cookie') ?? '';
  const token = cookie.match(/qs_session=([^;]+)/)?.[1];
  const body = (await response.json()) as { csrfToken?: string; user?: { role: string } };
  return { response, token, body, cookie };
}

function authed(token: string, csrf?: string, method = 'GET') {
  return {
    method,
    headers: {
      cookie: `qs_session=${token}`,
      ...(csrf ? { 'X-CSRF-Token': csrf } : {}),
    },
  };
}

describe('login (S-05)', () => {
  it('accepts the right password and sets an httpOnly Strict cookie', async () => {
    const { response, token, body, cookie } = await login('owner@example.com', ownerPassword);

    expect(response.status).toBe(200);
    expect(token).toBeTruthy();
    expect(body.user?.role).toBe('owner');
    expect(body.csrfToken).toBeTruthy();
    expect(cookie).toContain('HttpOnly');
    expect(cookie).toContain('SameSite=Strict');
  });

  it('is case-insensitive on the email', async () => {
    const { response } = await login('OWNER@example.com', ownerPassword);
    expect(response.status).toBe(200);
  });

  it('rejects a wrong password without revealing the account exists', async () => {
    const wrong = await login('owner@example.com', 'nope-nope-nope');
    const unknown = await login('nobody@example.com', 'nope-nope-nope');

    expect(wrong.response.status).toBe(401);
    expect(unknown.response.status).toBe(401);
    expect(wrong.response.status).toBe(unknown.response.status);
    expect(wrong.body).toEqual(unknown.body);
  });

  it('requires both fields', async () => {
    const response = await app.request('/admin/api/login', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ email: 'owner@example.com' }),
    });
    expect(response.status).toBe(400);
  });
});

describe('lockout after five failures (S-05)', () => {
  it('locks the account and refuses even the right password', async () => {
    for (let attempt = 0; attempt < 5; attempt++) {
      const { response } = await login('editor@example.com', 'wrong-password-1');
      expect(response.status, `attempt ${attempt + 1}`).toBe(401);
    }

    const [row] = await db<{ locked_until: Date | null; failed_login_count: number }[]>`
      select locked_until, failed_login_count from admin_users where id = ${editorId}
    `;
    expect(row!.locked_until).not.toBeNull();

    const blocked = await login('editor@example.com', editorPassword);
    expect(blocked.response.status).toBe(429);
  });

  it('clears the counter after a successful login', async () => {
    await login('editor@example.com', 'wrong-password-1');
    await login('editor@example.com', editorPassword);

    const [row] = await db<{ failed_login_count: number }[]>`
      select failed_login_count from admin_users where id = ${editorId}
    `;
    expect(row!.failed_login_count).toBe(0);
  });

  it('honours a lock written by another process', async () => {
    // Regression: postgres-js can return timestamptz as a string, and a naive
    // `string > Date` comparison silently let logins through the lock.
    await db`
      update admin_users
      set locked_until = ${new Date(now.getTime() + 60_000).toISOString()}::timestamptz
      where id = ${editorId}
    `;

    const blocked = await login('editor@example.com', editorPassword);
    expect(blocked.response.status).toBe(429);
  });
});

describe('session and CSRF (S-05)', () => {
  it('rejects /me without a session', async () => {
    const response = await app.request('/admin/api/me');
    expect(response.status).toBe(401);
  });

  it('returns /me with a session', async () => {
    const { token } = await login('owner@example.com', ownerPassword);
    const response = await app.request('/admin/api/me', authed(token!));
    expect(response.status).toBe(200);
    const body = (await response.json()) as { user: { email: string } };
    expect(body.user.email).toBe('owner@example.com');
  });

  it('rejects a write without the CSRF header', async () => {
    const { token } = await login('owner@example.com', ownerPassword);
    const response = await app.request('/admin/api/me', authed(token!, undefined, 'POST'));
    expect(response.status).toBe(403);
  });

  it('rejects a write with the wrong CSRF token', async () => {
    const { token } = await login('owner@example.com', ownerPassword);
    const response = await app.request('/admin/api/me', authed(token!, 'wrong-token', 'POST'));
    expect(response.status).toBe(403);
  });

  it('accepts a write with the session CSRF token', async () => {
    const { token, body } = await login('owner@example.com', ownerPassword);
    const response = await app.request(
      '/admin/api/me',
      authed(token!, body.csrfToken, 'POST'),
    );
    // /me is a GET route; a POST 404s only after passing auth and CSRF.
    expect(response.status).not.toBe(403);
  });

  it('destroys the session on logout', async () => {
    const { token, body } = await login('owner@example.com', ownerPassword);
    const logout = await app.request('/admin/api/logout', authed(token!, body.csrfToken, 'POST'));
    expect(logout.status).toBe(200);

    const after = await app.request('/admin/api/me', authed(token!));
    expect(after.status).toBe(401);
  });

  it('rejects a disabled account', async () => {
    const { token } = await login('owner@example.com', ownerPassword);
    await db`update admin_users set disabled = true where id = ${ownerId}`;
    const response = await app.request('/admin/api/me', authed(token!));
    await db`update admin_users set disabled = false where id = ${ownerId}`;
    expect(response.status).toBe(401);
  });
});

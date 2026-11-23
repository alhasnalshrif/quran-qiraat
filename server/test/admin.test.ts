import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';

import { createApp } from '../src/app.js';
import { createDatabase, type Database } from '../src/db/client.js';
import { hashPassword } from '../src/services/auth.js';
import { OneSignal } from '../src/services/onesignal.js';
import { ManifestSigner } from '../src/services/manifest-signer.js';
import { PackStorage } from '../src/services/storage.js';
import { buildFilters } from '../src/services/onesignal.js';
import { runMigrations } from './helpers/migrate.js';

/**
 * S-09: platforms, config, announcements, users and audit, each with its
 * permissions, plus the OneSignal filter builder (no network here).
 */
const databaseUrl =
  process.env.TEST_DATABASE_URL ?? 'postgres://localhost:5432/quran_test';

let db: Database;
let app: ReturnType<typeof createApp>;
let ownerToken: string;
let editorToken: string;
let ownerCsrf: string;
let editorCsrf: string;
let ownerId: string;

const ownerPassword = 'owner-password-123';
const editorPassword = 'editor-password-123';

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
  accessKeyId: 't',
  secretAccessKey: 't',
});

beforeAll(async () => {
  db = createDatabase(databaseUrl);
  await runMigrations(db);
  await db`truncate admin_sessions, admin_users, audit_log, remote_config,
                   announcements, app_platforms, notifications restart identity cascade`;

  const [owner] = await db<{ id: string }[]>`
    insert into admin_users (email, password_hash, role)
    values ('s9-owner@example.com', ${await hashPassword(ownerPassword)}, 'owner')
    returning id
  `;
  ownerId = owner!.id;
  await db`
    insert into admin_users (email, password_hash, role)
    values ('s9-editor@example.com', ${await hashPassword(editorPassword)}, 'editor')
  `;

  app = createApp({ db, storage, onesignal, signer: testSigner, cdnBaseUrl: 'https://cdn.example.com', secureCookies: false });

  const ownerLogin = await login('s9-owner@example.com', ownerPassword);
  ownerToken = ownerLogin.token;
  ownerCsrf = ownerLogin.csrf;
  const editorLogin = await login('s9-editor@example.com', editorPassword);
  editorToken = editorLogin.token;
  editorCsrf = editorLogin.csrf;
}, 30000);

afterAll(async () => {
  await db?.end();
});

beforeEach(async () => {
  await db`delete from remote_config`;
  await db`delete from announcements`;
  await db`delete from app_platforms`;
  await db`delete from notifications`;
  await db`delete from audit_log`;
});

async function login(email: string, password: string) {
  const response = await app.request('/admin/api/login', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ email, password }),
  });
  const cookie = response.headers.get('set-cookie') ?? '';
  const token = cookie.match(/qs_session=([^;]+)/)?.[1] ?? '';
  const body = (await response.json()) as { csrfToken: string };
  return { token, csrf: body.csrfToken };
}

function as(token: string, csrf: string, method = 'GET', payload?: unknown) {
  return {
    method,
    headers: {
      'content-type': 'application/json',
      cookie: `qs_session=${token}`,
      ...(csrf ? { 'X-CSRF-Token': csrf } : {}),
    },
    ...(payload === undefined ? {} : { body: JSON.stringify(payload) }),
  };
}

describe('platforms (S-09)', () => {
  it('lets an owner set builds and reads them back', async () => {
    const put = await app.request(
      '/admin/api/platforms/ios',
      as(ownerToken, ownerCsrf, 'PUT', {
        latestBuild: 9,
        minSupportedBuild: 5,
        storeUrl: 'https://apps.apple.com/app/id1',
        messageAr: 'حدّث التطبيق',
      }),
    );
    expect(put.status).toBe(200);

    const get = await app.request('/admin/api/platforms/ios', as(ownerToken, ownerCsrf));
    const body = (await get.json()) as { platform: { latestBuild: number } };
    expect(body.platform.latestBuild).toBe(9);
  });

  it('rejects latest below minimum', async () => {
    const put = await app.request(
      '/admin/api/platforms/ios',
      as(ownerToken, ownerCsrf, 'PUT', { latestBuild: 4, minSupportedBuild: 9 }),
    );
    expect(put.status).toBe(400);
  });

  it('rejects an unknown platform', async () => {
    const get = await app.request('/admin/api/platforms/windows', as(ownerToken, ownerCsrf));
    expect(get.status).toBe(400);
  });

  it('does not let an editor write platforms', async () => {
    const put = await app.request(
      '/admin/api/platforms/ios',
      as(editorToken, editorCsrf, 'PUT', { latestBuild: 9, minSupportedBuild: 5 }),
    );
    expect(put.status).toBe(403);
  });
});

describe('remote config (S-09)', () => {
  it('accepts an approved key with a matching value', async () => {
    const post = await app.request(
      '/admin/api/config',
      as(ownerToken, ownerCsrf, 'POST', {
        key: 'updates.checkIntervalHours',
        channel: 'stable',
        value: 12,
      }),
    );
    expect(post.status).toBe(201);
  });

  it('rejects an unapproved key', async () => {
    const post = await app.request(
      '/admin/api/config',
      as(ownerToken, ownerCsrf, 'POST', {
        key: 'features.telemetry',
        channel: 'stable',
        value: true,
      }),
    );
    expect(post.status).toBe(400);
    const body = (await post.json()) as { error: { message: string } };
    expect(body.error.message).toContain('01 §4');
  });

  it('rejects a value that does not match the key type', async () => {
    const post = await app.request(
      '/admin/api/config',
      as(ownerToken, ownerCsrf, 'POST', {
        key: 'features.audio',
        channel: 'stable',
        value: 'yes',
      }),
    );
    expect(post.status).toBe(400);
  });

  it('rejects an out-of-range interval', async () => {
    const post = await app.request(
      '/admin/api/config',
      as(ownerToken, ownerCsrf, 'POST', {
        key: 'updates.checkIntervalHours',
        channel: 'stable',
        value: 500,
      }),
    );
    expect(post.status).toBe(400);
  });

  it('refuses a duplicate scope instead of silently ignoring it', async () => {
    const payload = {
      key: 'updates.checkIntervalHours',
      channel: 'stable',
      value: 12,
    };
    const first = await app.request('/admin/api/config', as(ownerToken, ownerCsrf, 'POST', payload));
    expect(first.status).toBe(201);

    const second = await app.request('/admin/api/config', as(ownerToken, ownerCsrf, 'POST', payload));
    expect(second.status).toBe(409);
  });

  it('lets only an owner read the config', async () => {
    const asEditor = await app.request('/admin/api/config', as(editorToken, editorCsrf));
    expect(asEditor.status).toBe(403);
    const asOwner = await app.request('/admin/api/config', as(ownerToken, ownerCsrf));
    expect(asOwner.status).toBe(200);
  });
});

describe('announcements (S-09)', () => {
  const announcement = {
    id: 'a-1',
    titleAr: 'إعلان',
    bodyAr: 'نص',
    channel: 'stable',
    startsAt: '2026-11-23T00:00:00Z',
    endsAt: '2026-12-01T00:00:00Z',
  };

  it('lets an editor create and list one', async () => {
    const post = await app.request(
      '/admin/api/announcements',
      as(editorToken, editorCsrf, 'POST', announcement),
    );
    expect(post.status, await post.clone().text()).toBe(201);

    const list = await app.request('/admin/api/announcements', as(editorToken, editorCsrf));
    const body = (await list.json()) as { announcements: { id: string }[] };
    expect(body.announcements).toHaveLength(1);
  });

  it('rejects an end before the start', async () => {
    const post = await app.request(
      '/admin/api/announcements',
      as(editorToken, editorCsrf, 'POST', {
        ...announcement,
        startsAt: '2026-12-02T00:00:00Z',
      }),
    );
    expect(post.status).toBe(400);
  });

  it('publishes and deletes', async () => {
    await app.request('/admin/api/announcements', as(editorToken, editorCsrf, 'POST', announcement));
    const put = await app.request(
      '/admin/api/announcements/a-1',
      as(editorToken, editorCsrf, 'PUT', { published: true }),
    );
    expect(put.status).toBe(200);

    const del = await app.request('/admin/api/announcements/a-1', as(editorToken, editorCsrf, 'DELETE'));
    expect(del.status).toBe(200);
  });
});

describe('users (S-09)', () => {
  it('lets only an owner list users', async () => {
    const asEditor = await app.request('/admin/api/users', as(editorToken, editorCsrf));
    expect(asEditor.status).toBe(403);
    const asOwner = await app.request('/admin/api/users', as(ownerToken, ownerCsrf));
    expect(asOwner.status).toBe(200);
  });

  it('disables an account and refuses to let an owner disable themselves', async () => {
    const self = await app.request(
      `/admin/api/users/${ownerId}`,
      as(ownerToken, ownerCsrf, 'PUT', { disabled: true }),
    );
    expect(self.status).toBe(400);

    const [editor] = await db<{ id: string }[]>`
      select id from admin_users where email = 's9-editor@example.com'
    `;
    const disable = await app.request(
      `/admin/api/users/${editor!.id}`,
      as(ownerToken, ownerCsrf, 'PUT', { disabled: true }),
    );
    expect(disable.status).toBe(200);

    await db`update admin_users set disabled = false where id = ${editor!.id}`;
  });
});

describe('audit log (S-09)', () => {
  it('records writes and paginates', async () => {
    await app.request(
      '/admin/api/announcements',
      as(editorToken, editorCsrf, 'POST', {
        id: 'a-2',
        titleAr: 'x',
        bodyAr: 'y',
        channel: 'beta',
        startsAt: '2026-11-23T00:00:00Z',
        endsAt: '2026-12-01T00:00:00Z',
      }),
    );

    const response = await app.request('/admin/api/audit?limit=10&offset=0', as(ownerToken, ownerCsrf));
    expect(response.status).toBe(200);
    const body = (await response.json()) as {
      entries: { action: string }[];
      total: number;
      limit: number;
    };
    expect(body.total).toBeGreaterThan(0);
    expect(body.entries.some((entry) => entry.action === 'announcement.create')).toBe(true);
    expect(body.limit).toBe(10);
  });

  it('lets only an owner read it', async () => {
    const asEditor = await app.request('/admin/api/audit', as(editorToken, editorCsrf));
    expect(asEditor.status).toBe(403);
  });
});

describe('OneSignal filters (S-09)', () => {
  it('builds channel, platform and build filters from our fields', () => {
    const filters = buildFilters({
      channel: 'beta',
      platforms: ['ios', 'android'],
      minBuild: 5,
      maxBuild: 9,
    }) as Record<string, unknown>[];

    expect(filters[0]).toEqual({ field: 'tag', key: 'channel', relation: '=', value: 'beta' });
    expect(filters).toContainEqual({
      field: 'tag',
      key: 'build',
      relation: '>=',
      value: '5',
    });
    expect(filters).toContainEqual({
      field: 'tag',
      key: 'build',
      relation: '<=',
      value: '9',
    });
    expect(filters.some((filter) => filter['operator'] === 'OR')).toBe(true);
  });

  it('never emits a tag outside channel, platform and build', () => {
    const filters = buildFilters({
      channel: 'stable',
      platforms: ['ios'],
      minBuild: null,
      maxBuild: null,
    }) as Record<string, unknown>[];
    const keys = filters.map((filter) => filter['key']).filter(Boolean);
    expect(new Set(keys)).toEqual(new Set(['channel', 'platform']));
  });
});

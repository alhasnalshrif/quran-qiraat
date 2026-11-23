import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';

import { createApp } from '../src/app.js';
import { createDatabase, type Database } from '../src/db/client.js';
import { hashPassword } from '../src/services/auth.js';
import { PackStorage, sha256Hex } from '../src/services/storage.js';
import { startFakeS3, type FakeS3 } from './helpers/fake-s3.js';
import { runMigrations } from './helpers/migrate.js';

/**
 * S-07 end to end against real Postgres and a real S3-shaped server:
 * draft → validated → beta → stable, plus a sha256 mismatch blocking
 * validation and the owner-only rules.
 */
const databaseUrl =
  process.env.TEST_DATABASE_URL ?? 'postgres://localhost:5432/quran_test';

let db: Database;
let s3: FakeS3;
let app: ReturnType<typeof createApp>;
let ownerToken: string;
let editorToken: string;
let ownerCsrf: string;
let editorCsrf: string;

const ownerPassword = 'owner-password-123';
const editorPassword = 'editor-password-123';

/** A minimal, valid editions-manifest@1 document. */
const validManifest = JSON.stringify({
  schema_version: '1.0.0',
  editions: [
    { id: 'hafs_kfgqpc', reading: 'hafs', name_ar: 'حفص', total_ayahs: 6236 },
  ],
});

beforeAll(async () => {
  db = createDatabase(databaseUrl);
  s3 = await startFakeS3();
  await runMigrations(db);
  await db`truncate channel_releases, pack_files, pack_versions, packs, admin_sessions, admin_users, audit_log restart identity cascade`;

  await db`
    insert into admin_users (email, password_hash, role) values
      ('pack-owner@example.com', ${await hashPassword(ownerPassword)}, 'owner'),
      ('pack-editor@example.com', ${await hashPassword(editorPassword)}, 'editor')
  `;

  app = createApp({
    db,
    storage: PackStorage.fromConfig({
      endpoint: s3.endpoint,
      region: 'auto',
      bucket: s3.bucket,
      accessKeyId: 'test-key',
      secretAccessKey: 'test-secret',
    }),
    secureCookies: false,
  });

  const owner = await login('pack-owner@example.com', ownerPassword);
  ownerToken = owner.token;
  ownerCsrf = owner.csrf;
  const editor = await login('pack-editor@example.com', editorPassword);
  editorToken = editor.token;
  editorCsrf = editor.csrf;
}, 30000);

afterAll(async () => {
  await s3?.close();
  await db?.end();
});

beforeEach(async () => {
  await db`delete from channel_releases`;
  await db`delete from pack_files`;
  await db`delete from pack_versions`;
  await db`delete from packs`;
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

function as(token: string, csrf: string, method = 'GET') {
  return {
    method,
    headers: {
      'content-type': 'application/json',
      cookie: `qs_session=${token}`,
      ...(csrf ? { 'X-CSRF-Token': csrf } : {}),
    },
  };
}

/** Creates the pack, a draft version and uploads one file; returns its id. */
async function createDraft(
  options: {
    body?: string;
    declaredSha?: string;
    format?: string;
    token?: string;
    csrf?: string;
  } = {},
) {
  const token = options.token ?? ownerToken;
  const csrf = options.csrf ?? ownerCsrf;
  const body = options.body ?? validManifest;
  const bytes = new TextEncoder().encode(body);

  const pack = await app.request(
    '/admin/api/packs',
    { ...as(token, csrf, 'POST'), body: JSON.stringify({ packId: 'editions-manifest', titleAr: 'بيان الطبعات', formatFamily: 'editions-manifest' }) },
  );
  if (pack.status !== 201) throw new Error(`pack create failed: ${pack.status} ${await pack.text()}`);

  const created = await app.request(
    '/admin/api/packs/editions-manifest/versions',
    {
      ...as(token, csrf, 'POST'),
      body: JSON.stringify({ format: options.format ?? 'editions-manifest@1', sourceName: 'test', sourceRevision: 'abc' }),
    },
  );
  const version = (await created.json()) as { id: string; version: number };

  const upload = await app.request(
    `/admin/api/pack-versions/${version.id}/files`,
    {
      ...as(token, csrf, 'POST'),
      body: JSON.stringify({
        files: [
          {
            path: 'editions_manifest.json',
            sha256: options.declaredSha ?? sha256Hex(bytes),
            size: bytes.byteLength,
          },
        ],
      }),
    },
  );
  const { uploads } = (await upload.json()) as { uploads: { url: string }[] };

  // Put the real bytes at the presigned URL, exactly as the browser would.
  const put = await fetch(uploads[0]!.url, { method: 'PUT', body: bytes });
  if (!put.ok) throw new Error(`upload failed: ${put.status}`);

  return version;
}

describe('pack version lifecycle (S-07)', () => {
  it('walks draft → validated → beta → stable', async () => {
    const version = await createDraft();

    const validated = await app.request(
      `/admin/api/pack-versions/${version.id}/validate`,
      as(editorToken, editorCsrf, 'POST'),
    );
    const validatedBody = (await validated.json()) as { status: string };
    expect(validated.status, JSON.stringify(validatedBody)).toBe(200);
    expect(validatedBody.status).toBe('validated');

    const beta = await app.request(
      `/admin/api/pack-versions/${version.id}/release`,
      { ...as(editorToken, editorCsrf, 'POST'), body: JSON.stringify({ channel: 'beta' }) },
    );
    expect(beta.status, JSON.stringify(await beta.json())).toBe(200);

    const stable = await app.request(
      `/admin/api/pack-versions/${version.id}/release`,
      { ...as(ownerToken, ownerCsrf, 'POST'), body: JSON.stringify({ channel: 'stable' }) },
    );
    expect(stable.status, JSON.stringify(await stable.json())).toBe(200);

    const list = await app.request('/admin/api/packs', as(ownerToken, ownerCsrf));
    const body = (await list.json()) as {
      packs: { packId: string; channels: Record<string, number> }[];
    };
    expect(body.packs[0]!.channels.beta).toBe(1);
    expect(body.packs[0]!.channels.stable).toBe(1);

    const audit = await db<{ action: string }[]>`select action from audit_log order by at`;
    const actions = audit.map((row) => row.action);
    expect(actions).toContain('pack_version.validate');
    expect(actions).toContain('pack_version.publish');
  });

  it('blocks validation when the uploaded sha256 does not match', async () => {
    const version = await createDraft({ declaredSha: 'a'.repeat(64) });

    const validated = await app.request(
      `/admin/api/pack-versions/${version.id}/validate`,
      as(editorToken, editorCsrf, 'POST'),
    );
    expect(validated.status).toBe(422);
    expect(((await validated.json()) as { error: { message: string } }).error.message).toContain(
      'sha256 mismatch',
    );
  });

  it('blocks validation when the format validator rejects the document', async () => {
    const version = await createDraft({
      body: JSON.stringify({ schema_version: '9.9.9', editions: [] }),
    });

    const validated = await app.request(
      `/admin/api/pack-versions/${version.id}/validate`,
      as(editorToken, editorCsrf, 'POST'),
    );
    expect(validated.status).toBe(422);
    expect(((await validated.json()) as { error: { message: string } }).error.message).toContain(
      'Validator rejected',
    );
  });

  it('blocks validation when the file was never uploaded', async () => {
    const version = await createDraft();
    await s3.objects.clear();

    const validated = await app.request(
      `/admin/api/pack-versions/${version.id}/validate`,
      as(editorToken, editorCsrf, 'POST'),
    );
    expect(validated.status).toBe(422);
    expect(((await validated.json()) as { error: { message: string } }).error.message).toContain(
      'Missing upload',
    );
  });

  it('refuses to release an unvalidated version', async () => {
    const version = await createDraft();
    const response = await app.request(
      `/admin/api/pack-versions/${version.id}/release`,
      { ...as(ownerToken, ownerCsrf, 'POST'), body: JSON.stringify({ channel: 'beta' }) },
    );
    expect(response.status).toBe(409);
  });
});

describe('permissions (S-07)', () => {
  it('does not let an editor release to stable', async () => {
    const version = await createDraft();
    await app.request(`/admin/api/pack-versions/${version.id}/validate`, as(editorToken, editorCsrf, 'POST'));

    const response = await app.request(
      `/admin/api/pack-versions/${version.id}/release`,
      { ...as(editorToken, editorCsrf, 'POST'), body: JSON.stringify({ channel: 'stable' }) },
    );
    expect(response.status).toBe(403);
  });

  it('lets an editor release to beta', async () => {
    const version = await createDraft();
    await app.request(`/admin/api/pack-versions/${version.id}/validate`, as(editorToken, editorCsrf, 'POST'));

    const response = await app.request(
      `/admin/api/pack-versions/${version.id}/release`,
      { ...as(editorToken, editorCsrf, 'POST'), body: JSON.stringify({ channel: 'beta' }) },
    );
    expect(response.status).toBe(200);
  });

  it('only lets an owner create a pack', async () => {
    const response = await app.request(
      '/admin/api/packs',
      {
        ...as(editorToken, editorCsrf, 'POST'),
        body: JSON.stringify({ packId: 'hafs-text', titleAr: 'نص حفص', formatFamily: 'kfgqpc-ayahs' }),
      },
    );
    expect(response.status).toBe(403);
  });

  it('rejects a packId outside the protocol list', async () => {
    const response = await app.request(
      '/admin/api/packs',
      {
        ...as(ownerToken, ownerCsrf, 'POST'),
        body: JSON.stringify({ packId: 'not-a-pack', titleAr: 'x', formatFamily: 'y' }),
      },
    );
    expect(response.status).toBe(400);
  });

  it('only lets an owner revoke', async () => {
    const version = await createDraft();
    await app.request(`/admin/api/pack-versions/${version.id}/validate`, as(editorToken, editorCsrf, 'POST'));

    const asEditor = await app.request(
      `/admin/api/pack-versions/${version.id}/revoke`,
      as(editorToken, editorCsrf, 'POST'),
    );
    expect(asEditor.status).toBe(403);

    const asOwner = await app.request(
      `/admin/api/pack-versions/${version.id}/revoke`,
      as(ownerToken, ownerCsrf, 'POST'),
    );
    expect(asOwner.status).toBe(200);
  });

  it('removes a revoked version from every channel', async () => {
    const version = await createDraft();
    await app.request(`/admin/api/pack-versions/${version.id}/validate`, as(ownerToken, ownerCsrf, 'POST'));
    await app.request(
      `/admin/api/pack-versions/${version.id}/release`,
      { ...as(ownerToken, ownerCsrf, 'POST'), body: JSON.stringify({ channel: 'beta' }) },
    );

    await app.request(`/admin/api/pack-versions/${version.id}/revoke`, as(ownerToken, ownerCsrf, 'POST'));

    const list = await app.request('/admin/api/packs', as(ownerToken, ownerCsrf));
    const body = (await list.json()) as { packs: { channels: Record<string, number> }[] };
    expect(body.packs[0]!.channels).toEqual({});
  });

  it('rejects an unsafe file path', async () => {
    const version = await createDraft();
    const response = await app.request(
      `/admin/api/pack-versions/${version.id}/files`,
      {
        ...as(ownerToken, ownerCsrf, 'POST'),
        body: JSON.stringify({
          files: [{ path: '../escape.json', sha256: 'a'.repeat(64), size: 1 }],
        }),
      },
    );
    expect(response.status).toBe(400);
  });

  it('requires CSRF on pack writes', async () => {
    const response = await app.request(
      '/admin/api/packs',
      {
        ...as(ownerToken, '', 'POST'),
        body: JSON.stringify({ packId: 'hafs-text', titleAr: 'x', formatFamily: 'y' }),
      },
    );
    expect(response.status).toBe(403);
  });

  it('numbers versions upward and never reuses one', async () => {
    const first = await createDraft();
    await app.request(`/admin/api/pack-versions/${first.id}/validate`, as(ownerToken, ownerCsrf, 'POST'));
    await app.request(`/admin/api/pack-versions/${first.id}/revoke`, as(ownerToken, ownerCsrf, 'POST'));

    const second = await app.request(
      '/admin/api/packs/editions-manifest/versions',
      { ...as(ownerToken, ownerCsrf, 'POST'), body: JSON.stringify({ format: 'editions-manifest@1' }) },
    );
    const body = (await second.json()) as { version: number };
    expect(body.version).toBe(2);
  });
});

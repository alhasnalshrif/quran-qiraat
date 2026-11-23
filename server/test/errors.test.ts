import { afterAll, beforeAll, describe, expect, it } from 'vitest';

import { createApp } from '../src/app.js';
import { createDatabase, type Database } from '../src/db/client.js';
import { ManifestSigner } from '../src/services/manifest-signer.js';
import { OneSignal } from '../src/services/onesignal.js';
import { PackStorage } from '../src/services/storage.js';
import { runMigrations } from './helpers/migrate.js';

/** 01 §2.3: every error is { error: { code, message } }, never HTML. */
const databaseUrl =
  process.env.TEST_DATABASE_URL ?? 'postgres://localhost:5432/quran_test';

let db: Database;
const signer = ManifestSigner.fromSeed(Buffer.alloc(32, 2).toString('base64'), 'k1');
const onesignal = new OneSignal({
  appIdStable: 's', appIdBeta: 'b', keyStable: 'k', keyBeta: 'k',
  baseUrl: 'http://127.0.0.1:9',
});
const storage = PackStorage.fromConfig({
  endpoint: 'http://127.0.0.1:9', region: 'auto', bucket: 'b',
  accessKeyId: 'k', secretAccessKey: 's',
});

function appWith(overrides: { db?: Database } = {}) {
  return createApp({
    db: overrides.db ?? db,
    storage,
    onesignal,
    signer,
    cdnBaseUrl: 'https://cdn.example.com',
    secureCookies: false,
  });
}

beforeAll(async () => {
  db = createDatabase(databaseUrl);
  await runMigrations(db);
}, 30000);

afterAll(async () => {
  await db?.end();
});

describe('error contract (01 §2.3)', () => {
  it('answers an unknown route with not_found JSON', async () => {
    const response = await appWith().request('/v1/nope');
    expect(response.status).toBe(404);
    expect(response.headers.get('content-type')).toContain('application/json');
    const body = (await response.json()) as { error: { code: string } };
    expect(body.error.code).toBe('not_found');
  });

  it('answers a failing handler with internal JSON, not an HTML page', async () => {
    // A database stub that throws drives a real 500 through the app.
    const broken = Object.assign(
      async () => {
        throw new Error('database exploded with secrets');
      },
      { end: async () => {} },
    ) as unknown as Database;

    const response = await appWith({ db: broken }).request(
      '/v1/manifest?platform=ios&build=1&protocol=1',
    );

    expect(response.status).toBe(500);
    expect(response.headers.get('content-type')).toContain('application/json');
    const body = (await response.json()) as { error: { code: string; message: string } };
    expect(body.error.code).toBe('internal');
    // The internal message must not leak.
    expect(body.error.message).not.toContain('exploded');
    expect(body.error.message).not.toContain('secrets');
  });

  it('keeps /healthz honest when the database is down', async () => {
    const broken = Object.assign(
      async () => {
        throw new Error('down');
      },
      { end: async () => {} },
    ) as unknown as Database;

    const response = await appWith({ db: broken }).request('/healthz');
    expect(response.status).toBe(503);
    expect(await response.json()).toEqual({ ok: false });
  });
});

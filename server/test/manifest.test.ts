import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';

import { createApp } from '../src/app.js';
import { createDatabase, type Database } from '../src/db/client.js';
import { ManifestSigner, verifyEnvelope } from '../src/services/manifest-signer.js';
import { OneSignal } from '../src/services/onesignal.js';
import { PackStorage } from '../src/services/storage.js';
import { ManifestCache } from '../src/routes/public.js';
import { runMigrations } from './helpers/migrate.js';

/**
 * S-08: every rule of 01 §2.2 against a real database — build filtering,
 * channels, revoked, expiresAt, ETag/304, signing and the error cases.
 */
const databaseUrl =
  process.env.TEST_DATABASE_URL ?? 'postgres://localhost:5432/quran_test';

let db: Database;
let app: ReturnType<typeof createApp>;
let cache: ManifestCache;
const fixedNow = new Date('2026-11-23T10:00:00Z');
const signer = ManifestSigner.fromSeed(Buffer.alloc(32, 3).toString('base64'), 'k1');

const onesignal = new OneSignal({
  appIdStable: 's',
  appIdBeta: 'b',
  keyStable: 'k',
  keyBeta: 'k',
  baseUrl: 'http://127.0.0.1:9',
});
const storage = PackStorage.fromConfig({
  endpoint: 'http://127.0.0.1:9',
  region: 'auto',
  bucket: 'b',
  accessKeyId: 'k',
  secretAccessKey: 's',
});

async function decode(response: Response) {
  const envelope = (await response.json()) as {
    keyId: string;
    payload: string;
    signature: string;
  };
  const payload = JSON.parse(Buffer.from(envelope.payload, 'base64').toString('utf8'));
  return { envelope, payload };
}

/** Inserts a published pack version and an optional channel release. */
async function release(
  packId: string,
  version: number,
  options: {
    channel?: 'stable' | 'beta' | 'internal';
    status?: 'published' | 'revoked' | 'validated';
    minAppBuild?: number;
  } = {},
) {
  const channel = options.channel ?? 'stable';
  const status = options.status ?? 'published';
  const [row] = await db<{ id: string }[]>`
    insert into pack_versions (pack_id, version, format, min_app_build, status)
    values (${packId}, ${version}, 'editions-manifest@1', ${options.minAppBuild ?? 1}, ${status})
    returning id
  `;
  await db`
    insert into pack_files (pack_version_id, path, object_key, sha256, size)
    values (${row!.id}, 'editions_manifest.json',
            ${`packs/${packId}/${version}/editions_manifest.json`},
            ${'a'.repeat(64)}, 10)
  `;
  if (status === 'published') {
    await db`insert into channel_releases (channel, pack_version_id)
             values (${channel}, ${row!.id})`;
  }
  return row!.id;
}

beforeAll(async () => {
  db = createDatabase(databaseUrl);
  await runMigrations(db);
}, 30000);

afterAll(async () => {
  await db?.end();
});

beforeEach(async () => {
  await db`delete from channel_releases`;
  await db`delete from pack_files`;
  await db`delete from pack_versions`;
  await db`delete from packs`;
  await db`delete from app_platforms`;
  await db`delete from remote_config`;
  await db`delete from announcements`;

  await db`insert into packs (id, title_ar, format_family)
           values ('editions-manifest', 'بيان', 'editions-manifest')`;
  await db`insert into app_platforms (platform, latest_build, min_supported_build, store_url)
           values ('ios', 9, 5, 'https://apps.apple.com/app/id1')`;

  // A fresh cache per test: manifests are cached per platform/build/channel.
  cache = new ManifestCache();
  app = createApp({
    db,
    storage,
    onesignal,
    signer,
    cdnBaseUrl: 'https://cdn.example.com',
    manifestCache: cache,
    secureCookies: false,
    now: () => fixedNow,
  });
});

const manifest = (query: string) => app.request(`/v1/manifest?${query}`);

describe('request validation (S-08)', () => {
  it('requires platform, build and protocol 1', async () => {
    expect((await manifest('build=7&protocol=1')).status).toBe(400);
    expect((await manifest('platform=ios&protocol=1')).status).toBe(400);
    expect((await manifest('platform=ios&build=7')).status).toBe(400);
    expect((await manifest('platform=ios&build=7&protocol=2')).status).toBe(400);
  });

  it('names the protocol error code', async () => {
    const response = await manifest('platform=ios&build=7&protocol=2');
    const body = (await response.json()) as { error: { code: string } };
    expect(body.error.code).toBe('unsupported_protocol');
  });

  it('defaults the channel to stable', async () => {
    const response = await manifest('platform=ios&build=7&protocol=1');
    const { payload } = await decode(response);
    expect(payload.channel).toBe('stable');
  });
});

describe('signing and envelope (S-08)', () => {
  it('signs the payload so the public key verifies it', async () => {
    const response = await manifest('platform=ios&build=7&protocol=1');
    const body = (await response.json()) as {
      keyId: string;
      payload: string;
      signature: string;
    };

    expect(body.keyId).toBe('k1');
    expect(verifyEnvelope(body, signer.publicKeyBase64)).toBe(true);
  });

  it('fails verification when the payload is altered', async () => {
    const response = await manifest('platform=ios&build=7&protocol=1');
    const body = (await response.json()) as { payload: string; signature: string };
    const altered = Buffer.from(body.payload, 'base64')
      .toString('utf8')
      .replace('"protocol":1', '"protocol":1 ')
      .replace('"latestBuild":9', '"latestBuild":99');

    expect(
      verifyEnvelope(
        { payload: Buffer.from(altered).toString('base64'), signature: body.signature },
        signer.publicKeyBase64,
      ),
    ).toBe(false);
  });

  it('sets expiresAt at most 7 days ahead', async () => {
    const { payload } = await decode(await manifest('platform=ios&build=7&protocol=1'));
    const days =
      (new Date(payload.expiresAt).getTime() - new Date(payload.issuedAt).getTime()) /
      86_400_000;
    expect(days).toBeLessThanOrEqual(7);
    expect(days).toBeGreaterThan(0);
  });
});

describe('content rules (S-08)', () => {
  it('includes only the newest published version per pack', async () => {
    await release('editions-manifest', 1);
    await release('editions-manifest', 3);
    await release('editions-manifest', 2);

    const { payload } = await decode(await manifest('platform=ios&build=7&protocol=1'));
    expect(payload.packs).toHaveLength(1);
    expect(payload.packs[0].version).toBe(3);
  });

  it('filters by the app build (min_app_build)', async () => {
    await release('editions-manifest', 5, { minAppBuild: 10 });

    const older = await decode(await manifest('platform=ios&build=7&protocol=1'));
    expect(older.payload.packs).toHaveLength(0);

    const newer = await decode(await manifest('platform=ios&build=11&protocol=1'));
    expect(newer.payload.packs).toHaveLength(1);
  });

  it('keeps channels apart', async () => {
    await release('editions-manifest', 1, { channel: 'stable' });
    await release('editions-manifest', 2, { channel: 'beta' });

    const stable = await decode(await manifest('platform=ios&build=7&channel=stable&protocol=1'));
    expect(stable.payload.packs[0].version).toBe(1);

    const beta = await decode(await manifest('platform=ios&build=7&channel=beta&protocol=1'));
    expect(beta.payload.packs[0].version).toBe(2);
  });

  it('lists revoked versions regardless of channel', async () => {
    await release('editions-manifest', 1, { status: 'revoked' });

    const { payload } = await decode(await manifest('platform=ios&build=7&protocol=1'));
    expect(payload.revoked).toEqual([{ packId: 'editions-manifest', version: 1 }]);
    expect(payload.packs).toHaveLength(0);
  });

  it('serves the app policy and store link', async () => {
    const { payload } = await decode(await manifest('platform=ios&build=7&protocol=1'));
    expect(payload.app.latestBuild).toBe(9);
    expect(payload.app.minSupportedBuild).toBe(5);
    expect(payload.app.storeUrl).toContain('apps.apple.com');
  });

  it('includes live announcements and their Arabic text', async () => {
    await db`insert into announcements
             (id, title_ar, body_ar, channel, starts_at, ends_at, priority, published)
             values ('a1', 'إعلان', 'نص', 'stable'::channel,
                     ${'2026-11-01T00:00:00Z'}::timestamptz,
                     ${'2026-12-01T00:00:00Z'}::timestamptz,
                     'normal'::announcement_priority, true)`;
    // An expired one must not appear.
    await db`insert into announcements
             (id, title_ar, body_ar, channel, starts_at, ends_at, priority, published)
             values ('a2', 'قديم', 'نص', 'stable'::channel,
                     ${'2026-01-01T00:00:00Z'}::timestamptz,
                     ${'2026-02-01T00:00:00Z'}::timestamptz,
                     'normal'::announcement_priority, true)`;

    const { payload } = await decode(await manifest('platform=ios&build=7&protocol=1'));
    expect(payload.announcements).toHaveLength(1);
    expect(payload.announcements[0].title.ar).toBe('إعلان');
  });

  it('carries remote config for this channel and build', async () => {
    await db`insert into remote_config (key, channel, value)
             values ('updates.checkIntervalHours', 'stable'::channel, '{"v":12}'::jsonb)`;

    const { payload } = await decode(await manifest('platform=ios&build=7&protocol=1'));
    expect(payload.config['updates.checkIntervalHours']).toEqual({ v: 12 });
  });

  it('builds absolute CDN URLs for pack files', async () => {
    await release('editions-manifest', 2);
    const { payload } = await decode(await manifest('platform=ios&build=7&protocol=1'));
    expect(payload.packs[0].files[0].url).toBe(
      'https://cdn.example.com/packs/editions-manifest/2/editions_manifest.json',
    );
  });
});

describe('caching and ETag (S-08)', () => {
  it('returns an ETag and Cache-Control', async () => {
    const response = await manifest('platform=ios&build=7&protocol=1');
    expect(response.headers.get('etag')).toMatch(/^"[0-9a-f]{64}"$/);
    expect(response.headers.get('cache-control')).toContain('max-age=300');
  });

  it('answers 304 when If-None-Match matches', async () => {
    const first = await manifest('platform=ios&build=7&protocol=1');
    const etag = first.headers.get('etag')!;

    const second = await app.request('/v1/manifest?platform=ios&build=7&protocol=1', {
      headers: { 'if-none-match': etag },
    });
    expect(second.status).toBe(304);
    expect(await second.text()).toBe('');
  });

  it('serves a cached body without rebuilding', async () => {
    const first = await manifest('platform=ios&build=7&protocol=1');
    const second = await manifest('platform=ios&build=7&protocol=1');
    expect(first.headers.get('etag')).toBe(second.headers.get('etag'));
  });

  it('clears the cache on clear(), so a publish is visible immediately', async () => {
    await app.request('/v1/manifest?platform=ios&build=7&protocol=1');
    expect(cache.size).toBe(1);

    await release('editions-manifest', 4);
    cache.clear();
    expect(cache.size).toBe(0);

    const after = await app.request('/v1/manifest?platform=ios&build=7&protocol=1');
    const { payload } = await decode(after);
    expect(payload.packs[0].version).toBe(4);
  });
});

describe('pack fallback (S-08)', () => {
  it('redirects a direct pack file request to the CDN', async () => {
    const response = await app.request(
      '/v1/packs/editions-manifest/2/editions_manifest.json',
      { redirect: 'manual' },
    );
    expect(response.status).toBe(302);
    expect(response.headers.get('location')).toBe(
      'https://cdn.example.com/packs/editions-manifest/2/editions_manifest.json',
    );
  });
});

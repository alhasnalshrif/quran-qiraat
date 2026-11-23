import { afterAll, beforeAll, describe, expect, it } from 'vitest';

import { createApp } from '../src/app.js';
import { createDatabase, type Database } from '../src/db/client.js';
import { RateLimiter, clientKey } from '../src/middleware/rate-limit.js';
import { ManifestSigner } from '../src/services/manifest-signer.js';
import { OneSignal } from '../src/services/onesignal.js';
import { PackStorage } from '../src/services/storage.js';
import { runMigrations } from './helpers/migrate.js';

/**
 * 02 §4: /v1 is limited to 60 requests per minute per IP, keyed by a
 * daily-rotating hash, and answers 429 in the contract's error shape.
 */
const databaseUrl =
  process.env.TEST_DATABASE_URL ?? 'postgres://localhost:5432/quran_test';

let db: Database;
let app: ReturnType<typeof createApp>;
let limiter: RateLimiter;
const now = new Date('2026-11-23T10:00:00Z');

const signer = ManifestSigner.fromSeed(Buffer.alloc(32, 5).toString('base64'), 'k1');
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

const manifestPath = '/v1/manifest?platform=ios&build=1&protocol=1';

beforeAll(async () => {
  db = createDatabase(databaseUrl);
  await runMigrations(db);
}, 30000);

afterAll(async () => {
  await db?.end();
});

function freshApp(limit = 60): void {
  limiter = new RateLimiter(limit, 60_000, () => now.getTime());
  app = createApp({
    db,
    storage,
    onesignal,
    signer,
    cdnBaseUrl: 'https://cdn.example.com',
    secureCookies: false,
    now: () => now,
    rateLimiter: limiter,
  });
}

describe('rate limiting (02 §4)', () => {
  it('allows the first request and reports remaining capacity', () => {
    const local = new RateLimiter(3, 60_000, () => 0);
    expect(local.consume('ip')).toEqual({ allowed: true, remaining: 2, retryAfter: 0 });
    expect(local.consume('ip').remaining).toBe(1);
    expect(local.consume('ip').remaining).toBe(0);
  });

  it('blocks past the limit and says when to retry', () => {
    const clock = 0;
    const local = new RateLimiter(2, 30_000, () => clock);
    local.consume('ip');
    local.consume('ip');

    const blocked = local.consume('ip');
    expect(blocked.allowed).toBe(false);
    expect(blocked.retryAfter).toBe(30);
  });

  it('resets after the window', () => {
    let clock = 0;
    const local = new RateLimiter(1, 1_000, () => clock);
    expect(local.consume('ip').allowed).toBe(true);
    expect(local.consume('ip').allowed).toBe(false);

    clock = 1_001;
    expect(local.consume('ip').allowed).toBe(true);
  });

  it('counts each key independently', () => {
    const local = new RateLimiter(1, 60_000, () => 0);
    expect(local.consume('a').allowed).toBe(true);
    expect(local.consume('b').allowed).toBe(true);
    expect(local.consume('a').allowed).toBe(false);
  });

  it('drops expired buckets so the map cannot grow forever', () => {
    let clock = 0;
    const local = new RateLimiter(5, 1_000, () => clock);
    for (let i = 0; i < 50; i++) local.consume(`ip-${i}`);
    expect(local.size).toBe(50);

    clock = 2_000;
    local.consume('fresh');
    expect(local.size).toBe(1);
  });

  it('prefers the Cloudflare client header, which a client cannot forge', () => {
    const headers: Record<string, string> = {
      'cf-connecting-ip': '5.5.5.5',
      'x-forwarded-for': '1.2.3.4, 5.6.7.8',
      'x-real-ip': '9.9.9.9',
    };
    expect(clientKey({ header: (n) => headers[n] })).toBe('5.5.5.5');
  });

  it('falls back to x-real-ip, then the closest forwarded hop', () => {
    expect(clientKey({ header: (n) => (n === 'x-real-ip' ? '9.9.9.9' : undefined) })).toBe('9.9.9.9');
    // The right-most forwarded entry is our own proxy's, not the client's claim.
    expect(clientKey({ header: (n) => (n === 'x-forwarded-for' ? '1.2.3.4, 5.6.7.8' : undefined) })).toBe('5.6.7.8');
  });

  it('never keys on the client-supplied left-most forwarded entry', () => {
    // A forged, varying first entry must not create a fresh bucket each time.
    const rotated = new RateLimiter(1, 60_000, () => 0);
    for (let i = 0; i < 5; i++) {
      const key = clientKey({
        header: (n) =>
          n === 'x-forwarded-for' ? `10.0.0.${i}, 5.6.7.8` : undefined,
      });
      rotated.consume(key);
    }
    // All five map to the same key, so the limiter counted one bucket.
    expect(rotated.size).toBe(1);
  });

  it('returns a constant when no address header is present', () => {
    expect(clientKey({ header: () => undefined })).toBe('unknown');
  });
});

describe('the /v1 route enforces the limit', () => {
  it('answers 429 with the contract error code once exhausted', async () => {
    freshApp(2);

    expect((await app.request(manifestPath)).status).toBe(200);
    expect((await app.request(manifestPath)).status).toBe(200);

    const blocked = await app.request(manifestPath);
    expect(blocked.status).toBe(429);
    const body = (await blocked.json()) as { error: { code: string } };
    expect(body.error.code).toBe('rate_limited');
    expect(blocked.headers.get('retry-after')).toBeTruthy();
  });

  it('does not touch /healthz or the admin API', async () => {
    freshApp(1);
    await app.request(manifestPath);
    expect((await app.request(manifestPath)).status).toBe(429);

    // Admin routes live on a different mount and must stay reachable.
    const login = await app.request('/admin/api/login', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ email: 'nobody@example.com', password: 'x' }),
    });
    expect(login.status).not.toBe(429);
  });
});

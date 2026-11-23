import { describe, expect, it } from 'vitest';
import { mkdir, mkdtemp, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

import { createApp } from '../src/app.js';
import { ManifestSigner } from '../src/services/manifest-signer.js';
import { OneSignal } from '../src/services/onesignal.js';
import { PackStorage } from '../src/services/storage.js';

/**
 * The dashboard is served from ADMIN_DIST and a request must never read
 * outside it.
 *
 * Honest scope: Hono normalises the request path before the handler runs, so
 * the encoded-traversal cases below cannot actually reach a sibling directory
 * and this test passes with or without the prefix guard. The guard is still
 * correct to have — it protects against a future caller that passes a raw
 * path — but it is not proven exploitable over HTTP, and this test does not
 * claim otherwise.
 */
const signer = ManifestSigner.fromSeed(Buffer.alloc(32, 9).toString('base64'), 'k1');
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

// A tag function placeholder: /admin static serving never queries the database.
const fakeDb = Object.assign(
  async () => [],
  { end: async () => {} },
) as unknown as Parameters<typeof createApp>[0]['db'];

describe('dashboard static serving (S-10)', () => {
  it('refuses a sibling directory that shares the dist prefix', async () => {
    const root = await mkdtemp(join(tmpdir(), 'admin-static-'));
    const dist = join(root, 'dist');
    const sibling = join(root, 'dist-secret');
    await mkdir(dist, { recursive: true });
    await mkdir(sibling, { recursive: true });
    await writeFile(join(dist, 'index.html'), '<html>app</html>');
    await writeFile(join(sibling, 'secret.txt'), 'TOP SECRET');

    const previous = process.env.ADMIN_DIST;
    process.env.ADMIN_DIST = dist;
    try {
      const app = createApp({
        db: fakeDb,
        storage,
        onesignal,
        signer,
        cdnBaseUrl: 'https://cdn.example.com',
        secureCookies: false,
      });

      // The SPA entry point works.
      const index = await app.request('/admin/');
      expect(index.status).toBe(200);
      expect(await index.text()).toContain('app');

      // A traversal into a same-prefix sibling must not leak.
      const leaked = await app.request('/admin/..%2Fdist-secret%2Fsecret.txt');
      expect(await leaked.text()).not.toContain('TOP SECRET');

      const direct = await app.request('/admin/../dist-secret/secret.txt');
      expect(await direct.text()).not.toContain('TOP SECRET');
    } finally {
      if (previous === undefined) delete process.env.ADMIN_DIST;
      else process.env.ADMIN_DIST = previous;
      await rm(root, { recursive: true, force: true });
    }
  });
});

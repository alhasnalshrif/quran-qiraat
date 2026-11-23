import { readFile } from 'node:fs/promises';
import { dirname, extname, join, normalize, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

import { Hono } from 'hono';

import type { Database } from './db/client.js';
import { databaseIsHealthy } from './db/client.js';
import { adminRouter } from './routes/admin/index.js';
import { ManifestCache, publicRoutes } from './routes/public.js';
import type { ManifestSigner } from './services/manifest-signer.js';
import type { OneSignal } from './services/onesignal.js';
import type { PackStorage } from './services/storage.js';

export interface AppDependencies {
  db: Database;
  storage: PackStorage;
  onesignal: OneSignal;
  signer: ManifestSigner;
  cdnBaseUrl: string;
  /** Shared so a publish clears the manifest cache (02 §4). */
  manifestCache?: ManifestCache | undefined;
  /** Cookie Secure flag; false only for local HTTP development. */
  secureCookies?: boolean;
  now?: (() => Date) | undefined;
}

/** Builds the Hono app; routes are mounted here as tasks land (02 §4–§5). */
export function createApp({
  db,
  storage,
  onesignal,
  signer,
  cdnBaseUrl,
  manifestCache,
  secureCookies = true,
  now,
}: AppDependencies): Hono {
  const app = new Hono();
  const cache = manifestCache ?? new ManifestCache();

  app.get('/healthz', async (c) => {
    const healthy = await databaseIsHealthy(db);
    return c.json({ ok: healthy }, healthy ? 200 : 503);
  });

  const publicConfig = { sql: db, signer, cdnBaseUrl, cache, now, storage };
  app.route('/v1', publicRoutes(publicConfig));
  // Pack files are requested at /packs/... by the absolute CDN URL inside the
  // manifest, so a second instance serves that path at the root as well.
  app.route('/', publicRoutes(publicConfig));
  app.route(
    '/admin/api',
    adminRouter({ db, storage, onesignal, secureCookies, now, manifestCache: cache }),
  );

  /**
   * Serves the built dashboard on /admin, same origin so there is no CORS and
   * the session cookie simply works (02 §6). Unknown paths fall back to the
   * SPA entry point so client-side routes survive a refresh.
   */
  const adminRoot =
    process.env.ADMIN_DIST ??
    resolve(dirname(fileURLToPath(import.meta.url)), '../../admin/dist');

  app.get('/admin', (c) => c.redirect('/admin/'));
  app.get('/admin/*', async (c) => {
    const relative = c.req.path.replace(/^\/admin\/?/, '') || 'index.html';
    const target = normalize(join(adminRoot, relative));

    // Never serve a path outside the admin build directory.
    if (!target.startsWith(adminRoot)) return c.notFound();

    try {
      const body = await readFile(target);
      return new Response(body, { headers: { 'content-type': contentType(target) } });
    } catch {
      const body = await readFile(join(adminRoot, 'index.html'));
      return new Response(body, { headers: { 'content-type': 'text/html; charset=utf-8' } });
    }
  });

  return app;
}

function contentType(path: string): string {
  switch (extname(path)) {
    case '.js':
      return 'text/javascript; charset=utf-8';
    case '.css':
      return 'text/css; charset=utf-8';
    case '.svg':
      return 'image/svg+xml';
    case '.png':
      return 'image/png';
    case '.woff2':
      return 'font/woff2';
    case '.json':
      return 'application/json';
    default:
      return 'text/html; charset=utf-8';
  }
}

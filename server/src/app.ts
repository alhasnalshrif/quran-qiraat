import { readFile } from 'node:fs/promises';
import { dirname, extname, join, normalize, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

import { Hono } from 'hono';

import type { Database } from './db/client.js';
import { databaseIsHealthy } from './db/client.js';
import { adminRouter } from './routes/admin/index.js';
import { ManifestCache, publicRoutes } from './routes/public.js';
import type { ManifestSigner } from './services/manifest-signer.js';
import type { OneSignal } from './services/onesignal.js';
import type { PackStorage } from './services/storage.js';
import { RateLimiter } from './middleware/rate-limit.js';
import { privacyPage } from './privacy.js';

export interface AppDependencies {
  db: Database;
  storage: PackStorage;
  onesignal: OneSignal;
  signer: ManifestSigner;
  cdnBaseUrl: string;
  /** Shared so a publish clears the manifest cache (02 §4). */
  manifestCache?: ManifestCache | undefined;
  /** Shared limit state for /v1 (02 §4). */
  rateLimiter?: RateLimiter | undefined;
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
  rateLimiter,
  secureCookies = true,
  now,
}: AppDependencies): Hono {
  const app = new Hono();
  const cache = manifestCache ?? new ManifestCache();
  // One limiter for both mounts: publicRoutes is mounted twice (the /v1 API
  // and the root pack path), and separate instances would each keep half the
  // count, letting a client exceed the documented 60/minute.
  const limiter = rateLimiter ?? new RateLimiter();

  /**
   * Every failure answers in the contract's shape (01 §2.3) instead of Hono's
   * default HTML page. The message is intentionally generic: internals never
   * reach a client.
   */
  app.onError((error, c) => {
    console.error(`unhandled error on ${c.req.method} ${c.req.path}:`, error);
    // A response that already started writing cannot be replaced.
    if (c.res && c.res.headers.get('content-type')?.includes('application/json')) {
      return c.res;
    }
    return c.json(
      { error: { code: 'internal', message: 'An internal error occurred.' } },
      500,
    );
  });

  app.notFound((c) =>
    c.json({ error: { code: 'not_found', message: 'No such route.' } }, 404),
  );

  app.get('/healthz', async (c) => {
    const healthy = await databaseIsHealthy(db);
    return c.json({ ok: healthy }, healthy ? 200 : 503);
  });

  app.get('/privacy', (c) => c.html(privacyPage));

  const publicConfig = { sql: db, signer, cdnBaseUrl, cache, now, storage, rateLimiter: limiter };
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

    // Never serve a path outside the admin build directory. The separator
    // matters: a plain prefix check would also allow a sibling such as
    // `dist-secret`, since it starts with the same characters.
    if (target !== adminRoot && !target.startsWith(adminRoot + sep)) {
      return c.notFound();
    }

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

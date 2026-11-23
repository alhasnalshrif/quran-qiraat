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

  app.route(
    '/v1',
    publicRoutes({ sql: db, signer, cdnBaseUrl, cache, now }),
  );
  app.route(
    '/admin/api',
    adminRouter({ db, storage, onesignal, secureCookies, now, manifestCache: cache }),
  );

  return app;
}

import { Hono } from 'hono';

import type { Database } from './db/client.js';
import { databaseIsHealthy } from './db/client.js';
import { adminRouter } from './routes/admin/index.js';

export interface AppDependencies {
  db: Database;
  /** Cookie Secure flag; false only for local HTTP development. */
  secureCookies?: boolean;
  now?: (() => Date) | undefined;
}

/** Builds the Hono app; routes are mounted here as tasks land (02 §4–§5). */
export function createApp({ db, secureCookies = true, now }: AppDependencies): Hono {
  const app = new Hono();

  app.get('/healthz', async (c) => {
    const healthy = await databaseIsHealthy(db);
    return c.json({ ok: healthy }, healthy ? 200 : 503);
  });

  app.route(
    '/admin/api',
    adminRouter({ db, secureCookies, now }),
  );

  return app;
}

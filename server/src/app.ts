import { Hono } from 'hono';

import type { Database } from './db/client.js';
import { databaseIsHealthy } from './db/client.js';

export interface AppDependencies {
  db: Database;
}

/** Builds the Hono app; routes are mounted here as tasks land (02 §4–§5). */
export function createApp({ db }: AppDependencies): Hono {
  const app = new Hono();

  app.get('/healthz', async (c) => {
    const healthy = await databaseIsHealthy(db);
    return c.json({ ok: healthy }, healthy ? 200 : 503);
  });

  return app;
}

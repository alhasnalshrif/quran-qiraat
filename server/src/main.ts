import { serve } from '@hono/node-server';

import { createApp } from './app.js';
import { createDatabase, databaseIsHealthy } from './db/client.js';
import { loadEnv } from './env.js';

/** Starts the server after validating the environment (02 §2, §9). */
async function main(): Promise<void> {
  const env = loadEnv();
  const db = createDatabase(env.DATABASE_URL);

  if (!(await databaseIsHealthy(db))) {
    console.error('Cannot reach the database at DATABASE_URL; refusing to start.');
    process.exitCode = 1;
    await db.end();
    return;
  }

  // Cookies are Secure except on plain-HTTP localhost development.
  const secureCookies = env.PUBLIC_BASE_URL.startsWith('https://');
  const app = createApp({ db, secureCookies });
  const server = serve({ fetch: app.fetch, port: env.PORT }, (info) => {
    console.log(`@quran/server listening on port ${info.port}`);
  });

  const shutdown = async () => {
    server.close();
    await db.end();
  };
  process.on('SIGINT', shutdown);
  process.on('SIGTERM', shutdown);
}

main().catch((error: unknown) => {
  console.error(error instanceof Error ? error.message : error);
  process.exitCode = 1;
});

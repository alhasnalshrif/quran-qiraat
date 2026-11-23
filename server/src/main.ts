import { serve } from '@hono/node-server';

import { createApp } from './app.js';
import { createDatabase, databaseIsHealthy } from './db/client.js';
import { loadEnv } from './env.js';
import { OneSignal } from './services/onesignal.js';
import { PackStorage } from './services/storage.js';

/** Starts the server after validating the environment (02 §2, §9). */
async function main(): Promise<void> {
  const env = loadEnv();
  const db = createDatabase(env.DATABASE_URL);
  const storage = PackStorage.fromEnv(env);
  const onesignal = new OneSignal({
    appIdStable: env.ONESIGNAL_APP_ID_STABLE,
    appIdBeta: env.ONESIGNAL_APP_ID_BETA,
    keyStable: env.ONESIGNAL_REST_API_KEY_STABLE,
    keyBeta: env.ONESIGNAL_REST_API_KEY_BETA,
  });

  if (!(await databaseIsHealthy(db))) {
    console.error('Cannot reach the database at DATABASE_URL; refusing to start.');
    process.exitCode = 1;
    await db.end();
    return;
  }

  // Cookies are Secure except on plain-HTTP localhost development.
  const secureCookies = env.PUBLIC_BASE_URL.startsWith('https://');
  const app = createApp({ db, storage, onesignal, secureCookies });
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

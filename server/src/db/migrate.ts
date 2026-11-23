import { migrate } from 'drizzle-orm/postgres-js/migrator';
import { drizzle } from 'drizzle-orm/postgres-js';

import { createDatabase } from './client.js';
import { loadEnv } from '../env.js';

/** Applies every pending Drizzle migration, then closes the pool (02 §3). */
async function main(): Promise<void> {
  const env = loadEnv();
  const sql = createDatabase(env.DATABASE_URL);
  const db = drizzle(sql);
  await migrate(db, { migrationsFolder: './drizzle' });
  await sql.end();
  console.log('Migrations applied.');
}

main().catch((error: unknown) => {
  console.error(error instanceof Error ? error.message : error);
  process.exitCode = 1;
});

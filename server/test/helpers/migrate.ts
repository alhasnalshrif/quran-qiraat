import { migrate } from 'drizzle-orm/postgres-js/migrator';
import { drizzle } from 'drizzle-orm/postgres-js';

import type { Database } from '../../src/db/client.js';

/** Applies the committed migrations to the test database. */
export async function runMigrations(sql: Database): Promise<void> {
  const db = drizzle(sql);
  await migrate(db, { migrationsFolder: './drizzle' });
}

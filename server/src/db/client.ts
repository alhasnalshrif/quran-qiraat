import postgres from 'postgres';

export type Database = ReturnType<typeof postgres>;

/**
 * Creates the postgres-js client (D3). A small pool keeps a single VPS happy
 * (D5); callers close it on shutdown.
 */
export function createDatabase(url: string): Database {
  return postgres(url, {
    max: 10,
    idle_timeout: 30,
    onnotice: () => {},
  });
}

/** True when the database answers a trivial query (02 §4 `/healthz`). */
export async function databaseIsHealthy(db: Database): Promise<boolean> {
  try {
    await db`select 1`;
    return true;
  } catch {
    return false;
  }
}

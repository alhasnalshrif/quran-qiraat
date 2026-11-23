import { createInterface } from 'node:readline/promises';

import { createDatabase } from './db/client.js';
import { loadEnv } from './env.js';
import { assertPasswordPolicy, hashPassword, minPasswordLength } from './services/auth.js';

/**
 * `pnpm --filter server create-owner --email …` — creates the first owner
 * account by prompting for a password. There is no self-registration (02 §5).
 */
async function main(): Promise<void> {
  const email = readEmailArg(process.argv.slice(2));
  if (!email) {
    console.error('Usage: create-owner --email <address>');
    process.exitCode = 1;
    return;
  }

  const env = loadEnv();
  const password = await readPassword();
  try {
    assertPasswordPolicy(password);
  } catch (error) {
    console.error(error instanceof Error ? error.message : error);
    process.exitCode = 1;
    return;
  }

  const sql = createDatabase(env.DATABASE_URL);
  try {
    const existing = await sql<{ id: string }[]>`
      select id from admin_users where email = ${email.toLowerCase()} limit 1
    `;
    if (existing.length > 0) {
      console.error(`An account already exists for ${email}.`);
      process.exitCode = 1;
      return;
    }

    const passwordHash = await hashPassword(password);
    const rows = await sql<{ id: string }[]>`
      insert into admin_users (email, password_hash, role)
      values (${email.toLowerCase()}, ${passwordHash}, 'owner')
      returning id
    `;
    console.log(`Created owner ${email} (${rows[0]?.id}).`);
  } finally {
    await sql.end();
  }
}

function readEmailArg(args: string[]): string | null {
  const index = args.indexOf('--email');
  const value = index >= 0 ? args[index + 1] : args.find((arg) => arg.startsWith('--email='))?.slice(8);
  return value && value.includes('@') ? value : null;
}

async function readPassword(): Promise<string> {
  const rl = createInterface({ input: process.stdin, output: process.stdout });
  try {
    const password = await rl.question(`Password (at least ${minPasswordLength} characters): `);
    return password.trim();
  } finally {
    rl.close();
  }
}

main().catch((error: unknown) => {
  console.error(error instanceof Error ? error.message : error);
  process.exitCode = 1;
});

#!/usr/bin/env node
/**
 * Publishes one pack's files up to `validated` in one command (02 §7).
 *
 *   node tool/publish_pack.mjs --pack qiraat-farsh --server https://api.example.com \
 *     --source-name "Quran Tajweed Engine" --source-revision <sha> --notes "…" \
 *     assets/qiraat/variants.json assets/qiraat/LICENSE-QuranTajweedEngine.txt
 *
 * It signs in (the password is read from the terminal or PACK_PASSWORD), creates
 * the version, uploads each file to its presigned URL, and runs validation.
 * Releasing to a channel stays a deliberate action in the dashboard.
 */
import { createHash } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import { basename } from 'node:path';
import { createInterface } from 'node:readline/promises';

const args = parseArgs(process.argv.slice(2));

if (!args.pack || !args.server || args.files.length === 0) {
  fail(
    'Usage: publish_pack.mjs --pack <id> --server <url> [--email <address>] ' +
      '[--format <name@version>] [--source-name <name>] [--source-revision <sha>] ' +
      '[--notes <ar>] <file...>',
  );
}

/** The format each pack ships, from 01 §1.1. */
const packFormats = {
  'editions-manifest': 'editions-manifest@1',
  'hafs-text': 'kfgqpc-ayahs@1',
  'riwayah-shubah-text': 'kfgqpc-ayahs@1',
  'riwayah-qalun-text': 'kfgqpc-ayahs@1',
  'hafs-layout-1405': 'mushaf-layout@1',
  'mapping-hafs-qalun': 'ayah-map@1',
  'qiraat-farsh': 'qiraat-variants@1',
  'published-differences': 'published-differences@1',
  'navigation-hizbs': 'hizb-starts@1',
};

const server = args.server.replace(/\/$/, '');

try {
  const email = args.email ?? (await prompt('Email: '));
  const password = process.env.PACK_PASSWORD ?? (await promptPassword('Password: '));

  const session = await login(email, password);
  console.log(`Signed in as ${session.user.email} (${session.user.role}).`);

  const version = await createVersion(session);
  console.log(`Created ${args.pack} v${version.version} (${version.id}).`);

  await uploadFiles(session, version.id);
  await validate(session, version.id);

  console.log(`\n${args.pack} v${version.version} is validated.`);
  console.log('Release it to beta or stable from the dashboard.');
} catch (error) {
  fail(error instanceof Error ? error.message : String(error));
}

// -----------------------------------------------------------------------------

function parseArgs(argv) {
  const parsed = {
    pack: undefined,
    server: undefined,
    email: undefined,
    format: undefined,
    'source-name': undefined,
    'source-revision': undefined,
    notes: undefined,
    files: [],
  };
  for (let index = 0; index < argv.length; index++) {
    const arg = argv[index];
    if (arg.startsWith('--')) {
      const name = arg.slice(2);
      const value = argv[index + 1];
      if (value === undefined || value.startsWith('--')) fail(`Missing value for --${name}.`);
      parsed[name] = value;
      index++;
    } else {
      parsed.files.push(arg);
    }
  }
  return {
    pack: parsed.pack,
    server: parsed.server,
    email: parsed.email,
    format: parsed.format,
    sourceName: parsed['source-name'],
    sourceRevision: parsed['source-revision'],
    notes: parsed.notes,
    files: parsed.files,
  };
}

async function login(email, password) {
  const response = await fetch(`${server}/admin/api/login`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ email, password }),
  });
  if (!response.ok) throw new Error(`Login failed (${response.status}): ${await response.text()}`);

  const cookie = response.headers.get('set-cookie') ?? '';
  const token = cookie.match(/qs_session=([^;]+)/)?.[1];
  if (!token) throw new Error('Login returned no session cookie.');

  const body = await response.json();
  return { cookie: `qs_session=${token}`, csrf: body.csrfToken, user: body.user };
}

async function createVersion(session) {
  const format = args.format ?? packFormats[args.pack];
  if (!format) {
    fail(`Unknown pack ${args.pack}. Pass --format explicitly.`);
  }
  const response = await call(session, 'POST', `/admin/api/packs/${args.pack}/versions`, {
    format,
    sourceName: args.sourceName,
    sourceRevision: args.sourceRevision,
    notesAr: args.notes,
  });
  return response;
}

async function uploadFiles(session, versionId) {
  const files = [];
  for (const path of args.files) {
    const bytes = await readFile(path);
    files.push({
      path: basename(path),
      sha256: createHash('sha256').update(bytes).digest('hex'),
      size: bytes.byteLength,
      bytes,
    });
  }

  const { uploads } = await call(session, 'POST', `/admin/api/pack-versions/${versionId}/files`, {
    files: files.map(({ path, sha256, size }) => ({ path, sha256, size })),
  });

  for (const upload of uploads) {
    const file = files.find((candidate) => candidate.path === upload.path);
    if (!file) throw new Error(`The server asked for an unknown file ${upload.path}.`);
    const response = await fetch(upload.url, { method: 'PUT', body: file.bytes });
    if (!response.ok) {
      throw new Error(`Upload of ${file.path} failed (${response.status}).`);
    }
    console.log(`Uploaded ${file.path} (${file.size} bytes).`);
  }
}

async function validate(session, versionId) {
  const result = await call(session, 'POST', `/admin/api/pack-versions/${versionId}/validate`, {});
  console.log(`Validation passed (${result.files} files).`);
}

async function call(session, method, path, body) {
  const response = await fetch(`${server}${path}`, {
    method,
    headers: {
      'content-type': 'application/json',
      cookie: session.cookie,
      ...(method === 'GET' ? {} : { 'X-CSRF-Token': session.csrf }),
    },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  });
  if (!response.ok) {
    const text = await response.text();
    throw new Error(`${method} ${path} failed (${response.status}): ${text}`);
  }
  return response.json();
}

async function prompt(question) {
  const rl = createInterface({ input: process.stdin, output: process.stdout });
  try {
    return (await rl.question(question)).trim();
  } finally {
    rl.close();
  }
}

async function promptPassword(question) {
  // Without a TTY (CI), require the environment variable rather than hang.
  if (!process.stdin.isTTY) {
    throw new Error('Set PACK_PASSWORD when running without a terminal.');
  }
  return prompt(question);
}

function fail(message) {
  console.error(message);
  process.exit(1);
}

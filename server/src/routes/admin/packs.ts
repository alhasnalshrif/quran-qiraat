import { Hono, type Context } from 'hono';

import { validateFormat } from '@quran/contracts';

import type { Database } from '../../db/client.js';
import {
  audit,
  canTransition,
  isAllowedPackId,
  isSafePackPath,
  storageKey,
  TransitionError,
  type Channel,
  type PackVersionStatus,
} from '../../services/packs.js';
import type { PackStorage } from '../../services/storage.js';
import type { ActiveSession } from '../../services/sessions.js';
import { requireRole } from '../../middleware/auth.js';

export interface PackRoutesOptions {
  sql: Database;
  storage: PackStorage;
}

type Env = { Variables: { session: ActiveSession } };

interface VersionRow {
  id: string;
  pack_id: string;
  version: number;
  format: string;
  min_app_build: number;
  status: PackVersionStatus;
  source_name: string | null;
  source_revision: string | null;
  notes_ar: string | null;
}

interface FileRow {
  pack_version_id: string;
  path: string;
  object_key: string;
  sha256: string;
  size: number;
}

const channels: Channel[] = ['stable', 'beta', 'internal'];

/**
 * Pack and version routes of 02 §5: create packs and draft versions, get
 * uploads, validate against the stored bytes and the contract validators,
 * release to a channel, and revoke.
 */
export function packRoutes({ sql, storage }: PackRoutesOptions): Hono<Env> {
  const app = new Hono<Env>();

  app.get('/packs', async (c) => {
    const packs = await sql<{ id: string; title_ar: string; format_family: string }[]>`
      select id, title_ar, format_family from packs order by id
    `;
    const releases = await sql<
      { pack_id: string; channel: Channel; version: number; status: PackVersionStatus }[]
    >`
      select pv.pack_id, cr.channel, pv.version, pv.status
      from channel_releases cr
      join pack_versions pv on pv.id = cr.pack_version_id
      order by pv.pack_id, cr.channel, pv.version desc
    `;

    return c.json({
      packs: packs.map((pack) => {
        const latest: Record<string, number> = {};
        for (const release of releases) {
          if (release.pack_id !== pack.id) continue;
          if (release.status !== 'published') continue;
          const current = latest[release.channel];
          if (current === undefined || release.version > current) {
            latest[release.channel] = release.version;
          }
        }
        return {
          packId: pack.id,
          titleAr: pack.title_ar,
          formatFamily: pack.format_family,
          channels: latest,
        };
      }),
    });
  });

  app.post('/packs', requireRole('owner'), async (c) => {
    const body = await readJson(c);
    const packId = typeof body.packId === 'string' ? body.packId : '';
    if (!isAllowedPackId(packId)) {
      return error(c, 400, `Unknown packId ${packId}; it must come from the protocol list.`);
    }
    const titleAr = typeof body.titleAr === 'string' ? body.titleAr.trim() : '';
    const formatFamily =
      typeof body.formatFamily === 'string' ? body.formatFamily.trim() : '';
    if (!titleAr || !formatFamily) {
      return error(c, 400, 'titleAr and formatFamily are required.');
    }

    const existing = await sql<{ id: string }[]>`select id from packs where id = ${packId}`;
    if (existing.length > 0) return error(c, 409, `Pack ${packId} already exists.`);

    await sql`
      insert into packs (id, title_ar, description_ar, format_family)
      values (${packId}, ${titleAr}, ${
        typeof body.descriptionAr === 'string' ? body.descriptionAr : null
      }, ${formatFamily})
    `;
    await audit(sql, {
      userId: c.get('session').user.id,
      action: 'pack.create',
      target: packId,
    });

    return c.json({ packId }, 201);
  });

  app.get('/packs/:id/versions', async (c) => {
    const packId = c.req.param('id');
    const versions = await sql<VersionRow[]>`
      select id, pack_id, version, format, min_app_build, status,
             source_name, source_revision, notes_ar
      from pack_versions where pack_id = ${packId}
      order by version desc
    `;
    const releaseRows = await sql<{ channel: Channel; version: number }[]>`
      select cr.channel, pv.version
      from channel_releases cr
      join pack_versions pv on pv.id = cr.pack_version_id
      where pv.pack_id = ${packId}
    `;

    return c.json({
      versions: versions.map((version) => ({
        id: version.id,
        version: version.version,
        format: version.format,
        minAppBuild: version.min_app_build,
        status: version.status,
        source: version.source_name
          ? { name: version.source_name, revision: version.source_revision }
          : null,
        notes: version.notes_ar ? { ar: version.notes_ar } : null,
        channels: releaseRows
          .filter((release) => release.version === version.version)
          .map((release) => release.channel),
      })),
    });
  });

  app.post('/packs/:id/versions', requireRole('owner', 'editor'), async (c) => {
    const packId = c.req.param('id');
    const body = await readJson(c);

    const [pack] = await sql<{ id: string }[]>`select id from packs where id = ${packId}`;
    if (!pack) return error(c, 404, `Unknown pack ${packId}.`);

    const format = typeof body.format === 'string' ? body.format.trim() : '';
    if (!/^[a-z0-9-]+@\d+$/.test(format)) {
      return error(c, 400, 'format must look like name@version.');
    }

    // Versions only ever increase, even after a revoke (01 §1.3).
    const [next] = await sql<{ next: number }[]>`
      select coalesce(max(version), 0) + 1 as next from pack_versions where pack_id = ${packId}
    `;
    const version = next!.next;
    const minAppBuild =
      typeof body.minAppBuild === 'number' && Number.isInteger(body.minAppBuild)
        ? body.minAppBuild
        : 1;

    const [created] = await sql<{ id: string }[]>`
      insert into pack_versions
        (pack_id, version, format, min_app_build, status, source_name, source_revision, notes_ar, created_by)
      values (${packId}, ${version}, ${format}, ${minAppBuild}, 'draft',
              ${typeof body.sourceName === 'string' ? body.sourceName : null},
              ${typeof body.sourceRevision === 'string' ? body.sourceRevision : null},
              ${typeof body.notesAr === 'string' ? body.notesAr : null},
              ${c.get('session').user.id})
      returning id
    `;
    await audit(sql, {
      userId: c.get('session').user.id,
      action: 'pack_version.create',
      target: created!.id,
      details: { packId, version, format },
    });

    return c.json({ id: created!.id, packId, version, format, status: 'draft' }, 201);
  });

  /** Presigned PUT per file, 15 minutes (02 §5). */
  app.post('/pack-versions/:vid/files', requireRole('owner', 'editor'), async (c) => {
    const found = await loadVersion(sql, c.req.param('vid'));
    if (!found) return error(c, 404, 'Unknown pack version.');
    if (found.status !== 'draft') {
      return error(c, 409, `Only a draft version accepts uploads (status: ${found.status}).`);
    }

    const body = await readJson(c);
    const files = Array.isArray(body.files) ? body.files : [];
    if (files.length === 0) return error(c, 400, 'files must be a non-empty array.');

    const uploads: { path: string; url: string; objectKey: string }[] = [];
    for (const raw of files) {
      const file = raw as Record<string, unknown>;
      const path = typeof file.path === 'string' ? file.path : '';
      const sha256 = typeof file.sha256 === 'string' ? file.sha256.toLowerCase() : '';
      const size = typeof file.size === 'number' ? file.size : -1;

      if (!isSafePackPath(path)) return error(c, 400, `Unsafe file path ${path}.`);
      if (!/^[0-9a-f]{64}$/.test(sha256)) {
        return error(c, 400, `File ${path} needs a 64-character lowercase sha256.`);
      }
      if (!Number.isInteger(size) || size < 0) {
        return error(c, 400, `File ${path} needs a non-negative integer size.`);
      }

      const key = storageKey(found.pack_id, found.version, path);
      // The row is created up front so validate() knows what to expect.
      await sql`
        insert into pack_files (pack_version_id, path, object_key, sha256, size)
        values (${found.id}, ${path}, ${key}, ${sha256}, ${size})
        on conflict (pack_version_id, path) do update
          set object_key = excluded.object_key,
              sha256 = excluded.sha256,
              size = excluded.size
      `;
      uploads.push({ path, objectKey: key, url: await storage.presignedUploadUrl(key) });
    }

    return c.json({ uploads });
  });

  /**
   * Reads each stored file, matches size and sha256, then runs the format
   * validator. Success moves the version to `validated` (02 §5).
   */
  app.post('/pack-versions/:vid/validate', requireRole('owner', 'editor'), async (c) => {
    const found = await loadVersion(sql, c.req.param('vid'));
    if (!found) return error(c, 404, 'Unknown pack version.');

    const files = await sql<FileRow[]>`
      select pack_version_id, path, object_key, sha256, size
      from pack_files where pack_version_id = ${found.id}
    `;
    if (files.length === 0) return error(c, 409, 'No files were declared for this version.');

    const contents = new Map<string, Uint8Array>();
    for (const file of files) {
      const inspected = await storage.inspectObject(file.object_key);
      if (!inspected) {
        return error(c, 422, `Missing upload for ${file.path}.`);
      }
      if (inspected.size !== Number(file.size)) {
        return error(
          c,
          422,
          `Size mismatch for ${file.path}: expected ${file.size}, found ${inspected.size}.`,
        );
      }
      if (inspected.sha256 !== file.sha256) {
        return error(c, 422, `sha256 mismatch for ${file.path}.`);
      }
      contents.set(file.path, inspected.bytes);
    }

    const document = parsePrimaryDocument(found.format, contents);
    if (document.error) return error(c, 422, document.error);

    const result = validateFormat(found.format, document.value);
    if (!result.ok) {
      return error(c, 422, `Validator rejected ${found.format}: ${result.errors.join('; ')}`);
    }

    const moved = await moveStatus(sql, found, 'validated');
    if (!moved) return error(c, 409, `Cannot validate a ${found.status} version.`);

    await audit(sql, {
      userId: c.get('session').user.id,
      action: 'pack_version.validate',
      target: found.id,
      details: { packId: found.pack_id, version: found.version },
    });

    return c.json({ status: 'validated', files: files.length });
  });

  app.post('/pack-versions/:vid/release', requireRole('owner', 'editor'), async (c) => {
    const body = await readJson(c);
    const channel = body.channel as Channel;
    if (!channels.includes(channel)) {
      return error(c, 400, 'channel must be stable, beta or internal.');
    }
    // Editors may ship beta/internal; only an owner may ship stable (02 §5).
    if (channel === 'stable' && c.get('session').user.role !== 'owner') {
      return error(c, 403, 'Only an owner may release to stable.');
    }

    const found = await loadVersion(sql, c.req.param('vid'));
    if (!found) return error(c, 404, 'Unknown pack version.');
    if (found.status !== 'validated' && found.status !== 'published') {
      return error(c, 409, `A version must be validated before release (status: ${found.status}).`);
    }

    await sql`
      insert into channel_releases (channel, pack_version_id)
      values (${channel}, ${found.id})
      on conflict do nothing
    `;
    if (found.status === 'validated') {
      await moveStatus(sql, found, 'published');
    }

    await audit(sql, {
      userId: c.get('session').user.id,
      action: 'pack_version.publish',
      target: found.id,
      details: { packId: found.pack_id, version: found.version, channel },
    });

    return c.json({ status: 'published', channel });
  });

  app.post('/pack-versions/:vid/revoke', requireRole('owner'), async (c) => {
    const found = await loadVersion(sql, c.req.param('vid'));
    if (!found) return error(c, 404, 'Unknown pack version.');
    if (!canTransition(found.status, 'revoked')) {
      return error(c, 409, new TransitionError(found.status, 'revoked').message);
    }

    await sql`delete from channel_releases where pack_version_id = ${found.id}`;
    await moveStatus(sql, found, 'revoked');
    await audit(sql, {
      userId: c.get('session').user.id,
      action: 'pack_version.revoke',
      target: found.id,
      details: { packId: found.pack_id, version: found.version },
    });

    return c.json({ status: 'revoked' });
  });

  return app;
}

async function loadVersion(
  sql: Database,
  id: string,
): Promise<VersionRow | null> {
  if (!/^[0-9a-f-]{36}$/i.test(id)) return null;
  const rows = await sql<VersionRow[]>`
    select id, pack_id, version, format, min_app_build, status,
           source_name, source_revision, notes_ar
    from pack_versions where id = ${id} limit 1
  `;
  return rows[0] ?? null;
}

async function moveStatus(
  sql: Database,
  version: VersionRow,
  next: PackVersionStatus,
): Promise<boolean> {
  if (!canTransition(version.status, next)) return false;
  await sql`
    update pack_versions set status = ${next}, updated_at = now() where id = ${version.id}
  `;
  return true;
}

/**
 * The document the validator checks: the pack's primary JSON file. For packs
 * with one JSON file that is unambiguous; a pack with several needs the first
 * JSON in the list, which the contract defines per format.
 */
function parsePrimaryDocument(
  format: string,
  contents: Map<string, Uint8Array>,
): { value: unknown; error?: undefined } | { value?: undefined; error: string } {
  const jsonFiles = [...contents.keys()].filter((path) => path.endsWith('.json'));
  if (jsonFiles.length === 0) return { error: `No JSON file to validate for ${format}.` };

  const primary = jsonFiles[0]!;
  try {
    return { value: JSON.parse(new TextDecoder().decode(contents.get(primary)!)) };
  } catch (cause) {
    return {
      error: `${primary} is not valid JSON: ${cause instanceof Error ? cause.message : String(cause)}`,
    };
  }
}

function error(
  c: Context,
  status: 400 | 401 | 403 | 404 | 409 | 422,
  message: string,
) {
  const code =
    status === 404
      ? 'not_found'
      : status === 401 || status === 403
        ? 'invalid_request'
        : 'invalid_request';
  return c.json({ error: { code, message } }, status);
}

async function readJson(c: Context): Promise<Record<string, unknown>> {
  try {
    const body = await c.req.json();
    return typeof body === 'object' && body !== null
      ? (body as Record<string, unknown>)
      : {};
  } catch {
    return {};
  }
}

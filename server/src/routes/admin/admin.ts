import { Hono, type Context } from 'hono';

import { configKeyNames, isConfigKey } from '@quran/contracts';

import type { Database } from '../../db/client.js';
import { requireRole } from '../../middleware/auth.js';
import { allowedLinkPrefixes, isAllowedLink } from '../../services/links.js';
import { audit, type Channel } from '../../services/packs.js';
import type { ActiveSession } from '../../services/sessions.js';

export interface AdminRoutesOptions {
  sql: Database;
}

type Env = { Variables: { session: ActiveSession } };

const channels: Channel[] = ['stable', 'beta', 'internal'];
const platforms = ['ios', 'android'] as const;

/**
 * Platforms, remote config, announcements, users and the audit log (02 §5).
 * Notifications live in their own file because they call OneSignal.
 */
export function adminRoutes({ sql }: AdminRoutesOptions): Hono<Env> {
  const app = new Hono<Env>();

  // ---------------------------------------------------------------------------
  // Platforms (owner)
  // ---------------------------------------------------------------------------
  app.get('/platforms/:platform', requireRole('owner', 'editor'), async (c) => {
    const platform = c.req.param('platform');
    if (!platforms.includes(platform as (typeof platforms)[number])) {
      return failure(c, 400, 'platform must be ios or android.');
    }
    const [row] = await sql<PlatformRow[]>`
      select platform, latest_build, min_supported_build, store_url, message_ar
      from app_platforms where platform = ${platform}
    `;
    return c.json({ platform: row ? toPlatform(row) : null });
  });

  app.put('/platforms/:platform', requireRole('owner'), async (c) => {
    const platform = c.req.param('platform');
    if (!platforms.includes(platform as (typeof platforms)[number])) {
      return failure(c, 400, 'platform must be ios or android.');
    }
    const body = await readJson(c);
    const latestBuild = intOrNull(body.latestBuild);
    const minSupportedBuild = intOrNull(body.minSupportedBuild);
    if (latestBuild === null || minSupportedBuild === null || latestBuild < minSupportedBuild) {
      return failure(
        c,
        400,
        'latestBuild and minSupportedBuild are required and latest ≥ min.',
      );
    }

    await sql`
      insert into app_platforms (platform, latest_build, min_supported_build, store_url, message_ar)
      values (${platform}, ${latestBuild}, ${minSupportedBuild},
              ${strOrNull(body.storeUrl)}, ${strOrNull(body.messageAr)})
      on conflict (platform) do update
        set latest_build = excluded.latest_build,
            min_supported_build = excluded.min_supported_build,
            store_url = excluded.store_url,
            message_ar = excluded.message_ar,
            updated_at = now()
    `;
    await auditFor(c, sql, 'platform.update', platform, { latestBuild, minSupportedBuild });
    return c.json({ ok: true });
  });

  // ---------------------------------------------------------------------------
  // Remote config (owner): keys come from the contract only (01 §4)
  // ---------------------------------------------------------------------------
  app.get('/config', requireRole('owner'), async (c) => {
    const rows = await sql<ConfigRow[]>`
      select key, channel, platform, min_build, max_build, value
      from remote_config order by key, channel
    `;
    return c.json({
      config: rows.map((row) => ({
        key: row.key,
        channel: row.channel,
        platform: row.platform,
        minBuild: row.min_build,
        maxBuild: row.max_build,
        value: row.value,
      })),
    });
  });

  app.post('/config', requireRole('owner'), async (c) => {
    const body = await readJson(c);
    const key = typeof body.key === 'string' ? body.key : '';
    if (!isConfigKey(key)) {
      return failure(c, 400, `Unknown config key ${key}; it must come from 01 §4.`);
    }
    const channel = body.channel as Channel;
    if (!channels.includes(channel)) return failure(c, 400, 'Invalid channel.');
    const platform = body.platform === null || body.platform === undefined
      ? null
      : String(body.platform);
    if (platform !== null && !platforms.includes(platform as (typeof platforms)[number])) {
      return failure(c, 400, 'platform must be ios, android or null.');
    }

    const problem = validateConfigValue(key, body.value);
    if (problem) return failure(c, 400, problem);

    // Postgres treats NULLs as distinct, so uniqueness is enforced here.
    const platformValue = platform ?? null;
    const minBuild = intOrNull(body.minBuild);
    const maxBuild = intOrNull(body.maxBuild);
    const existing = await sql<{ id: string }[]>`
      select id from remote_config
      where key = ${key} and channel = ${channel}::channel
        and platform is not distinct from ${platformValue}::platform
        and min_build is not distinct from ${minBuild}
        and max_build is not distinct from ${maxBuild}
      limit 1
    `;
    if (existing.length > 0) {
      return failure(c, 409, 'This key already has a value for that scope.');
    }

    await sql`
      insert into remote_config (key, channel, platform, min_build, max_build, value)
      values (${key}, ${channel}::channel, ${platformValue}::platform, ${minBuild},
              ${maxBuild}, ${JSON.stringify(body.value)}::jsonb)
    `;
    await auditFor(c, sql, 'config.create', key, { channel, platform });
    return c.json({ ok: true }, 201);
  });

  app.delete('/config', requireRole('owner'), async (c) => {
    const body = await readJson(c);
    const key = typeof body.key === 'string' ? body.key : '';
    if (!isConfigKey(key)) return failure(c, 400, 'Unknown config key.');
    const channel = body.channel as Channel;
    if (!channels.includes(channel)) return failure(c, 400, 'Invalid channel.');

    await sql`
      delete from remote_config
      where key = ${key} and channel = ${channel}
        and platform is not distinct from ${body.platform ? String(body.platform) : null}
    `;
    await auditFor(c, sql, 'config.delete', key, { channel });
    return c.json({ ok: true });
  });

  // ---------------------------------------------------------------------------
  // Announcements (editor)
  // ---------------------------------------------------------------------------
  app.get('/announcements', requireRole('owner', 'editor'), async (c) => {
    const rows = await sql<AnnouncementRow[]>`
      select id, title_ar, body_ar, url, channel, platform, starts_at, ends_at, priority, published
      from announcements order by starts_at desc
    `;
    return c.json({ announcements: rows.map(toAnnouncement) });
  });

  app.post('/announcements', requireRole('owner', 'editor'), async (c) => {
    const body = await readJson(c);
    const id = typeof body.id === 'string' ? body.id.trim() : '';
    const titleAr = typeof body.titleAr === 'string' ? body.titleAr.trim() : '';
    const bodyAr = typeof body.bodyAr === 'string' ? body.bodyAr.trim() : '';
    if (!id || !titleAr || !bodyAr) {
      return failure(c, 400, 'id, titleAr and bodyAr are required.');
    }
    const channel = body.channel as Channel;
    if (!channels.includes(channel)) return failure(c, 400, 'Invalid channel.');

    const startsAt = parseDate(body.startsAt);
    const endsAt = parseDate(body.endsAt);
    if (!startsAt || !endsAt || endsAt <= startsAt) {
      return failure(c, 400, 'startsAt and endsAt are required, with endsAt after startsAt.');
    }

    await sql`
      insert into announcements
        (id, title_ar, body_ar, url, channel, platform, starts_at, ends_at, priority, published)
      values (${id}, ${titleAr}, ${bodyAr}, ${strOrNull(body.url)}, ${channel},
              ${strOrNull(body.platform)}, ${startsAt.toISOString()}::timestamptz,
              ${endsAt.toISOString()}::timestamptz,
              ${body.priority === 'high' ? 'high' : 'normal'}::announcement_priority,
              ${body.published === true})
    `;
    await auditFor(c, sql, 'announcement.create', id, { channel });
    return c.json({ id }, 201);
  });

  app.put('/announcements/:id', requireRole('owner', 'editor'), async (c) => {
    const body = await readJson(c);
    const id = c.req.param('id');
    const published = body.published;
    if (typeof published !== 'boolean') return failure(c, 400, 'published must be a boolean.');

    const updated = await sql`
      update announcements set published = ${published}, updated_at = now()
      where id = ${id} returning id
    `;
    if (updated.length === 0) return failure(c, 404, 'Unknown announcement.');
    await auditFor(c, sql, 'announcement.update', id, { published });
    return c.json({ ok: true });
  });

  app.delete('/announcements/:id', requireRole('owner', 'editor'), async (c) => {
    const id = c.req.param('id');
    const deleted = await sql`delete from announcements where id = ${id} returning id`;
    if (deleted.length === 0) return failure(c, 404, 'Unknown announcement.');
    await auditFor(c, sql, 'announcement.delete', id);
    return c.json({ ok: true });
  });

  // ---------------------------------------------------------------------------
  // Users (owner): add editors, disable accounts
  // ---------------------------------------------------------------------------
  app.get('/users', requireRole('owner'), async (c) => {
    const rows = await sql<
      { id: string; email: string; role: string; disabled: boolean; last_login_at: string | null }[]
    >`
      select id, email, role, disabled, last_login_at from admin_users order by email
    `;
    return c.json({
      users: rows.map((row) => ({
        id: row.id,
        email: row.email,
        role: row.role,
        disabled: row.disabled,
        lastLoginAt: row.last_login_at,
      })),
    });
  });

  app.put('/users/:id', requireRole('owner'), async (c) => {
    const body = await readJson(c);
    if (typeof body.disabled !== 'boolean') return failure(c, 400, 'disabled must be a boolean.');
    const id = c.req.param('id');

    // An owner must not lock themselves out.
    if (id === c.get('session').user.id && body.disabled) {
      return failure(c, 400, 'You cannot disable your own account.');
    }

    const updated = await sql`
      update admin_users set disabled = ${body.disabled}, updated_at = now()
      where id = ${id} returning id
    `;
    if (updated.length === 0) return failure(c, 404, 'Unknown user.');
    await auditFor(c, sql, 'user.update', id, { disabled: body.disabled });
    return c.json({ ok: true });
  });

  // ---------------------------------------------------------------------------
  // Audit log (owner, paginated)
  // ---------------------------------------------------------------------------
  app.get('/audit', requireRole('owner'), async (c) => {
    const limit = Math.min(Math.max(Number(c.req.query('limit') ?? 50), 1), 200);
    const offset = Math.max(Number(c.req.query('offset') ?? 0), 0);

    const rows = await sql<AuditRow[]>`
      select a.id, a.action, a.target, a.details, a.at, u.email
      from audit_log a left join admin_users u on u.id = a.user_id
      order by a.at desc limit ${limit} offset ${offset}
    `;
    const [count] = await sql<{ total: string }[]>`select count(*)::text as total from audit_log`;

    return c.json({
      entries: rows.map((row) => ({
        id: row.id,
        action: row.action,
        target: row.target,
        details: row.details,
        at: row.at,
        user: row.email,
      })),
      total: Number(count!.total),
      limit,
      offset,
    });
  });

  return app;
}

export { allowedLinkPrefixes, configKeyNames, isAllowedLink };

interface PlatformRow {
  platform: string;
  latest_build: number;
  min_supported_build: number;
  store_url: string | null;
  message_ar: string | null;
}

interface ConfigRow {
  key: string;
  channel: Channel;
  platform: string | null;
  min_build: number | null;
  max_build: number | null;
  value: unknown;
}

interface AnnouncementRow {
  id: string;
  title_ar: string;
  body_ar: string;
  url: string | null;
  channel: Channel;
  platform: string | null;
  starts_at: string | Date;
  ends_at: string | Date;
  priority: string;
  published: boolean;
}

interface AuditRow {
  id: string;
  action: string;
  target: string | null;
  details: unknown;
  at: string | Date;
  email: string | null;
}

function toPlatform(row: PlatformRow) {
  return {
    platform: row.platform,
    latestBuild: row.latest_build,
    minSupportedBuild: row.min_supported_build,
    storeUrl: row.store_url,
    messageAr: row.message_ar,
  };
}

function toAnnouncement(row: AnnouncementRow) {
  return {
    id: row.id,
    titleAr: row.title_ar,
    bodyAr: row.body_ar,
    url: row.url,
    channel: row.channel,
    platform: row.platform,
    startsAt: new Date(row.starts_at).toISOString(),
    endsAt: new Date(row.ends_at).toISOString(),
    priority: row.priority,
    published: row.published,
  };
}

/** Type check for one config key, mirroring 01 §4. */
function validateConfigValue(key: string, value: unknown): string | null {
  switch (key) {
    case 'updates.checkIntervalHours':
      return typeof value === 'number' &&
        Number.isInteger(value) &&
        value >= 1 &&
        value <= 168
        ? null
        : 'updates.checkIntervalHours must be an integer between 1 and 168.';
    case 'updates.wifiOnlyDefault':
    case 'features.audio':
    case 'features.announcements':
      return typeof value === 'boolean' ? null : `${key} must be a boolean.`;
    case 'audio.reciters':
      return Array.isArray(value) ? null : `${key} must be a list.`;
    default:
      return `Unknown config key ${key}.`;
  }
}

async function auditFor(
  c: Context<Env>,
  sql: Database,
  action: string,
  target: string,
  details?: unknown,
): Promise<void> {
  await audit(sql, {
    userId: c.get('session').user.id,
    action,
    target,
    ...(details === undefined ? {} : { details }),
  });
}

function failure(
  c: Context,
  status: 400 | 403 | 404 | 409,
  message: string,
) {
  return c.json(
    { error: { code: status === 404 ? 'not_found' : 'invalid_request', message } },
    status,
  );
}

function intOrNull(value: unknown): number | null {
  return typeof value === 'number' && Number.isInteger(value) ? value : null;
}

function strOrNull(value: unknown): string | null {
  return typeof value === 'string' && value.trim() ? value.trim() : null;
}

function parseDate(value: unknown): Date | null {
  if (typeof value !== 'string') return null;
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? null : date;
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

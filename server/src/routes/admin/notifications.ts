import { Hono, type Context } from 'hono';

import type { Database } from '../../db/client.js';
import { requireRole } from '../../middleware/auth.js';
import { audit } from '../../services/packs.js';
import { OneSignal, OneSignalError } from '../../services/onesignal.js';
import { isAllowedLink } from '../../services/links.js';
import type { ActiveSession } from '../../services/sessions.js';

export interface NotificationRoutesOptions {
  sql: Database;
  onesignal: OneSignal;
  now?: (() => Date) | undefined;
}

type Env = { Variables: { session: ActiveSession } };
type SendChannel = 'stable' | 'beta';

interface NotificationRow {
  id: string;
  channel: string;
  title_ar: string;
  body_ar: string;
  link: string | null;
  target_platforms: string[];
  target_min_build: number | null;
  target_max_build: number | null;
  scheduled_at: string | Date | null;
  status: string;
  onesignal_id: string | null;
  recipients: number | null;
  error: string | null;
}

/**
 * Notification routes of 02 §5 (D18): create a draft, send a test to one
 * device, send or schedule to a channel, and cancel before its time.
 */
export function notificationRoutes({
  sql,
  onesignal,
  now = () => new Date(),
}: NotificationRoutesOptions): Hono<Env> {
  const app = new Hono<Env>();

  app.get('/notifications', requireRole('owner', 'editor'), async (c) => {
    const rows = await sql<NotificationRow[]>`
      select id, channel, title_ar, body_ar, link, target_platforms,
             target_min_build, target_max_build, scheduled_at, status,
             onesignal_id, recipients, error
      from notifications order by created_at desc
    `;
    return c.json({ notifications: rows.map(toNotification) });
  });

  app.post('/notifications', requireRole('owner', 'editor'), async (c) => {
    const body = await readJson(c);
    const channel = body.channel;
    if (channel !== 'stable' && channel !== 'beta') {
      return failure(c, 400, 'channel must be stable or beta; internal gets no notifications.');
    }
    const titleAr = typeof body.titleAr === 'string' ? body.titleAr.trim() : '';
    const bodyAr = typeof body.bodyAr === 'string' ? body.bodyAr.trim() : '';
    if (!titleAr || titleAr.length > 60) {
      return failure(c, 400, 'titleAr is required and must be at most 60 characters.');
    }
    if (!bodyAr || bodyAr.length > 180) {
      return failure(c, 400, 'bodyAr is required and must be at most 180 characters.');
    }

    const link = typeof body.link === 'string' && body.link.trim() ? body.link.trim() : null;
    if (link && !isAllowedLink(link)) {
      return failure(c, 400, `link must be one of the app's deep links (03 §12).`);
    }

    const platforms = Array.isArray(body.platforms)
      ? body.platforms.filter((value) => value === 'ios' || value === 'android')
      : [];
    const platformsValue = platforms.length > 0 ? platforms : ['ios', 'android'];

    const scheduledAt = body.scheduledAt ? parseDate(body.scheduledAt) : null;
    if (body.scheduledAt && !scheduledAt) return failure(c, 400, 'scheduledAt is invalid.');
    if (scheduledAt && scheduledAt <= now()) {
      return failure(c, 400, 'scheduledAt must be in the future.');
    }

    const [created] = await sql<{ id: string }[]>`
      insert into notifications
        (channel, title_ar, body_ar, link, target_platforms,
         target_min_build, target_max_build, scheduled_at, status, created_by)
      values (${channel}::channel, ${titleAr}, ${bodyAr}, ${link},
              ${platformsValue}::text[], ${intOrNull(body.minBuild)},
              ${intOrNull(body.maxBuild)},
              ${scheduledAt ? scheduledAt.toISOString() : null}::timestamptz,
              ${scheduledAt ? 'scheduled' : 'draft'}::notification_status,
              ${c.get('session').user.id})
      returning id
    `;

    await auditFor(c, sql, 'notification.create', created!.id, { channel });
    return c.json({
      id: created!.id,
      status: scheduledAt ? 'scheduled' : 'draft',
    }, 201);
  });

  /** A single device, by OneSignal subscription id, never stored (02 §5). */
  app.post('/notifications/:id/test', requireRole('owner', 'editor'), async (c) => {
    const found = await load(sql, c.req.param('id'));
    if (!found) return failure(c, 404, 'Unknown notification.');
    const body = await readJson(c);
    const subscriptionId =
      typeof body.subscriptionId === 'string' ? body.subscriptionId.trim() : '';
    if (!subscriptionId) return failure(c, 400, 'subscriptionId is required.');

    try {
      const result = await onesignal.send({
        channel: found.channel as SendChannel,
        title: found.title_ar,
        body: found.body_ar,
        link: found.link,
        platforms: found.target_platforms,
        includeSubscriptionIds: [subscriptionId],
      });
      return c.json({ onesignalId: result.id, recipients: result.recipients });
    } catch (error) {
      return failure(c, 502, error instanceof OneSignalError ? error.message : 'Send failed.');
    }
  });

  app.post('/notifications/:id/send', requireRole('owner', 'editor'), async (c) => {
    const found = await load(sql, c.req.param('id'));
    if (!found) return failure(c, 404, 'Unknown notification.');
    if (found.status === 'sent' || found.status === 'cancelled') {
      return failure(c, 409, `This notification is already ${found.status}.`);
    }
    // Owner for stable, editor for beta (02 §5).
    if (found.channel === 'stable' && c.get('session').user.role !== 'owner') {
      return failure(c, 403, 'Only an owner may send to stable.');
    }

    try {
      const result = await onesignal.send({
        channel: found.channel as SendChannel,
        title: found.title_ar,
        body: found.body_ar,
        link: found.link,
        platforms: found.target_platforms,
        minBuild: found.target_min_build,
        maxBuild: found.target_max_build,
        sendAfter: found.scheduled_at ? new Date(found.scheduled_at) : null,
      });
      await sql`
        update notifications
        set status = ${found.scheduled_at ? 'scheduled' : 'sent'}::notification_status,
            onesignal_id = ${result.id}, recipients = ${result.recipients},
            error = null, updated_at = now()
        where id = ${found.id}
      `;
      await auditFor(c, sql, 'notification.send', found.id, { channel: found.channel });
      return c.json({ status: found.scheduled_at ? 'scheduled' : 'sent', onesignalId: result.id });
    } catch (error) {
      const message = error instanceof OneSignalError ? error.message : String(error);
      await sql`
        update notifications
        set status = 'failed'::notification_status, error = ${message}, updated_at = now()
        where id = ${found.id}
      `;
      return failure(c, 502, message);
    }
  });

  app.post('/notifications/:id/cancel', requireRole('owner', 'editor'), async (c) => {
    const found = await load(sql, c.req.param('id'));
    if (!found) return failure(c, 404, 'Unknown notification.');
    if (found.status !== 'scheduled' || !found.scheduled_at) {
      return failure(c, 409, 'Only a scheduled notification can be cancelled.');
    }
    if (new Date(found.scheduled_at) <= now()) {
      return failure(c, 409, 'The scheduled time has passed.');
    }

    try {
      if (found.onesignal_id) {
        await onesignal.cancel(found.channel as SendChannel, found.onesignal_id);
      }
      await sql`
        update notifications
        set status = 'cancelled'::notification_status, updated_at = now()
        where id = ${found.id}
      `;
      await auditFor(c, sql, 'notification.cancel', found.id);
      return c.json({ status: 'cancelled' });
    } catch (error) {
      return failure(c, 502, error instanceof OneSignalError ? error.message : 'Cancel failed.');
    }
  });

  return app;
}

async function load(sql: Database, id: string): Promise<NotificationRow | null> {
  if (!/^[0-9a-f-]{36}$/i.test(id)) return null;
  const rows = await sql<NotificationRow[]>`
    select id, channel, title_ar, body_ar, link, target_platforms,
           target_min_build, target_max_build, scheduled_at, status,
           onesignal_id, recipients, error
    from notifications where id = ${id} limit 1
  `;
  return rows[0] ?? null;
}

function toNotification(row: NotificationRow) {
  return {
    id: row.id,
    channel: row.channel,
    titleAr: row.title_ar,
    bodyAr: row.body_ar,
    link: row.link,
    platforms: row.target_platforms,
    minBuild: row.target_min_build,
    maxBuild: row.target_max_build,
    scheduledAt: row.scheduled_at ? new Date(row.scheduled_at).toISOString() : null,
    status: row.status,
    onesignalId: row.onesignal_id,
    recipients: row.recipients,
    error: row.error,
  };
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

function failure(c: Context, status: 400 | 403 | 404 | 409 | 502, message: string) {
  const code = status === 404 ? 'not_found' : 'invalid_request';
  return c.json({ error: { code, message } }, status);
}

function intOrNull(value: unknown): number | null {
  return typeof value === 'number' && Number.isInteger(value) ? value : null;
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

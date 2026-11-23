import { Hono } from 'hono';

import type { Database } from '../../db/client.js';
import type { PackStorage } from '../../services/storage.js';
import type { OneSignal } from '../../services/onesignal.js';
import type { ManifestCache } from '../public.js';
import { SessionStore, type ActiveSession } from '../../services/sessions.js';
import { requireCsrf, requireSession } from '../../middleware/auth.js';
import { adminRoutes } from './admin.js';
import { authRoutes } from './auth.js';
import { notificationRoutes } from './notifications.js';
import { packRoutes } from './packs.js';

export interface AdminRouterOptions {
  db: Database;
  storage: PackStorage;
  onesignal: OneSignal;
  /** Cleared on publish so the next request rebuilds (02 §4). */
  manifestCache?: ManifestCache;
  secureCookies: boolean;
  now?: (() => Date) | undefined;
}

/**
 * Mounts `/admin/api` (02 §5): login is open, and every other route needs a
 * session, with the CSRF header on writes.
 */
export function adminRouter(
  options: AdminRouterOptions,
): Hono<{ Variables: { session: ActiveSession } }> {
  const app = new Hono<{ Variables: { session: ActiveSession } }>();
  const sessions = new SessionStore(options.db);

  app.route(
    '/',
    authRoutes({
      sql: options.db,
      sessions,
      secureCookies: options.secureCookies,
      now: options.now,
    }),
  );

  const protectedRoutes = new Hono<{ Variables: { session: ActiveSession } }>();
  protectedRoutes.use('*', requireSession(sessions));
  protectedRoutes.use('*', requireCsrf());

  protectedRoutes.get('/me', (c) => {
    const session = c.get('session');
    return c.json({
      user: { email: session.user.email, role: session.user.role },
      csrfToken: session.csrfToken,
    });
  });

  protectedRoutes.route(
    '/',
    packRoutes({
      sql: options.db,
      storage: options.storage,
      manifestCache: options.manifestCache,
    }),
  );
  protectedRoutes.route('/', adminRoutes({ sql: options.db }));
  protectedRoutes.route(
    '/',
    notificationRoutes({ sql: options.db, onesignal: options.onesignal, now: options.now }),
  );

  app.route('/', protectedRoutes);
  return app;
}

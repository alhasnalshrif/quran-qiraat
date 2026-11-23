import { Hono, type Context } from 'hono';
import { createDatabase } from '../../db/client.js';
import { SessionStore, type ActiveSession } from '../../services/sessions.js';
import { requireCsrf, requireSession, unauthorized } from '../../middleware/auth.js';
import { authRoutes } from './auth.js';

export interface AdminRouterOptions {
  db: ReturnType<typeof createDatabase>;
  secureCookies: boolean;
  now?: (() => Date) | undefined;
}

/**
 * Mounts `/admin/api` (02 §5): login is open, `/me` needs a session, and every
 * state-changing route needs the CSRF header as well.
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

  app.route('/', protectedRoutes);
  return app;
}

export { unauthorized, type Context };

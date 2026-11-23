import { z } from 'zod';

/**
 * Environment validation for the server (02 §2). The process refuses to start
 * when a required variable is missing or malformed, with one clear message.
 */
const base64 = z
  .string()
  .min(1)
  .refine(
    (value) => {
      if (!/^[A-Za-z0-9+/]+={0,2}$/.test(value)) return false;
      try {
        return Buffer.from(value, 'base64').toString('base64') === value;
      } catch {
        return false;
      }
    },
    { message: 'must be base64' },
  );

export const envSchema = z.object({
  DATABASE_URL: z
    .string()
    .refine((value) => /^postgres(ql)?:\/\/.+/.test(value), {
      message: 'must be a postgres:// or postgresql:// URL',
    }),
  PORT: z.coerce.number().int().positive().default(8787),
  PUBLIC_BASE_URL: z.string().url(),
  CDN_BASE_URL: z.string().url(),

  S3_ENDPOINT: z.string().url(),
  S3_REGION: z.string().min(1),
  S3_BUCKET: z.string().min(1),
  S3_ACCESS_KEY_ID: z.string().min(1),
  S3_SECRET_ACCESS_KEY: z.string().min(1),

  MANIFEST_SIGNING_KEY: base64,
  MANIFEST_KEY_ID: z.string().min(1),
  MANIFEST_TTL_DAYS: z.coerce.number().int().min(1).max(7).default(7),

  SESSION_SECRET: z.string().min(32, 'SESSION_SECRET must be at least 32 characters'),
  ADMIN_ORIGIN: z.string().url(),

  LOG_LEVEL: z.enum(['debug', 'info', 'warn', 'error']).default('info'),

  ONESIGNAL_APP_ID_STABLE: z.string().min(1),
  ONESIGNAL_APP_ID_BETA: z.string().min(1),
  ONESIGNAL_REST_API_KEY_STABLE: z.string().min(1),
  ONESIGNAL_REST_API_KEY_BETA: z.string().min(1),
});

export type Env = z.infer<typeof envSchema>;

/** Formats zod issues as one readable, line-per-variable message. */
export function formatEnvErrors(error: z.ZodError): string {
  const lines = error.issues.map((issue) => {
    const name = issue.path.join('.') || '(root)';
    return `  ${name}: ${issue.message}`;
  });
  return `Invalid environment configuration:\n${lines.join('\n')}`;
}

/**
 * Parses and validates the environment. Throws with a single readable message
 * listing every problem, so a missing variable stops start-up (02 §2).
 */
export function loadEnv(source: NodeJS.ProcessEnv = process.env): Env {
  const parsed = envSchema.safeParse(source);
  if (!parsed.success) {
    throw new Error(formatEnvErrors(parsed.error));
  }
  return parsed.data;
}

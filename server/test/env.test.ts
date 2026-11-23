import { describe, expect, it } from 'vitest';

import { envSchema, formatEnvErrors, loadEnv } from '../src/env.js';

const complete = {
  DATABASE_URL: 'postgres://quran:quran@localhost:5432/quran',
  PUBLIC_BASE_URL: 'https://api.example.com',
  CDN_BASE_URL: 'https://cdn.example.com',
  S3_ENDPOINT: 'https://s3.example.com',
  S3_REGION: 'us-east-1',
  S3_BUCKET: 'quran',
  S3_ACCESS_KEY_ID: 'key',
  S3_SECRET_ACCESS_KEY: 'secret',
  MANIFEST_SIGNING_KEY: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
  MANIFEST_KEY_ID: 'k1',
  SESSION_SECRET: 'a'.repeat(43),
  ADMIN_ORIGIN: 'https://api.example.com',
  ONESIGNAL_APP_ID_STABLE: '00000000-0000-0000-0000-000000000000',
  ONESIGNAL_APP_ID_BETA: '00000000-0000-0000-0000-000000000001',
  ONESIGNAL_REST_API_KEY_STABLE: 'test-stable-key',
  ONESIGNAL_REST_API_KEY_BETA: 'test-beta-key',
} as const;

describe('environment (S-03)', () => {
  it('accepts a complete environment and applies defaults', () => {
    const env = loadEnv(complete as NodeJS.ProcessEnv);
    expect(env.PORT).toBe(8787);
    expect(env.MANIFEST_TTL_DAYS).toBe(7);
    expect(env.LOG_LEVEL).toBe('info');
  });

  it('stops start-up when a required variable is missing', () => {
    const { DATABASE_URL: _removed, ...missing } = complete;
    expect(() => loadEnv(missing as NodeJS.ProcessEnv)).toThrow(/DATABASE_URL/);
  });

  it('names every missing variable in one message', () => {
    expect(() => loadEnv({})).toThrow(/Invalid environment configuration/);
    try {
      loadEnv({});
    } catch (error) {
      const message = (error as Error).message;
      expect(message).toContain('DATABASE_URL');
      expect(message).toContain('MANIFEST_SIGNING_KEY');
      expect(message).toContain('ONESIGNAL_REST_API_KEY_BETA');
    }
  });

  it('rejects a short SESSION_SECRET', () => {
    expect(() =>
      loadEnv({ ...complete, SESSION_SECRET: 'short' } as NodeJS.ProcessEnv),
    ).toThrow(/SESSION_SECRET must be at least 32 characters/);
  });

  it('rejects a TTL above the 7-day maximum', () => {
    const parsed = envSchema.safeParse({ ...complete, MANIFEST_TTL_DAYS: '8' });
    expect(parsed.success).toBe(false);
  });

  it('rejects a non-base64 signing key', () => {
    const parsed = envSchema.safeParse({
      ...complete,
      MANIFEST_SIGNING_KEY: '***not base64***',
    });
    expect(parsed.success).toBe(false);
  });

  it('formats one line per problem', () => {
    const parsed = envSchema.safeParse({ ...complete, PORT: 'abc' });
    expect(parsed.success).toBe(false);
    if (!parsed.success) {
      const message = formatEnvErrors(parsed.error);
      expect(message.split('\n')[0]).toBe('Invalid environment configuration:');
      expect(message).toContain('PORT');
    }
  });

  it('a DATABASE_URL must look like postgres', () => {
    expect(
      envSchema.safeParse({ ...complete, DATABASE_URL: 'mysql://x' }).success,
    ).toBe(false);
    expect(
      envSchema.safeParse({ ...complete, DATABASE_URL: 'postgresql://u:p@h:5432/d' })
        .success,
    ).toBe(true);
  });
});

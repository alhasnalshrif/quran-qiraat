import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

import { describe, expect, it } from 'vitest';

import { manifestEnvelope, manifestPayload } from '../src/manifest.js';

const fixtures = resolve(import.meta.dirname, '../fixtures');

function fixture(name: string): unknown {
  return JSON.parse(readFileSync(resolve(fixtures, name), 'utf8'));
}

describe('manifest schema (S-02)', () => {
  it('accepts the 01 §2.2 example payload', () => {
    const parsed = manifestPayload.safeParse(fixture('manifest-payload.json'));
    expect(parsed.success, parsed.success ? '' : parsed.error.message).toBe(true);
  });

  it('accepts the signed envelope', () => {
    const parsed = manifestEnvelope.safeParse(fixture('manifest-envelope.json'));
    expect(parsed.success, parsed.success ? '' : parsed.error.message).toBe(true);
  });

  it('rejects a payload with the wrong protocol version', () => {
    const payload = fixture('manifest-payload.json') as Record<string, unknown>;
    expect(manifestPayload.safeParse({ ...payload, protocol: 2 }).success).toBe(false);
  });

  it('rejects a pack file path that escapes the pack', () => {
    const payload = fixture('manifest-payload.json') as {
      packs: { files: { path: string }[] }[];
    };
    payload.packs[0]!.files[0]!.path = '../secrets.json';
    expect(manifestPayload.safeParse(payload).success).toBe(false);
  });

  it('rejects a non-hex sha256', () => {
    const payload = fixture('manifest-payload.json') as {
      packs: { files: { sha256: string }[] }[];
    };
    payload.packs[0]!.files[0]!.sha256 = 'not-a-hash';
    expect(manifestPayload.safeParse(payload).success).toBe(false);
  });

  it('requires Arabic in localized text', () => {
    const payload = fixture('manifest-payload.json') as {
      app: { message: Record<string, string> };
    };
    payload.app.message = { en: 'Update available' };
    expect(manifestPayload.safeParse(payload).success).toBe(false);
  });

  it('rejects a non-URL store link', () => {
    const payload = fixture('manifest-payload.json') as { app: { storeUrl: string } };
    payload.app.storeUrl = 'not a url';
    expect(manifestPayload.safeParse(payload).success).toBe(false);
  });
});

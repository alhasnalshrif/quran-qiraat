import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

import { describe, expect, it } from 'vitest';

import {
  configEntry,
  configKeyNames,
  configMap,
  defaultConfigValue,
  isConfigKey,
} from '../src/config-keys.js';

const repoRoot = resolve(import.meta.dirname, '../../..');

function asset(path: string): unknown {
  return JSON.parse(readFileSync(resolve(repoRoot, path), 'utf8'));
}

describe('config keys (S-02)', () => {
  it('lists exactly the approved keys from 01 §4', () => {
    expect(configKeyNames).toEqual([
      'updates.checkIntervalHours',
      'updates.wifiOnlyDefault',
      'features.audio',
      'features.announcements',
      'audio.reciters',
    ]);
  });

  it('accepts a valid int in range and rejects out-of-range values', () => {
    expect(configEntry.safeParse({ key: 'updates.checkIntervalHours', value: 6 }).success).toBe(
      true,
    );
    expect(configEntry.safeParse({ key: 'updates.checkIntervalHours', value: 0 }).success).toBe(
      false,
    );
    expect(configEntry.safeParse({ key: 'updates.checkIntervalHours', value: 169 }).success).toBe(
      false,
    );
    expect(configEntry.safeParse({ key: 'updates.checkIntervalHours', value: 6.5 }).success).toBe(
      false,
    );
  });

  it('enforces each key type', () => {
    expect(configEntry.safeParse({ key: 'features.audio', value: true }).success).toBe(true);
    expect(configEntry.safeParse({ key: 'features.audio', value: 'yes' }).success).toBe(false);
    expect(configEntry.safeParse({ key: 'audio.reciters', value: [] }).success).toBe(true);
    expect(configEntry.safeParse({ key: 'audio.reciters', value: {} }).success).toBe(false);
  });

  it('rejects an unknown key', () => {
    expect(configEntry.safeParse({ key: 'features.unknown', value: true }).success).toBe(false);
    expect(isConfigKey('features.unknown')).toBe(false);
  });

  it('drops unknown and invalid keys from a manifest config object', () => {
    const parsed = configMap.parse({
      'updates.checkIntervalHours': 12,
      'features.audio': 'not-a-bool',
      'unknown.key': 1,
    });
    expect(parsed).toEqual([{ key: 'updates.checkIntervalHours', value: 12 }]);
  });

  it('exposes the documented defaults', () => {
    expect(defaultConfigValue('updates.checkIntervalHours')).toBe(6);
    expect(defaultConfigValue('updates.wifiOnlyDefault')).toBe(true);
    expect(defaultConfigValue('features.announcements')).toBe(true);
  });
});

describe('bundled config values (S-02)', () => {
  it('does not ship a config file with unapproved keys', () => {
    let bundled: unknown;
    try {
      bundled = asset('assets/remote_config_bundled.json');
    } catch {
      return; // No bundled config file yet; nothing to check.
    }
    for (const key of Object.keys(bundled as Record<string, unknown>)) {
      expect(isConfigKey(key), `unapproved key ${key}`).toBe(true);
    }
  });
});

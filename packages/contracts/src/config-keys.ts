import { z } from 'zod';

/**
 * Approved remote config keys with their types (01 §4). Adding a key starts
 * here, then in the app defaults and server validation.
 */
export const configKeys = {
  'updates.checkIntervalHours': {
    type: 'int',
    default: 6,
    min: 1,
    max: 168,
  },
  'updates.wifiOnlyDefault': {
    type: 'bool',
    default: true,
  },
  'features.audio': {
    type: 'bool',
    default: true,
  },
  'features.announcements': {
    type: 'bool',
    default: true,
  },
  'audio.reciters': {
    type: 'list',
    default: [],
  },
} as const;

export type ConfigKey = keyof typeof configKeys;

export const configKeyNames = Object.keys(configKeys) as ConfigKey[];

const keySchema = z.enum(configKeyNames as [ConfigKey, ...ConfigKey[]]);

/** Validates one key/value pair against the approved key's type. */
export const configEntry = z
  .object({
    key: keySchema,
    value: z.unknown(),
  })
  .superRefine((entry, ctx) => {
    const spec = configKeys[entry.key];
    const valid = (() => {
      switch (spec.type) {
        case 'int':
          return (
            typeof entry.value === 'number' &&
            Number.isInteger(entry.value) &&
            entry.value >= spec.min &&
            entry.value <= spec.max
          );
        case 'bool':
          return typeof entry.value === 'boolean';
        case 'list':
          return Array.isArray(entry.value);
      }
    })();
    if (!valid) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        path: ['value'],
        message: `value does not match the type of ${entry.key}`,
      });
    }
  });

export type ConfigEntry = z.infer<typeof configEntry>;

/** Validates a `config` object from a manifest, ignoring unknown keys (01 §2.2). */
export const configMap = z.record(z.string(), z.unknown()).transform((raw) =>
  Object.entries(raw).flatMap(([key, value]) => {
    if (!(key in configKeys)) return [];
    const parsed = configEntry.safeParse({ key, value });
    return parsed.success ? [parsed.data] : [];
  }),
);

export function isConfigKey(key: string): key is ConfigKey {
  return key in configKeys;
}

export function defaultConfigValue(key: ConfigKey): unknown {
  return configKeys[key].default;
}

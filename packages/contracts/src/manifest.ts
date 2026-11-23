import { z } from 'zod';

/** Localised user-facing text. Arabic is mandatory (01 §2.2). */
export const localizedText = z.object({
  ar: z.string().min(1),
});

export type LocalizedText = z.infer<typeof localizedText>;

/** A pack version entry inside a signed manifest (01 §2.2). */
export const manifestPackFile = z.object({
  path: z.string().min(1).refine((value) => !value.includes('..') && !value.startsWith('/'), {
    message: 'path must be relative and cannot contain ".."',
  }),
  url: z.string().url(),
  sha256: z.string().regex(/^[0-9a-f]{64}$/, 'sha256 must be 64 lowercase hex characters'),
  size: z.number().int().nonnegative(),
});

export type ManifestPackFile = z.infer<typeof manifestPackFile>;

export const manifestPack = z.object({
  packId: z.string().regex(/^[a-z0-9-]+$/, 'packId uses lowercase letters, digits and dashes'),
  version: z.number().int().positive(),
  format: z.string().regex(/^[a-z0-9-]+@\d+$/, 'format must be name@version'),
  source: z
    .object({
      name: z.string().min(1),
      revision: z.string().min(1),
    })
    .optional(),
  notes: localizedText.optional(),
  files: z.array(manifestPackFile).min(1),
});

export type ManifestPack = z.infer<typeof manifestPack>;

export const manifestApp = z.object({
  latestBuild: z.number().int().positive(),
  minSupportedBuild: z.number().int().positive(),
  storeUrl: z.string().url(),
  message: localizedText.optional(),
});

export type ManifestApp = z.infer<typeof manifestApp>;

export const manifestAnnouncement = z.object({
  id: z.string().min(1),
  title: localizedText,
  body: localizedText,
  url: z.string().url().nullable(),
  startsAt: z.string().datetime(),
  endsAt: z.string().datetime(),
  priority: z.enum(['normal', 'high']),
});

export type ManifestAnnouncement = z.infer<typeof manifestAnnouncement>;

/** The decoded manifest payload (01 §2.2). */
export const manifestPayload = z.object({
  protocol: z.literal(1),
  issuedAt: z.string().datetime(),
  expiresAt: z.string().datetime(),
  channel: z.enum(['stable', 'beta', 'internal']),
  app: manifestApp,
  packs: z.array(manifestPack),
  revoked: z.array(
    z.object({
      packId: z.string().regex(/^[a-z0-9-]+$/),
      version: z.number().int().positive(),
    }),
  ),
  config: z.record(z.string(), z.unknown()),
  announcements: z.array(manifestAnnouncement),
});

export type ManifestPayload = z.infer<typeof manifestPayload>;

/** The signed envelope the server returns (01 §2.2). */
export const manifestEnvelope = z.object({
  keyId: z.string().min(1),
  payload: z.string().min(1),
  signature: z.string().min(1),
});

export type ManifestEnvelope = z.infer<typeof manifestEnvelope>;

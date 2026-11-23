import type { Database } from '../db/client.js';

export type PackVersionStatus = 'draft' | 'validated' | 'published' | 'revoked';

export type Channel = 'stable' | 'beta' | 'internal';

/**
 * Allowed status transitions (02 §3): draft→validated→published→revoked, plus
 * validated→revoked. Nothing else moves.
 */
const transitions: Record<PackVersionStatus, PackVersionStatus[]> = {
  draft: ['validated'],
  validated: ['published', 'revoked'],
  published: ['revoked'],
  revoked: [],
};

export function canTransition(
  from: PackVersionStatus,
  to: PackVersionStatus,
): boolean {
  return transitions[from].includes(to);
}

export class TransitionError extends Error {
  constructor(from: PackVersionStatus, to: PackVersionStatus) {
    super(`Cannot move a pack version from ${from} to ${to}.`);
  }
}

/** Appends an entry to `audit_log` (02 §5: writes are audited). */
export async function audit(
  sql: Database,
  entry: {
    userId: string | null;
    action: string;
    target: string;
    details?: unknown;
  },
): Promise<void> {
  await sql`
    insert into audit_log (user_id, action, target, details)
    values (${entry.userId}, ${entry.action}, ${entry.target}, ${
      entry.details === undefined ? null : JSON.stringify(entry.details)
    }::jsonb)
  `;
}

/** Pack ids from the protocol, the only ones an admin may create (01 §1.1). */
export const allowedPackIds = [
  'editions-manifest',
  'hafs-text',
  'riwayah-shubah-text',
  'riwayah-qalun-text',
  'hafs-layout-1405',
  'mapping-hafs-qalun',
  'qiraat-farsh',
  'published-differences',
  'navigation-hizbs',
] as const;

export type PackId = (typeof allowedPackIds)[number];

export function isAllowedPackId(value: string): value is PackId {
  return (allowedPackIds as readonly string[]).includes(value);
}

/** A pack file path must stay inside the pack (02 §3). */
export function isSafePackPath(path: string): boolean {
  return (
    path.length > 0 &&
    !path.startsWith('/') &&
    !path.includes('..') &&
    !path.includes('\\')
  );
}

/** `packs/<packId>/<version>/<path>` (02 §3). */
export function storageKey(packId: string, version: number, path: string): string {
  return `packs/${packId}/${version}/${path}`;
}

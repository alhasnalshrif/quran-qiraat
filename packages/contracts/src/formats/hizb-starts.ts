import { fail, isRecord, ok, type Json, type ValidationResult } from './common.js';

export interface HizbStartsContext {
  /** Hafs ayah keys (`surah:ayah`) from the hafs-text pack. */
  hafsAyahKeys?: ReadonlySet<string>;
}

/**
 * `hizb-starts@1` (01 §1.2): same checks as `QuranNavigationIndex.hizbs` —
 * exactly 60 distinct hizb starts, each an ayah that exists in Hafs.
 */
export function validateHizbStarts(
  document: Json,
  context: HizbStartsContext = {},
): ValidationResult {
  if (!isRecord(document)) return fail('expected a hizb-starts object');
  const starts = document['hizb_starts'];
  if (!Array.isArray(starts)) return fail('hizb_starts must be an array');

  const errors: string[] = [];
  if (starts.length !== 60) {
    errors.push(`expected 60 hizb starts, found ${starts.length}`);
  }
  const seen = new Set<string>();
  for (const raw of starts) {
    if (typeof raw !== 'string' || !/^\d+:\d+$/.test(raw)) {
      errors.push(`invalid hizb start ${String(raw)}`);
      continue;
    }
    if (seen.has(raw)) errors.push(`duplicate hizb start ${raw}`);
    seen.add(raw);
    if (context.hafsAyahKeys && !context.hafsAyahKeys.has(raw)) {
      errors.push(`hizb start ${raw} is missing from Hafs`);
    }
  }

  return errors.length === 0 ? ok : fail(...errors);
}

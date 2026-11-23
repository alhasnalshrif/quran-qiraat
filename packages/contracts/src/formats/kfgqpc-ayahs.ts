import { fail, isRecord, ok, type Json, type ValidationResult } from './common.js';

/**
 * `kfgqpc-ayahs@1` (01 §1.2): an array of ayahs; each has sura_no 1–114,
 * aya_no ≥ 1 and a non-empty aya_text; no duplicated (surah, ayah); the count
 * must match totalAyahs from editions-manifest when one is supplied.
 */
export function validateKfgqpcAyahs(
  document: Json,
  options: { totalAyahs?: number } = {},
): ValidationResult {
  if (!Array.isArray(document)) return fail('expected an array of ayahs');
  if (document.length === 0) return fail('ayah list is empty');

  const errors: string[] = [];
  const seen = new Set<string>();

  document.forEach((raw, index) => {
    if (!isRecord(raw)) {
      errors.push(`ayah ${index + 1} is not an object`);
      return;
    }
    const sura = raw['sura_no'];
    const aya = raw['aya_no'];
    const text = raw['aya_text'];

    if (typeof sura !== 'number' || !Number.isInteger(sura) || sura < 1 || sura > 114) {
      errors.push(`ayah ${index + 1} has an invalid sura_no`);
    }
    if (typeof aya !== 'number' || !Number.isInteger(aya) || aya < 1) {
      errors.push(`ayah ${index + 1} has an invalid aya_no`);
    }
    if (typeof text !== 'string' || text.trim().length === 0) {
      errors.push(`ayah ${index + 1} has an empty aya_text`);
    }
    if (typeof sura === 'number' && typeof aya === 'number') {
      const key = `${sura}:${aya}`;
      if (seen.has(key)) errors.push(`duplicate ayah ${key}`);
      seen.add(key);
    }
  });

  if (
    options.totalAyahs !== undefined &&
    document.length !== options.totalAyahs
  ) {
    errors.push(
      `expected ${options.totalAyahs} ayahs, found ${document.length}`,
    );
  }

  return errors.length === 0 ? ok : fail(...errors);
}

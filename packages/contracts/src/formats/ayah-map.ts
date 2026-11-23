import { fail, isRecord, ok, type Json, type ValidationResult } from './common.js';

const surahCount = 114;

/**
 * `ayah-map@1` (01 §1.2): same checks the app runs today — version 0.1.0,
 * kufi source, qalun target, and 114 surahs whose ayah entries point at
 * existing target ayahs.
 */
export function validateAyahMap(document: Json): ValidationResult {
  if (!isRecord(document)) return fail('expected an ayah-map object');
  if (document['_version'] !== '0.1.0') return fail('unsupported ayah map version');
  if (document['_source'] !== 'kufi') return fail('unsupported ayah map source');
  if (document['_rawi'] !== 'qalun') return fail('unsupported ayah map rawi');

  const surahs = document['surahs'];
  if (!isRecord(surahs)) return fail('surahs must be an object');

  const errors: string[] = [];
  const keys = Object.keys(surahs);
  if (keys.length !== surahCount) {
    errors.push(`expected ${surahCount} surahs, found ${keys.length}`);
  }

  for (const [surahKey, surah] of Object.entries(surahs)) {
    const surahNumber = Number(surahKey);
    if (!Number.isInteger(surahNumber) || surahNumber < 1 || surahNumber > surahCount) {
      errors.push(`invalid surah number ${surahKey}`);
      continue;
    }
    if (!isRecord(surah)) {
      errors.push(`surah ${surahKey} is not an object`);
      continue;
    }
    const ayahs = surah['ayahs'];
    if (!isRecord(ayahs)) {
      errors.push(`surah ${surahKey} has no ayahs`);
      continue;
    }
    if (Object.keys(ayahs).length === 0) {
      errors.push(`surah ${surahKey} has no ayah entries`);
    }
    for (const [ayahKey, mapping] of Object.entries(ayahs)) {
      const ayahNumber = Number(ayahKey);
      if (!Number.isInteger(ayahNumber) || ayahNumber < 1) {
        errors.push(`surah ${surahKey} has an invalid ayah number ${ayahKey}`);
        continue;
      }
      if (!isRecord(mapping)) {
        errors.push(`surah ${surahKey} ayah ${ayahKey} is not an object`);
        continue;
      }
      const targets = mapping['splits_into'];
      if (targets !== undefined && targets !== null) {
        if (
          !Array.isArray(targets) ||
          targets.length === 0 ||
          targets.some((value) => typeof value !== 'number' || value < 1)
        ) {
          errors.push(`surah ${surahKey} ayah ${ayahKey} has invalid splits_into`);
        }
        continue;
      }
      const target = mapping['target_ayah'];
      if (typeof target !== 'number' || target < 1) {
        errors.push(`surah ${surahKey} ayah ${ayahKey} has no valid target_ayah`);
      }
    }
  }

  return errors.length === 0 ? ok : fail(...errors);
}

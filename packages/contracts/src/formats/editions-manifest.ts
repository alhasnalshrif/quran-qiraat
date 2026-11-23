import { fail, isRecord, ok, type Json, type ValidationResult } from './common.js';

/**
 * `editions-manifest@1` (01 §1.2): same checks as `QuranRepository.load` —
 * schema 1.0.0 with the expected editions and their ayah counts.
 */
export function validateEditionsManifest(document: Json): ValidationResult {
  if (!isRecord(document)) return fail('expected an editions-manifest object');
  if (document['schema_version'] !== '1.0.0') {
    return fail('unsupported editions manifest schema');
  }
  const editions = document['editions'];
  if (!Array.isArray(editions) || editions.length === 0) {
    return fail('editions must be a non-empty array');
  }

  const errors: string[] = [];
  const ids = new Set<string>();

  editions.forEach((edition, index) => {
    if (!isRecord(edition)) {
      errors.push(`edition ${index + 1} is not an object`);
      return;
    }
    const id = edition['id'];
    if (typeof id !== 'string' || id.trim().length === 0) {
      errors.push(`edition ${index + 1} has no id`);
    } else if (ids.has(id)) {
      errors.push(`duplicate edition id ${id}`);
    } else {
      ids.add(id);
    }
    if (typeof edition['reading'] !== 'string' || edition['reading'].trim().length === 0) {
      errors.push(`edition ${String(id)} has no reading`);
    }
    if (typeof edition['name_ar'] !== 'string' || edition['name_ar'].trim().length === 0) {
      errors.push(`edition ${String(id)} has no name_ar`);
    }
    const totalAyahs = edition['total_ayahs'];
    if (typeof totalAyahs !== 'number' || !Number.isInteger(totalAyahs) || totalAyahs < 1) {
      errors.push(`edition ${String(id)} has an invalid total_ayahs`);
    }
  });

  return errors.length === 0 ? ok : fail(...errors);
}

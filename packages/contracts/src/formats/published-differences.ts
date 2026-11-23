import { fail, isRecord, ok, type Json, type ValidationResult } from './common.js';

/**
 * `published-differences@1` (01 §1.2): same rules as the app's
 * `parsePublishedDifferences` — schema 1.0.0, unique ids, and every record
 * marked as reviewed before it can ship in the bundle.
 */
export function validatePublishedDifferences(document: Json): ValidationResult {
  if (!isRecord(document)) return fail('expected a published-differences object');
  if (document['schema_version'] !== '1.0.0') {
    return fail('unsupported published differences schema');
  }
  const records = document['records'];
  if (!Array.isArray(records)) return fail('records must be an array');
  if (records.length === 0) return ok;

  const errors: string[] = [];
  const ids = new Set<string>();

  records.forEach((record, index) => {
    if (!isRecord(record)) {
      errors.push(`record ${index + 1} is not an object`);
      return;
    }
    const id = record['id'];
    if (typeof id !== 'string' || id.trim().length === 0) {
      errors.push(`record ${index + 1} has no id`);
    } else if (ids.has(id)) {
      errors.push(`duplicate record id ${id}`);
    } else {
      ids.add(id);
    }

    const status = record['review_status'] ?? record['status'] ?? record['is_published'];
    const published =
      status === 'published' || status === 'approved' || status === 'reviewed' || status === true;
    if (!published) {
      errors.push(`record ${String(id)} is not reviewed for publishing`);
    }

    for (const field of ['base_span', 'target_span'] as const) {
      const span = record[field];
      if (!isRecord(span)) {
        errors.push(`record ${String(id)} has no ${field}`);
        continue;
      }
      for (const key of ['reading', 'ayah', 'start_word', 'end_word', 'text'] as const) {
        if (span[key] === undefined) {
          errors.push(`record ${String(id)} ${field} is missing ${key}`);
        }
      }
      const start = span['start_word'];
      const end = span['end_word'];
      if (typeof start !== 'number' || typeof end !== 'number' || start < 1 || end < start) {
        errors.push(`record ${String(id)} ${field} has an invalid word span`);
      }
      if (typeof span['text'] !== 'string' || span['text'].trim().length === 0) {
        errors.push(`record ${String(id)} ${field} has empty text`);
      }
    }
  });

  return errors.length === 0 ? ok : fail(...errors);
}

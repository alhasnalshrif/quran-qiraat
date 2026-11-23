import { fail, isRecord, ok, type Json, type ValidationResult } from './common.js';

export interface QiraatVariantsContext {
  /** Hafs ayah keys (`surah:ayah`) from the hafs-text pack. */
  hafsAyahKeys?: ReadonlySet<string>;
  /** Hafs layout word locations (`surah:ayah:word`) from the layout pack. */
  hafsWordLocations?: ReadonlySet<string>;
}

/**
 * `qiraat-variants@1` (01 §1.2): ten readers, twenty transmitters, every
 * `junctures[].segments[].ayah` exists in Hafs, and `words` is either null or
 * `[start, end]` with word numbers that exist in the layout.
 */
export function validateQiraatVariants(
  document: Json,
  context: QiraatVariantsContext = {},
): ValidationResult {
  if (!isRecord(document)) return fail('expected a variants object');

  const errors: string[] = [];

  const readers = document['readers'];
  if (!isRecord(readers)) {
    errors.push('readers must be an object');
  } else if (Object.keys(readers).length !== 10) {
    errors.push(`expected 10 readers, found ${Object.keys(readers).length}`);
  } else {
    for (const [id, reader] of Object.entries(readers)) {
      if (!isRecord(reader)) {
        errors.push(`reader ${id} is not an object`);
        continue;
      }
      if (typeof reader['name'] !== 'string' || reader['name'].trim().length === 0) {
        errors.push(`reader ${id} has no name`);
      }
      if (typeof reader['position'] !== 'number' || !Number.isInteger(reader['position'])) {
        errors.push(`reader ${id} has an invalid position`);
      }
    }
  }

  const transmitters = document['transmitters'];
  const readerIds = new Set(
    isRecord(readers) ? Object.keys(readers).map(Number) : [],
  );
  if (!isRecord(transmitters)) {
    errors.push('transmitters must be an object');
  } else if (Object.keys(transmitters).length !== 20) {
    errors.push(`expected 20 transmitters, found ${Object.keys(transmitters).length}`);
  } else {
    for (const [id, transmitter] of Object.entries(transmitters)) {
      if (!isRecord(transmitter)) {
        errors.push(`transmitter ${id} is not an object`);
        continue;
      }
      if (typeof transmitter['name'] !== 'string' || transmitter['name'].trim().length === 0) {
        errors.push(`transmitter ${id} has no name`);
      }
      if (typeof transmitter['riwayah'] !== 'string' || transmitter['riwayah'].trim().length === 0) {
        errors.push(`transmitter ${id} has no riwayah`);
      }
      const readerId = transmitter['reader'];
      if (typeof readerId !== 'number' || !readerIds.has(readerId)) {
        errors.push(`transmitter ${id} references an unknown reader`);
      }
    }
  }

  const junctures = document['junctures'];
  if (!Array.isArray(junctures)) {
    errors.push('junctures must be an array');
    return fail(...errors);
  }
  if (junctures.length === 0) errors.push('junctures is empty');

  junctures.forEach((juncture, index) => {
    if (!isRecord(juncture)) {
      errors.push(`juncture ${index + 1} is not an object`);
      return;
    }
    const segments = juncture['segments'];
    if (!Array.isArray(segments) || segments.length === 0) {
      errors.push(`juncture ${index + 1} has no segments`);
      return;
    }
    segments.forEach((segment, segmentIndex) => {
      if (!isRecord(segment)) {
        errors.push(`juncture ${index + 1} segment ${segmentIndex + 1} is not an object`);
        return;
      }
      const ayah = segment['ayah'];
      if (typeof ayah !== 'string' || !/^\d+:\d+$/.test(ayah)) {
        errors.push(`juncture ${index + 1} segment ${segmentIndex + 1} has an invalid ayah`);
        return;
      }
      if (context.hafsAyahKeys && !context.hafsAyahKeys.has(ayah)) {
        errors.push(`juncture ${index + 1} segment ${segmentIndex + 1} references a missing Hafs ayah ${ayah}`);
      }

      const words = segment['words'];
      if (words === null || words === undefined) return;
      if (
        !Array.isArray(words) ||
        words.length !== 2 ||
        !Number.isInteger(words[0]) ||
        !Number.isInteger(words[1]) ||
        words[0] < 1 ||
        words[1] < words[0]
      ) {
        errors.push(`juncture ${index + 1} segment ${segmentIndex + 1} has invalid words`);
        return;
      }
      if (context.hafsWordLocations) {
        for (let word = words[0]; word <= words[1]; word++) {
          if (!context.hafsWordLocations.has(`${ayah}:${word}`)) {
            errors.push(
              `juncture ${index + 1} segment ${segmentIndex + 1} references a missing layout word ${ayah}:${word}`,
            );
          }
        }
      }
    });

    const readings = juncture['readings'];
    if (!Array.isArray(readings) || readings.length === 0) {
      errors.push(`juncture ${index + 1} has no readings`);
      return;
    }
    readings.forEach((reading, readingIndex) => {
      if (!isRecord(reading)) {
        errors.push(`juncture ${index + 1} reading ${readingIndex + 1} is not an object`);
        return;
      }
      if (typeof reading['text'] !== 'string' || reading['text'].trim().length === 0) {
        errors.push(`juncture ${index + 1} reading ${readingIndex + 1} has no text`);
      }
      for (const field of ['readers', 'transmitters'] as const) {
        const list = reading[field];
        if (!Array.isArray(list) || list.some((id) => typeof id !== 'number')) {
          errors.push(`juncture ${index + 1} reading ${readingIndex + 1} has an invalid ${field} list`);
        }
      }
    });
  });

  return errors.length === 0 ? ok : fail(...errors);
}

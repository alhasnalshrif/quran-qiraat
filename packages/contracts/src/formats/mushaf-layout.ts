import { fail, isRecord, ok, type Json, type ValidationResult } from './common.js';

const pageCount = 604;
const validLineTypes = new Set(['surah-header', 'basmala', 'text']);
const wordLocation = /^\d+:\d+:\d+$/;
const surahCount = 114;

/**
 * `mushaf-layout@1` (01 §1.2): 604 pages, every word location is `s:a:w`,
 * plus the same checks as `tool/import_mushaf_layout.mjs --check`.
 */
export function validateMushafLayout(document: Json): ValidationResult {
  if (!isRecord(document)) return fail('expected a layout object');
  if (document['schemaVersion'] !== '1.0.0') {
    return fail('unsupported layout schemaVersion');
  }
  const pages = document['pages'];
  if (!Array.isArray(pages)) return fail('pages must be an array');
  if (pages.length !== pageCount) {
    return fail(`expected ${pageCount} pages, found ${pages.length}`);
  }

  const errors: string[] = [];

  pages.forEach((page, index) => {
    const expectedNumber = index + 1;
    if (!isRecord(page)) {
      errors.push(`page ${expectedNumber} is not an object`);
      return;
    }
    if (page['number'] !== expectedNumber) {
      errors.push(`expected page ${expectedNumber}, found ${String(page['number'])}`);
    }
    const lines = page['lines'];
    if (!Array.isArray(lines) || lines.length === 0) {
      errors.push(`page ${expectedNumber} has no lines`);
      return;
    }

    let previousLine = 0;
    const seenLines = new Set<number>();
    lines.forEach((line, lineIndex) => {
      if (!isRecord(line)) {
        errors.push(`page ${expectedNumber}, entry ${lineIndex + 1} is invalid`);
        return;
      }
      const number = line['number'];
      if (typeof number !== 'number' || !Number.isInteger(number) || number <= previousLine) {
        errors.push(`page ${expectedNumber}, entry ${lineIndex + 1} has a non-monotonic line number`);
      } else {
        previousLine = number;
        if (seenLines.has(number)) errors.push(`page ${expectedNumber} has duplicate line ${number}`);
        seenLines.add(number);
      }

      const type = line['type'];
      if (typeof type !== 'string' || !validLineTypes.has(type)) {
        errors.push(`page ${expectedNumber}, line ${String(number)} has an invalid type`);
        return;
      }
      if (type === 'text' && (typeof line['text'] !== 'string' || line['text'].trim().length === 0)) {
        errors.push(`page ${expectedNumber}, text line ${String(number)} has empty text`);
      }
      if (
        type !== 'text' &&
        typeof line['text'] !== 'string' &&
        typeof line['qpcV1'] !== 'string' &&
        typeof line['qpcV2'] !== 'string'
      ) {
        errors.push(`page ${expectedNumber}, structural line ${String(number)} has no display data`);
      }

      if (type === 'text') {
        const words = line['words'];
        if (!Array.isArray(words) || words.length === 0) {
          errors.push(`page ${expectedNumber}, text line ${String(number)} has no words`);
          return;
        }
        words.forEach((word, wordIndex) => {
          if (!isRecord(word)) {
            errors.push(
              `page ${expectedNumber}, line ${String(number)}, word ${wordIndex + 1} is invalid`,
            );
            return;
          }
          const location = word['location'];
          const wordText = word['text'] ?? word['word'];
          if (typeof location !== 'string' || !wordLocation.test(location)) {
            errors.push(
              `page ${expectedNumber}, line ${String(number)}, word ${wordIndex + 1} has an invalid location`,
            );
          } else {
            const [surah] = location.split(':').map(Number);
            if (surah === undefined || surah < 1 || surah > surahCount) {
              errors.push(
                `page ${expectedNumber}, line ${String(number)}, word ${wordIndex + 1} has an invalid surah`,
              );
            }
          }
          if (typeof wordText !== 'string' || wordText.trim().length === 0) {
            errors.push(
              `page ${expectedNumber}, line ${String(number)}, word ${wordIndex + 1} has empty text`,
            );
          }
        });
      }
    });
  });

  return errors.length === 0 ? ok : fail(...errors);
}

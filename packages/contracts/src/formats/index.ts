import { validateAyahMap } from './ayah-map.js';
import type { Json, ValidationResult } from './common.js';
import { validateEditionsManifest } from './editions-manifest.js';
import { validateHizbStarts } from './hizb-starts.js';
import { validateKfgqpcAyahs } from './kfgqpc-ayahs.js';
import { validateMushafLayout } from './mushaf-layout.js';
import { validatePublishedDifferences } from './published-differences.js';
import { validateQiraatVariants } from './qiraat-variants.js';

export type FormatValidator = (document: Json) => ValidationResult;

/** Every format the app and server understand today (01 §1.2). */
export const formatValidators: Record<string, FormatValidator> = {
  'kfgqpc-ayahs@1': (document) => validateKfgqpcAyahs(document),
  'mushaf-layout@1': validateMushafLayout,
  'qiraat-variants@1': (document) => validateQiraatVariants(document),
  'published-differences@1': validatePublishedDifferences,
  'ayah-map@1': validateAyahMap,
  'hizb-starts@1': (document) => validateHizbStarts(document),
  'editions-manifest@1': validateEditionsManifest,
};

export function isKnownFormat(format: string): boolean {
  return format in formatValidators;
}

/** Runs the validator for [format]; unknown formats are rejected. */
export function validateFormat(format: string, document: Json): ValidationResult {
  const validator = formatValidators[format];
  if (!validator) {
    return { ok: false, errors: [`unknown format ${format}`] };
  }
  return validator(document);
}

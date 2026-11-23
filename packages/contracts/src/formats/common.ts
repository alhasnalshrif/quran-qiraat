/**
 * Validators for the pack formats in 01 §1.2. Each returns a list of problems;
 * an empty list means the document is valid. The server runs these on upload,
 * the app runs the Dart mirror after download and before activation.
 */

export interface ValidationResult {
  ok: boolean;
  errors: string[];
}

export const ok: ValidationResult = { ok: true, errors: [] };

export function fail(...errors: string[]): ValidationResult {
  return { ok: false, errors };
}

export type Json = unknown;

export function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

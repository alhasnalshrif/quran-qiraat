export * from './config-keys.js';
export * from './formats/index.js';
export * from './manifest.js';

export const PROTOCOL_VERSION = 1;

export const channels = ['stable', 'beta', 'internal'] as const;
export type Channel = (typeof channels)[number];

export const platforms = ['ios', 'android'] as const;
export type Platform = (typeof platforms)[number];

/** Pack ids from 01 §1.1, the only ones the protocol allows. */
export const packIds = [
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
export type PackId = (typeof packIds)[number];

export function isPackId(value: string): value is PackId {
  return (packIds as readonly string[]).includes(value);
}

/** Deep links a notification may carry, from 03 §12. */
export const allowedLinkPrefixes = [
  'quranqiraat://page/',
  'quranqiraat://ayah/',
  'quranqiraat://updates',
  'quranqiraat://announcement/',
] as const;

/** Whether a notification link is one of the app's deep links (03 §12). */
export function isAllowedLink(link: string): boolean {
  return allowedLinkPrefixes.some((prefix) => link.startsWith(prefix));
}

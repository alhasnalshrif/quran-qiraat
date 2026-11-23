import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

import { describe, expect, it } from 'vitest';

import { validateAyahMap } from '../src/formats/ayah-map.js';
import { validateEditionsManifest } from '../src/formats/editions-manifest.js';
import { validateHizbStarts } from '../src/formats/hizb-starts.js';
import { validateKfgqpcAyahs } from '../src/formats/kfgqpc-ayahs.js';
import { validateMushafLayout } from '../src/formats/mushaf-layout.js';
import { validatePublishedDifferences } from '../src/formats/published-differences.js';
import { validateQiraatVariants } from '../src/formats/qiraat-variants.js';

const repoRoot = resolve(import.meta.dirname, '../../..');

function asset<T = unknown>(path: string): T {
  return JSON.parse(readFileSync(resolve(repoRoot, path), 'utf8')) as T;
}

const hafs = asset<{ sura_no: number; aya_no: number }[]>('assets/quran_hafs.json');
const hafsAyahKeys = new Set(hafs.map((ayah) => `${ayah.sura_no}:${ayah.aya_no}`));
const layout = asset<{
  pages: { lines: { number: number; words?: { location: string }[] }[] }[];
}>('assets/mushaf/layout/hafs_madani_604.json');
const hafsWordLocations = new Set(
  layout.pages.flatMap((page) =>
    page.lines.flatMap((line) => (line.words ?? []).map((word) => word.location)),
  ),
);

describe('kfgqpc-ayahs@1 (S-02)', () => {
  it('accepts the bundled Hafs text with the manifest ayah count', () => {
    const result = validateKfgqpcAyahs(hafs, { totalAyahs: 6236 });
    expect(result.errors).toEqual([]);
    expect(result.ok).toBe(true);
  });

  it('accepts the bundled Qalun text with its own count', () => {
    const qalun = asset('assets/quran_qalun.json');
    expect(validateKfgqpcAyahs(qalun, { totalAyahs: 6214 }).ok).toBe(true);
  });

  it('rejects an empty ayah text', () => {
    const broken = structuredClone(hafs) as unknown as { aya_text: string }[];
    broken[0]!.aya_text = '   ';
    expect(validateKfgqpcAyahs(broken).ok).toBe(false);
  });

  it('rejects a duplicate ayah', () => {
    const broken = structuredClone(hafs) as unknown[];
    broken.push(structuredClone(hafs[0]));
    const result = validateKfgqpcAyahs(broken);
    expect(result.ok).toBe(false);
    expect(result.errors.join(' ')).toContain('duplicate ayah');
  });

  it('rejects a count that disagrees with totalAyahs', () => {
    expect(validateKfgqpcAyahs(hafs, { totalAyahs: 6000 }).ok).toBe(false);
  });

  it('rejects an out-of-range surah', () => {
    const broken = structuredClone(hafs) as { sura_no: number }[];
    broken[0]!.sura_no = 115;
    expect(validateKfgqpcAyahs(broken).ok).toBe(false);
  });
});

describe('mushaf-layout@1 (S-02)', () => {
  it('accepts the bundled 604-page layout', () => {
    const result = validateMushafLayout(layout);
    expect(result.errors).toEqual([]);
    expect(result.ok).toBe(true);
  });

  it('rejects a page count other than 604', () => {
    const broken = structuredClone(layout);
    broken.pages.pop();
    expect(validateMushafLayout(broken).ok).toBe(false);
  });

  it('rejects an invalid word location', () => {
    const broken = structuredClone(layout);
    const line = broken.pages[0]!.lines.find((entry) => entry.words && entry.words.length > 0)!;
    line.words![0]!.location = '2-6-1';
    expect(validateMushafLayout(broken).ok).toBe(false);
  });

  it('rejects a text line with no words', () => {
    const broken = structuredClone(layout);
    const line = broken.pages[0]!.lines.find((entry) => entry.words && entry.words.length > 0)!;
    line.words = [];
    expect(validateMushafLayout(broken).ok).toBe(false);
  });

  it('rejects a non-monotonic line number', () => {
    const broken = structuredClone(layout);
    const lines = broken.pages[0]!.lines;
    lines[1]!.number = lines[0]!.number;
    expect(validateMushafLayout(broken).ok).toBe(false);
  });
});

describe('qiraat-variants@1 (S-02)', () => {
  const variants = asset('assets/qiraat/variants.json');

  it('accepts the bundled variants against Hafs and the layout', () => {
    const result = validateQiraatVariants(variants, { hafsAyahKeys, hafsWordLocations });
    expect(result.errors).toEqual([]);
    expect(result.ok).toBe(true);
  });

  it('rejects a reader count other than ten', () => {
    const broken = structuredClone(variants) as { readers: Record<string, unknown> };
    delete broken.readers['10'];
    expect(validateQiraatVariants(broken).ok).toBe(false);
  });

  it('rejects a transmitter count other than twenty', () => {
    const broken = structuredClone(variants) as { transmitters: Record<string, unknown> };
    delete broken.transmitters['20'];
    expect(validateQiraatVariants(broken).ok).toBe(false);
  });

  it('rejects a segment ayah missing from Hafs', () => {
    const broken = structuredClone(variants) as {
      junctures: { segments: { ayah: string }[] }[];
    };
    broken.junctures[0]!.segments[0]!.ayah = '999:1';
    const result = validateQiraatVariants(broken, { hafsAyahKeys });
    expect(result.ok).toBe(false);
  });

  it('rejects a word range pointing at a missing layout word', () => {
    const broken = structuredClone(variants) as {
      junctures: { segments: { ayah: string; words: [number, number] | null }[] }[];
    };
    const segment = broken.junctures.flatMap((j) => j.segments).find((s) => s.words)!;
    segment.words = [900, 901];
    const result = validateQiraatVariants(broken, { hafsWordLocations });
    expect(result.ok).toBe(false);
  });
});

describe('ayah-map@1 (S-02)', () => {
  const map = asset('assets/mappings/hafs_to_qalun.json');

  it('accepts the bundled Hafs-to-Qalun map', () => {
    const result = validateAyahMap(map);
    expect(result.errors).toEqual([]);
    expect(result.ok).toBe(true);
  });

  it('rejects an unsupported version', () => {
    const broken = structuredClone(map) as Record<string, unknown>;
    broken['_version'] = '9.9.9';
    expect(validateAyahMap(broken).ok).toBe(false);
  });

  it('rejects an ayah with no target', () => {
    const broken = structuredClone(map) as {
      surahs: Record<string, { ayahs: Record<string, Record<string, unknown>> }>;
    };
    delete broken.surahs['1']!.ayahs['2']!['target_ayah'];
    expect(validateAyahMap(broken).ok).toBe(false);
  });
});

describe('hizb-starts@1 (S-02)', () => {
  const hizbs = asset('assets/navigation/hafs_hizbs.json');

  it('accepts the bundled 60 hizb starts against Hafs', () => {
    const result = validateHizbStarts(hizbs, { hafsAyahKeys });
    expect(result.errors).toEqual([]);
    expect(result.ok).toBe(true);
  });

  it('rejects a wrong start count', () => {
    const broken = structuredClone(hizbs) as { hizb_starts: string[] };
    broken.hizb_starts.pop();
    expect(validateHizbStarts(broken).ok).toBe(false);
  });

  it('rejects a start missing from Hafs', () => {
    const broken = structuredClone(hizbs) as { hizb_starts: string[] };
    broken.hizb_starts[0] = '999:1';
    expect(validateHizbStarts(broken, { hafsAyahKeys }).ok).toBe(false);
  });
});

describe('editions-manifest@1 (S-02)', () => {
  const manifest = asset('assets/editions_manifest.json');

  it('accepts the bundled editions manifest', () => {
    const result = validateEditionsManifest(manifest);
    expect(result.errors).toEqual([]);
    expect(result.ok).toBe(true);
  });

  it('rejects an empty editions list', () => {
    const broken = structuredClone(manifest) as { editions: unknown[] };
    broken.editions = [];
    expect(validateEditionsManifest(broken).ok).toBe(false);
  });

  it('rejects a duplicate edition id', () => {
    const broken = structuredClone(manifest) as { editions: unknown[] };
    broken.editions.push(structuredClone(broken.editions[0]));
    expect(validateEditionsManifest(broken).ok).toBe(false);
  });
});

describe('published-differences@1 (S-02)', () => {
  const published = asset('assets/published_differences.json');

  it('accepts the bundled (empty) published differences', () => {
    const result = validatePublishedDifferences(published);
    expect(result.errors).toEqual([]);
    expect(result.ok).toBe(true);
  });

  it('rejects an unsupported schema version', () => {
    const broken = structuredClone(published) as Record<string, unknown>;
    broken['schema_version'] = '2.0.0';
    expect(validatePublishedDifferences(broken).ok).toBe(false);
  });

  it('rejects an unreviewed record', () => {
    const broken = {
      schema_version: '1.0.0',
      records: [
        {
          id: 'x-1',
          review_status: 'candidate',
          base_span: { reading: 'hafs', ayah: '1:1', start_word: 1, end_word: 1, text: 'أ' },
          target_span: { reading: 'qalun', ayah: '1:1', start_word: 1, end_word: 1, text: 'ب' },
        },
      ],
    };
    const result = validatePublishedDifferences(broken);
    expect(result.ok).toBe(false);
    expect(result.errors.join(' ')).toContain('not reviewed');
  });
});

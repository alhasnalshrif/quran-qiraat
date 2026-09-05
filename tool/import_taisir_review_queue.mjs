#!/usr/bin/env node

import { createHash } from 'node:crypto';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const expectedBlobSha = '9ce968d87a9d37c5716e21d31ae3dc07d5501cce';
const sourceUrl =
  'https://raw.githubusercontent.com/arnizamani/corpus_coranicum_variants_dataset/main/data/taisir_variants.csv';
const projectRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const outputPath = path.join(projectRoot, 'assets', 'taisir_review_queue.json');

function parseCsv(text) {
  const rows = [];
  let row = [];
  let field = '';
  let quoted = false;
  for (let index = 0; index < text.length; index += 1) {
    const character = text[index];
    if (character === '"') {
      if (quoted && text[index + 1] === '"') {
        field += '"';
        index += 1;
      } else {
        quoted = !quoted;
      }
    } else if (character === ',' && !quoted) {
      row.push(field);
      field = '';
    } else if ((character === '\n' || character === '\r') && !quoted) {
      if (character === '\r' && text[index + 1] === '\n') index += 1;
      row.push(field);
      if (row.some(Boolean)) rows.push(row);
      row = [];
      field = '';
    } else {
      field += character;
    }
  }
  if (field || row.length) rows.push([...row, field]);
  return rows;
}

function column(header, name) {
  const index = header.indexOf(name);
  if (index < 0) throw new Error(`Missing required column: ${name}`);
  return index;
}

function sha256(value) {
  return createHash('sha256').update(value).digest('hex');
}

function gitBlobSha(value) {
  const bytes = Buffer.isBuffer(value) ? value : Buffer.from(value);
  return createHash('sha1')
    .update(`blob ${bytes.length}\0`)
    .update(bytes)
    .digest('hex');
}

const [, , sourcePath] = process.argv;
if (!sourcePath) {
  throw new Error('Usage: node tool/import_taisir_review_queue.mjs <taisir_variants.csv>');
}

const sourceBytes = await readFile(sourcePath);
const actualBlobSha = gitBlobSha(sourceBytes);
if (actualBlobSha !== expectedBlobSha) {
  throw new Error(
    `Source blob mismatch: expected ${expectedBlobSha}, received ${actualBlobSha}`,
  );
}
const source = sourceBytes.toString('utf8');
const [header, ...rows] = parseCsv(source);
const fields = {
  surah: column(header, 'surah'),
  verse: column(header, 'verse'),
  word: column(header, 'word'),
  reference: column(header, 'reference'),
  referenceCairo: column(header, 'reference_cairo'),
  qalunShared: column(header, '1 Nāfiʿ'),
  qalun: column(header, '1 Nāfiʿ (Qālūn)'),
  shubahShared: column(header, '5 ʿĀṣim'),
  shubah: column(header, '5 ʿĀṣim (Šuʿba)'),
};

const records = [];
for (const row of rows) {
  const surah = Number(row[fields.surah]);
  const ayah = Number(row[fields.verse]);
  const wordIndex = Number(row[fields.word]);
  if (!surah || !ayah || !wordIndex) continue;
  for (const [reading, sharedColumn, transmitterColumn] of [
    ['qalun', fields.qalunShared, fields.qalun],
    ['shubah', fields.shubahShared, fields.shubah],
  ]) {
    const value = (row[transmitterColumn] || row[sharedColumn] || '').trim();
    if (!value) continue;
    records.push({
      id: `taisir_${reading}_${surah}_${ayah}_${wordIndex}`,
      reading,
      surah,
      ayah,
      wordIndex,
      referenceTransliteration: (row[fields.reference] || '').trim(),
      referenceCairoArabic: (row[fields.referenceCairo] || '').trim(),
      variantTransliteration: value,
      source: 'ad-Dānī, at-Taysīr fī l-qirāʾāt as-sabʿ',
      sourceStatus: 'candidate_unreviewed',
      reviewStatus: 'pending',
    });
  }
}

records.sort((a, b) =>
  a.reading.localeCompare(b.reading) ||
  a.surah - b.surah ||
  a.ayah - b.ayah ||
  a.wordIndex - b.wordIndex,
);
const document = {
  schemaVersion: '1.0.0',
  source: {
    url: sourceUrl,
    blobSha: actualBlobSha,
    downloadedSha256: sha256(sourceBytes),
    license: 'CC BY-SA 4.0',
    work: 'ad-Dānī, at-Taysīr fī l-qirāʾāt as-sabʿ',
  },
  policy:
    'Candidate records are a review queue only. They must not be rendered as published word alignments without qualified scholarly approval.',
  records,
};
await mkdir(path.dirname(outputPath), { recursive: true });
await writeFile(outputPath, `${JSON.stringify(document)}\n`);
console.log(`Wrote ${records.length} review candidates to ${outputPath}`);

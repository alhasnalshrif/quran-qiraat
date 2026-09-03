import { readFile, writeFile } from 'node:fs/promises';

const [, , sourcePath, outputPath] = process.argv;

if (!sourcePath || !outputPath) {
  throw new Error('Usage: node tool/import_taisir_differences.mjs <csv> <json>');
}

function parseCsv(text) {
  const rows = [];
  let row = [];
  let field = '';
  let quoted = false;
  for (let i = 0; i < text.length; i += 1) {
    const character = text[i];
    if (character === '"') {
      if (quoted && text[i + 1] === '"') {
        field += '"';
        i += 1;
      } else {
        quoted = !quoted;
      }
    } else if (character === ',' && !quoted) {
      row.push(field);
      field = '';
    } else if ((character === '\n' || character === '\r') && !quoted) {
      if (character === '\r' && text[i + 1] === '\n') i += 1;
      row.push(field);
      if (row.some((value) => value.length > 0)) rows.push(row);
      row = [];
      field = '';
    } else {
      field += character;
    }
  }
  if (field.length > 0 || row.length > 0) rows.push([...row, field]);
  return rows;
}

const rows = parseCsv(await readFile(sourcePath, 'utf8'));
const [header, ...data] = rows;
const index = (name) => header.indexOf(name);
const fields = {
  qalun: [index('1 Nāfiʿ'), index('1 Nāfiʿ (Qālūn)')],
  shubah: [index('5 ʿĀṣim'), index('5 ʿĀṣim (Šuʿba)')],
};

const readings = { qalun: {}, shubah: {} };
for (const row of data) {
  const surah = Number(row[index('surah')]);
  const verse = Number(row[index('verse')]);
  const word = Number(row[index('word')]);
  if (!surah || !verse || !word) continue;
  const key = `${surah}:${verse}`;
  for (const [reading, columns] of Object.entries(fields)) {
    const value = columns.map((column) => row[column]?.trim()).find(Boolean);
    if (!value) continue;
    const list = readings[reading][key] ??= [];
    if (!list.includes(word)) list.push(word);
  }
}

for (const verses of Object.values(readings)) {
  for (const words of Object.values(verses)) words.sort((a, b) => a - b);
}

await writeFile(outputPath, `${JSON.stringify({
  source: 'Corpus Coranicum variants, ad-Dānī at-Taysīr CSV',
  license: 'CC BY-SA 4.0',
  status: 'candidate — requires scholarly review before release',
  readings,
}, null, 2)}\n`);

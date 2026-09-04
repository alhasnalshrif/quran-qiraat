#!/usr/bin/env node

import { createHash } from 'node:crypto';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const sourceCommit = '72116ce4d405d67823804f0eed795c1e6409b4af';
const sourceRepository = 'https://github.com/zonetecde/mushaf-layout';
const rawBaseUrl = `https://raw.githubusercontent.com/zonetecde/mushaf-layout/${sourceCommit}/mushaf`;
const pageCount = 604;
const thisFile = fileURLToPath(import.meta.url);
const projectRoot = path.resolve(path.dirname(thisFile), '..');
const outputDirectory = path.join(projectRoot, 'assets', 'mushaf', 'layout');
const outputPath = path.join(outputDirectory, 'hafs_madani_604.json');
const metadataPath = path.join(outputDirectory, 'manifest.json');
const validLineTypes = new Set(['surah-header', 'basmala', 'text']);
const wordLocationPattern = /^\d+:\d+:\d+$/;

function fail(message) {
  throw new Error(`Mushaf layout validation failed: ${message}`);
}

function sha256(value) {
  return createHash('sha256').update(value).digest('hex');
}

function validatePage(page, expectedNumber) {
  if (!page || typeof page !== 'object') fail(`page ${expectedNumber} is not an object`);
  if (page.page !== expectedNumber) fail(`expected page ${expectedNumber}, found ${page.page}`);
  if (!Array.isArray(page.lines) || page.lines.length === 0) fail(`page ${expectedNumber} has no lines`);

  let previousLine = 0;
  return {
    number: page.page,
    lines: page.lines.map((line, index) => {
      if (!line || typeof line !== 'object') fail(`page ${expectedNumber}, entry ${index + 1} is invalid`);
      if (!Number.isInteger(line.line) || line.line <= previousLine) {
        fail(`page ${expectedNumber}, entry ${index + 1} has a non-monotonic line number`);
      }
      previousLine = line.line;
      if (!validLineTypes.has(line.type)) fail(`page ${expectedNumber}, line ${line.line} has invalid type ${line.type}`);
      if (line.type === 'text' && (typeof line.text !== 'string' || line.text.trim().length === 0)) {
        fail(`page ${expectedNumber}, text line ${line.line} has empty text`);
      }
      if (line.type !== 'text' && typeof line.text !== 'string' && typeof line.qpcV1 !== 'string' && typeof line.qpcV2 !== 'string') {
        fail(`page ${expectedNumber}, structural line ${line.line} has no display data`);
      }
      if (line.type === 'text' && (!Array.isArray(line.words) || line.words.length === 0)) {
        fail(`page ${expectedNumber}, text line ${line.line} has no words`);
      }
      const words = line.words?.map((word, wordIndex) => {
        if (!word || !wordLocationPattern.test(word.location) || typeof word.word !== 'string' || !word.word.trim()) {
          fail(`page ${expectedNumber}, line ${line.line}, word ${wordIndex + 1} is invalid`);
        }
        return {
          location: word.location,
          text: word.word,
          ...(typeof word.qpcV1 === 'string' ? { qpcV1: word.qpcV1 } : {}),
          ...(typeof word.qpcV2 === 'string' ? { qpcV2: word.qpcV2 } : {}),
        };
      });
      return {
        number: line.line,
        type: line.type,
        ...(typeof line.text === 'string' ? { text: line.text } : {}),
        ...(typeof line.verseRange === 'string' ? { verseRange: line.verseRange } : {}),
        ...(typeof line.surah === 'string' || typeof line.surah === 'number' ? { surah: line.surah } : {}),
        ...(typeof line.qpcV1 === 'string' ? { qpcV1: line.qpcV1 } : {}),
        ...(typeof line.qpcV2 === 'string' ? { qpcV2: line.qpcV2 } : {}),
        ...(words ? { words } : {}),
      };
    }),
  };
}

function validateDocument(document) {
  if (!document || document.schemaVersion !== '1.0.0' || !Array.isArray(document.pages)) {
    fail('output document has an unsupported schema');
  }
  if (document.pages.length !== pageCount) fail(`expected ${pageCount} pages, found ${document.pages.length}`);
  document.pages.forEach((page, index) => validatePage({ page: page.number, lines: page.lines.map((line) => ({
    line: line.number,
    type: line.type,
    text: line.text,
    verseRange: line.verseRange,
    surah: line.surah,
    qpcV1: line.qpcV1,
    qpcV2: line.qpcV2,
    words: line.words?.map((word) => ({ location: word.location, word: word.text, qpcV1: word.qpcV1, qpcV2: word.qpcV2 })),
  })) }, index + 1));
}

async function fetchPage(number) {
  const fileName = `page-${String(number).padStart(3, '0')}.json`;
  const response = await fetch(`${rawBaseUrl}/${fileName}`);
  if (!response.ok) throw new Error(`Could not download ${fileName}: HTTP ${response.status}`);
  return validatePage(await response.json(), number);
}

async function fetchAllPages() {
  const results = new Array(pageCount);
  let next = 1;
  const workers = Array.from({ length: 12 }, async () => {
    while (next <= pageCount) {
      const number = next++;
      results[number - 1] = await fetchPage(number);
      if (number % 50 === 0 || number === pageCount) process.stderr.write(`Downloaded ${number}/${pageCount} pages\n`);
    }
  });
  await Promise.all(workers);
  return results;
}

async function verifyExisting() {
  const serialized = await readFile(outputPath, 'utf8');
  const document = JSON.parse(serialized);
  validateDocument(document);
  const metadata = JSON.parse(await readFile(metadataPath, 'utf8'));
  if (metadata.assetSha256 !== sha256(serialized)) fail('asset SHA-256 does not match manifest');
  if (metadata.source?.commit !== sourceCommit) fail('source commit does not match importer pin');
  console.log(`Verified ${pageCount} pages from ${metadata.source.commit} (${metadata.assetSha256})`);
}

async function importLayout() {
  const pages = await fetchAllPages();
  const document = {
    schemaVersion: '1.0.0',
    editionId: 'hafs_madani_604',
    source: {
      repository: sourceRepository,
      commit: sourceCommit,
      pathTemplate: 'mushaf/page-###.json',
      license: 'ISC',
    },
    pages,
  };
  validateDocument(document);
  const serialized = `${JSON.stringify(document)}\n`;
  const metadata = {
    schemaVersion: '1.0.0',
    editionId: document.editionId,
    pageCount,
    assetSha256: sha256(serialized),
    source: document.source,
  };
  await mkdir(outputDirectory, { recursive: true });
  await writeFile(outputPath, serialized);
  await writeFile(metadataPath, `${JSON.stringify(metadata, null, 2)}\n`);
  console.log(`Wrote ${outputPath}`);
  await verifyExisting();
}

if (process.argv.includes('--check')) {
  await verifyExisting();
} else if (process.argv.includes('--fetch')) {
  await importLayout();
} else {
  console.error('Usage: node tool/import_mushaf_layout.mjs --fetch | --check');
  process.exitCode = 2;
}

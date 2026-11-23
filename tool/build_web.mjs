import {createHash} from 'node:crypto';
import {readdir, readFile, writeFile} from 'node:fs/promises';
import {spawnSync} from 'node:child_process';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const result = spawnSync('flutter', ['build', 'web', '--no-web-resources-cdn',
  ...process.argv.slice(2)], {cwd: root, stdio: 'inherit'});
if (result.status !== 0) process.exit(result.status ?? 1);
const output = path.join(root, 'build/web');
async function files(directory, prefix = '') {
  const found = [];
  for (const entry of await readdir(directory, {withFileTypes: true})) {
    const name = `${prefix}${entry.name}`;
    if (entry.isDirectory()) found.push(...await files(path.join(directory, entry.name), `${name}/`));
    else if (!name.endsWith('.map') && !['quran_service_worker.js', 'flutter_service_worker.js'].includes(name)) found.push(name);
  }
  return found.sort();
}
const resources = await files(output);
const hash = createHash('sha256');
for (const resource of resources) hash.update(resource).update(await readFile(path.join(output, resource)));
const workerSource = await readFile(path.join(root, 'web/quran_service_worker.js'), 'utf8');
hash.update(workerSource);
const version = hash.digest('hex');
const worker = workerSource.replace("const cacheVersion = 'development';", `const cacheVersion = '${version}';`)
  .replace('const resources = [];', `const resources = ${JSON.stringify(['./', ...resources])};`);
await writeFile(path.join(output, 'quran_service_worker.js'), worker);
console.log(`Offline web bundle: ${resources.length} files, version ${version.slice(0, 12)}.`);

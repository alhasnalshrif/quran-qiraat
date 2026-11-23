import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {runInNewContext} from 'node:vm';

const source = (await readFile(new URL('../web/quran_service_worker.js', import.meta.url), 'utf8'))
  .replace("const cacheVersion = 'development';", "const cacheVersion = 'test-version';")
  .replace('const resources = [];', "const resources = ['./', 'main.dart.js'];");

function environment({failInstall = false} = {}) {
  const listeners = {};
  const stores = new Map([['quran-offline-old', new Map()], ['other-app', new Map()]]);
  let claimed = false;
  let skipped = false;
  let fetched = 0;
  const scope = 'https://example.test/quran/';
  const cacheStorage = {
    keys: async () => [...stores.keys()],
    delete: async key => stores.delete(key),
    open: async key => {
      if (!stores.has(key)) stores.set(key, new Map());
      const store = stores.get(key);
      return {
        addAll: async requests => {
          if (failInstall) throw new Error('synthetic download failure');
          for (const request of requests) store.set(request.url, 'cached');
        },
        match: async request => {
          const url = new URL(request.url);
          url.search = '';
          return store.get(url.href);
        }
      };
    }
  };
  const self = {
    registration: {scope}, location: {origin: 'https://example.test'},
    clients: {claim: async () => {claimed = true;}},
    skipWaiting: async () => {skipped = true;},
    addEventListener: (name, callback) => {listeners[name] = callback;}
  };
  runInNewContext(source, {self, caches: cacheStorage, URL, Request,
    fetch: async () => {fetched++; return 'network';}});
  return {stores, listeners, get claimed() {return claimed;},
    get skipped() {return skipped;}, get fetched() {return fetched;}};
}

function lifecycle(env, name) {
  let pending;
  env.listeners[name]({waitUntil: promise => {pending = promise;}});
  return pending;
}

test('successful offline install caches the subpath and activates atomically', async () => {
  const env = environment();
  await lifecycle(env, 'install');
  assert(env.stores.get('quran-offline-test-version').has('https://example.test/quran/main.dart.js'));
  assert(env.skipped);
  await lifecycle(env, 'activate');
  assert(env.claimed);
  assert(!env.stores.has('quran-offline-old'));
  assert(env.stores.has('other-app'));
});

test('failed precache preserves the previous offline version', async () => {
  const env = environment({failInstall: true});
  await assert.rejects(lifecycle(env, 'install'));
  assert(!env.stores.has('quran-offline-test-version'));
  assert(env.stores.has('quran-offline-old'));
  assert(!env.skipped);
});

test('offline requests use cached data including cache-busting queries', async () => {
  const env = environment();
  await lifecycle(env, 'install');
  let response;
  env.listeners.fetch({request: new Request('https://example.test/quran/main.dart.js?v=1'),
    respondWith: promise => {response = promise;}});
  assert.equal(await response, 'cached');
  assert.equal(env.fetched, 0);
});

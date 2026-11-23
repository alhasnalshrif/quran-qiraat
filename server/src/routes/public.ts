import { createHash } from 'node:crypto';

import { Hono, type Context } from 'hono';

import type { Database } from '../db/client.js';
import type { ManifestSigner } from '../services/manifest-signer.js';
import type { PackStorage } from '../services/storage.js';
import { buildManifest, type Channel, type Platform } from '../services/manifest.js';

export interface PublicRoutesOptions {
  sql: Database;
  signer: ManifestSigner;
  /** Where pack files are served from (01 §2.2 CDN base). */
  cdnBaseUrl: string;
  /** Reads pack bytes when CDN_BASE_URL is this server itself (02 §4). */
  storage?: PackStorage | undefined;
  now?: (() => Date) | undefined;
  /** Cache lifetime for one manifest; 60 seconds per 02 §4. */
  cacheTtlMs?: number;
  /** Shared cache so a publish can clear it (02 §4). */
  cache?: ManifestCache | undefined;
}

const channels: Channel[] = ['stable', 'beta', 'internal'];
const platforms: Platform[] = ['ios', 'android'];

interface CacheEntry {
  body: string;
  etag: string;
  expiresAt: number;
}

/** In-memory manifest cache keyed by platform/build/channel (02 §4). */
export class ManifestCache {
  private readonly entries = new Map<string, CacheEntry>();
  private readonly ttlMs: number;
  private readonly now: () => Date;

  constructor(ttlMs = 60_000, now: () => Date = () => new Date()) {
    this.ttlMs = ttlMs;
    this.now = now;
  }

  get(key: string): CacheEntry | undefined {
    const entry = this.entries.get(key);
    if (!entry) return undefined;
    if (entry.expiresAt <= this.now().getTime()) {
      this.entries.delete(key);
      return undefined;
    }
    return entry;
  }

  set(key: string, body: string): CacheEntry {
    const entry: CacheEntry = {
      body,
      etag: `"${createHash('sha256').update(body).digest('hex')}"`,
      expiresAt: this.now().getTime() + this.ttlMs,
    };
    this.entries.set(key, entry);
    return entry;
  }

  /** Called after any publish (02 §4). */
  clear(): void {
    this.entries.clear();
  }

  get size(): number {
    return this.entries.size;
  }
}

/**
 * The public `/v1` routes (01 §2, 02 §4). `GET /v1/manifest` validates the
 * request, builds and signs the manifest, serves it from a 60-second cache,
 * and answers 304 when the client's ETag matches.
 */
export function publicRoutes(options: PublicRoutesOptions): Hono {
  const app = new Hono();
  const cache = options.cache ?? new ManifestCache(options.cacheTtlMs, options.now);

  app.get('/manifest', async (c) => {
    const platform = c.req.query('platform');
    const build = Number(c.req.query('build'));
    const channel = c.req.query('channel') ?? 'stable';
    const protocol = c.req.query('protocol');

    if (!platform || !platforms.includes(platform as Platform)) {
      return invalid(c, 'invalid_request', 'platform must be ios or android.');
    }
    if (!Number.isInteger(build) || build < 1) {
      return invalid(c, 'invalid_request', 'build must be an integer ≥ 1.');
    }
    if (!channels.includes(channel as Channel)) {
      return invalid(c, 'invalid_request', 'channel must be stable, beta or internal.');
    }
    if (protocol !== '1') {
      return invalid(c, 'unsupported_protocol', 'This server speaks protocol 1 only.');
    }

    const key = `${platform}:${build}:${channel}`;
    let entry = cache.get(key);

    if (!entry) {
      const payload = await buildManifest({
        sql: options.sql,
        signer: options.signer,
        platform: platform as Platform,
        build,
        channel: channel as Channel,
        cdnBaseUrl: options.cdnBaseUrl,
        now: options.now ? options.now() : new Date(),
      });
      // Sign the exact bytes that are sent, with no re-serialisation.
      const payloadBytes = Buffer.from(JSON.stringify(payload), 'utf8');
      entry = cache.set(key, JSON.stringify(options.signer.signPayload(payloadBytes)));
    }

    const ifNoneMatch = c.req.header('if-none-match');
    if (ifNoneMatch && ifNoneMatch === entry.etag) {
      return new Response(null, {
        status: 304,
        headers: { etag: entry.etag, 'cache-control': 'public, max-age=300' },
      });
    }

    return new Response(entry.body, {
      status: 200,
      headers: {
        'content-type': 'application/json',
        etag: entry.etag,
        'cache-control': 'public, max-age=300',
      },
    });
  });

  /**
   * Serves a pack file directly when this server is the CDN (02 §4). When
   * CDN_BASE_URL points elsewhere, the app uses that absolute URL instead.
   */
  app.get('/packs/:packId/:version/*', async (c) => {
    const packId = c.req.param('packId');
    const version = c.req.param('version');
    const prefix = `packs/${packId}/${version}/`;
    const at = c.req.path.indexOf(prefix);
    const rest = at >= 0 ? c.req.path.slice(at + prefix.length) : '';
    if (!rest || !options.storage) return invalid(c, 'not_found', 'Unknown pack file.');

    let bytes: Uint8Array | null = null;
    try {
      bytes = await options.storage.readObject(`packs/${packId}/${version}/${rest}`);
    } catch {
      // Storage unavailable: treat it as a missing file, not a server fault.
      bytes = null;
    }
    if (!bytes) return invalid(c, 'not_found', 'Unknown pack file.');

    // Uint8Array is a valid BodyInit at runtime; the DOM type is not in scope here.
    return new Response(bytes as unknown as ReadableStream, {
      headers: {
        'content-type': rest.endsWith('.json') ? 'application/json' : 'application/octet-stream',
        'cache-control': 'public, max-age=300',
      },
    });
  });

  return app;
}

function invalid(c: Context, code: string, message: string) {
  const status = code === 'not_found' ? 404 : 400;
  return c.json({ error: { code, message } }, status);
}

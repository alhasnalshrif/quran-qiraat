import type { Database } from '../db/client.js';
import type { ManifestPayload } from '@quran/contracts';
import type { ManifestSigner } from './manifest-signer.js';

export type Channel = 'stable' | 'beta' | 'internal';
export type Platform = 'ios' | 'android';

export interface BuildManifestOptions {
  sql: Database;
  signer: ManifestSigner;
  platform: Platform;
  build: number;
  channel: Channel;
  /** Prefix for pack file URLs (01 §2.2 `CDN_BASE_URL`). */
  cdnBaseUrl: string;
  now?: Date;
  ttlDays?: number;
}

interface ReleaseRow {
  pack_id: string;
  version: number;
  format: string;
  min_app_build: number;
  source_name: string | null;
  source_revision: string | null;
  notes_ar: string | null;
}

interface FileRow {
  pack_id: string;
  version: number;
  path: string;
  object_key: string;
  sha256: string;
  size: number;
}

/**
 * Builds the manifest payload of 01 §2.2 from the database: the newest
 * published version per pack for this channel that this build can read,
 * everything revoked, the app policy, remote config and live announcements.
 */
export async function buildManifest(
  options: BuildManifestOptions,
): Promise<ManifestPayload> {
  const { sql, platform, build, channel } = options;
  const now = options.now ?? new Date();
  const ttlDays = Math.min(options.ttlDays ?? 7, 7);
  const expiresAt = new Date(now.getTime() + ttlDays * 24 * 60 * 60 * 1000);

  // Newest published release per pack in this channel, readable by this build.
  const releases = await sql<ReleaseRow[]>`
    select distinct on (pv.pack_id)
      pv.pack_id, pv.version, pv.format, pv.min_app_build,
      pv.source_name, pv.source_revision, pv.notes_ar
    from channel_releases cr
    join pack_versions pv on pv.id = cr.pack_version_id
    where cr.channel = ${channel}::channel
      and pv.status = 'published'
      and pv.min_app_build <= ${build}
    order by pv.pack_id, pv.version desc
  `;

  const files = await sql<FileRow[]>`
    select pv.pack_id, pv.version, pf.path, pf.object_key, pf.sha256, pf.size
    from pack_files pf
    join pack_versions pv on pv.id = pf.pack_version_id
    where pv.status = 'published'
    order by pv.pack_id, pv.version, pf.path
  `;

  const revoked = await sql<{ pack_id: string; version: number }[]>`
    select distinct pack_id, version from pack_versions
    where status = 'revoked'
    order by pack_id, version
  `;

  const [policy] = await sql<
    {
      latest_build: number;
      min_supported_build: number;
      store_url: string | null;
      message_ar: string | null;
    }[]
  >`
    select latest_build, min_supported_build, store_url, message_ar
    from app_platforms where platform = ${platform}::platform
  `;

  const configRows = await sql<{ key: string; value: unknown }[]>`
    select key, value from remote_config
    where channel = ${channel}::channel
      and (platform is null or platform = ${platform}::platform)
      and (min_build is null or min_build <= ${build})
      and (max_build is null or max_build >= ${build})
    order by key
  `;

  const announcementRows = await sql<
    {
      id: string;
      title_ar: string;
      body_ar: string;
      url: string | null;
      starts_at: string | Date;
      ends_at: string | Date;
      priority: 'normal' | 'high';
    }[]
  >`
    select id, title_ar, body_ar, url, starts_at, ends_at, priority
    from announcements
    where published = true
      and channel = ${channel}::channel
      and (platform is null or platform = ${platform}::platform)
      and starts_at <= ${now.toISOString()}::timestamptz
      and ends_at > ${now.toISOString()}::timestamptz
    order by priority desc, starts_at
  `;

  const config: Record<string, unknown> = {};
  for (const row of configRows) config[row.key] = row.value;

  return {
    protocol: 1,
    issuedAt: now.toISOString(),
    expiresAt: expiresAt.toISOString(),
    channel,
    app: {
      latestBuild: policy?.latest_build ?? build,
      minSupportedBuild: policy?.min_supported_build ?? 1,
      storeUrl: policy?.store_url ?? 'https://example.com/app',
      ...(policy?.message_ar ? { message: { ar: policy.message_ar } } : {}),
    },
    packs: releases.map((release) => ({
      packId: release.pack_id,
      version: release.version,
      format: release.format,
      ...(release.source_name
        ? {
            source: {
              name: release.source_name,
              revision: release.source_revision ?? '',
            },
          }
        : {}),
      ...(release.notes_ar ? { notes: { ar: release.notes_ar } } : {}),
      files: files
        .filter(
          (file) => file.pack_id === release.pack_id && file.version === release.version,
        )
        .map((file) => ({
          path: file.path,
          url: `${options.cdnBaseUrl ?? ''}/${file.object_key}`,
          sha256: file.sha256,
          size: Number(file.size),
        })),
    })),
    revoked: revoked.map((row) => ({ packId: row.pack_id, version: row.version })),
    config,
    announcements: announcementRows.map((row) => ({
      id: row.id,
      title: { ar: row.title_ar },
      body: { ar: row.body_ar },
      url: row.url,
      startsAt: new Date(row.starts_at).toISOString(),
      endsAt: new Date(row.ends_at).toISOString(),
      priority: row.priority,
    })),
  };
}

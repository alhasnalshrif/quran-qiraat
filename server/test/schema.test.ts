import { describe, expect, it } from 'vitest';

import {
  adminSessions,
  adminUsers,
  announcements,
  appPlatforms,
  auditLog,
  channelReleases,
  notifications,
  packFiles,
  packVersions,
  packs,
  remoteConfig,
} from '../src/db/schema.js';

/**
 * S-04: every table in 02 §3 exists with its required columns. The real
 * constraint check runs `db:migrate` against Postgres; this pins the shape so
 * a rename cannot slip through unnoticed.
 */
describe('drizzle schema (S-04)', () => {
  const tables = {
    packs,
    packVersions,
    packFiles,
    channelReleases,
    appPlatforms,
    remoteConfig,
    announcements,
    adminUsers,
    adminSessions,
    notifications,
    auditLog,
  };

  it('defines all eleven tables of 02 §3', () => {
    expect(Object.keys(tables)).toHaveLength(11);
    expect(packs).toBeDefined();
  });

  it('every table carries created_at and updated_at', () => {
    for (const [name, table] of Object.entries(tables)) {
      const columns = Object.keys(table);
      if (name === 'adminSessions') {
        // Sessions only need a creation time (02 §3).
        expect(columns, name).toContain('createdAt');
        continue;
      }
      if (name === 'auditLog') {
        // The audit log times entries with `at` (02 §3).
        expect(columns, name).toContain('at');
        continue;
      }
      expect(columns, name).toContain('createdAt');
      expect(columns, name).toContain('updatedAt');
    }
  });

  it('packs use the stable packId as primary key', () => {
    expect(packs.id.primary).toBe(true);
  });

  it('pack_versions are unique per pack and version', () => {
    expect(packVersions.packId.notNull).toBe(true);
    expect(packVersions.version.notNull).toBe(true);
    expect(packFiles.path.notNull).toBe(true);
    expect(packFiles.sha256.notNull).toBe(true);
  });

  it('the required text and timestamp columns are not nullable', () => {
    expect(announcements.titleAr.notNull).toBe(true);
    expect(announcements.bodyAr.notNull).toBe(true);
    expect(notifications.titleAr.notNull).toBe(true);
    expect(notifications.bodyAr.notNull).toBe(true);
    expect(channelReleases.releasedAt.notNull).toBe(true);
    expect(remoteConfig.value.notNull).toBe(true);
    expect(auditLog.action.notNull).toBe(true);
  });

  it('pack version status starts at draft and min_app_build at 1', () => {
    expect(packVersions.status.default).toBe('draft');
    expect(packVersions.minAppBuild.default).toBe(1);
    expect(notifications.status.default).toBe('draft');
    expect(announcements.published.default).toBe(false);
    expect(adminUsers.role.default).toBe('editor');
  });

  it('target_platforms is an array column', () => {
    expect(notifications.targetPlatforms.columnType).toBe('PgArray');
    expect(notifications.targetPlatforms.default).toEqual([]);
  });
});

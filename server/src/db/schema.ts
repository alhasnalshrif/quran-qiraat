import {
  bigint,
  boolean,
  index,
  integer,
  jsonb,
  pgEnum,
  pgTable,
  primaryKey,
  text,
  timestamp,
  uniqueIndex,
  uuid,
} from 'drizzle-orm/pg-core';

/** Shared timestamps; every table carries them (02 §3). */
const timestamps = {
  createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
  updatedAt: timestamp('updated_at', { withTimezone: true }).notNull().defaultNow(),
};

export const channelEnum = pgEnum('channel', ['stable', 'beta', 'internal']);

export const platformEnum = pgEnum('platform', ['ios', 'android']);

export const packVersionStatusEnum = pgEnum('pack_version_status', [
  'draft',
  'validated',
  'published',
  'revoked',
]);

export const adminRoleEnum = pgEnum('admin_role', ['owner', 'editor']);

export const announcementPriorityEnum = pgEnum('announcement_priority', [
  'normal',
  'high',
]);

export const notificationStatusEnum = pgEnum('notification_status', [
  'draft',
  'scheduled',
  'sent',
  'failed',
  'cancelled',
]);

/** Packs have a stable id that never changes (01 §1.1). */
export const packs = pgTable('packs', {
  id: text('id').primaryKey(),
  titleAr: text('title_ar').notNull(),
  descriptionAr: text('description_ar'),
  formatFamily: text('format_family').notNull(),
  ...timestamps,
});

export const adminUsers = pgTable(
  'admin_users',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    email: text('email').notNull(),
    passwordHash: text('password_hash').notNull(),
    role: adminRoleEnum('role').notNull().default('editor'),
    disabled: boolean('disabled').notNull().default(false),
    lastLoginAt: timestamp('last_login_at', { withTimezone: true }),
    failedLoginCount: integer('failed_login_count').notNull().default(0),
    lockedUntil: timestamp('locked_until', { withTimezone: true }),
    ...timestamps,
  },
  (table) => ({
    emailUnique: uniqueIndex('admin_users_email_unique').on(table.email),
  }),
);

export const packVersions = pgTable(
  'pack_versions',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    packId: text('pack_id')
      .notNull()
      .references(() => packs.id),
    version: integer('version').notNull(),
    format: text('format').notNull(),
    minAppBuild: integer('min_app_build').notNull().default(1),
    status: packVersionStatusEnum('status').notNull().default('draft'),
    sourceName: text('source_name'),
    sourceRevision: text('source_revision'),
    notesAr: text('notes_ar'),
    createdBy: uuid('created_by').references(() => adminUsers.id),
    ...timestamps,
  },
  (table) => ({
    packVersionUnique: uniqueIndex('pack_versions_pack_version_unique').on(
      table.packId,
      table.version,
    ),
    packIndex: index('pack_versions_pack_id_idx').on(table.packId),
  }),
);

export const packFiles = pgTable(
  'pack_files',
  {
    packVersionId: uuid('pack_version_id')
      .notNull()
      .references(() => packVersions.id, { onDelete: 'cascade' }),
    path: text('path').notNull(),
    objectKey: text('object_key').notNull(),
    sha256: text('sha256').notNull(),
    size: bigint('size', { mode: 'number' }).notNull(),
    ...timestamps,
  },
  (table) => ({
    pk: primaryKey({ columns: [table.packVersionId, table.path] }),
  }),
);

export const channelReleases = pgTable(
  'channel_releases',
  {
    channel: channelEnum('channel').notNull(),
    packVersionId: uuid('pack_version_id')
      .notNull()
      .references(() => packVersions.id, { onDelete: 'cascade' }),
    releasedAt: timestamp('released_at', { withTimezone: true }).notNull().defaultNow(),
    ...timestamps,
  },
  (table) => ({
    pk: primaryKey({ columns: [table.channel, table.packVersionId] }),
    versionIndex: index('channel_releases_pack_version_idx').on(table.packVersionId),
  }),
);

export const appPlatforms = pgTable('app_platforms', {
  platform: platformEnum('platform').primaryKey(),
  latestBuild: integer('latest_build').notNull(),
  minSupportedBuild: integer('min_supported_build').notNull(),
  storeUrl: text('store_url'),
  messageAr: text('message_ar'),
  ...timestamps,
});

export const remoteConfig = pgTable(
  'remote_config',
  {
    /** Surrogate key: the lookup columns are nullable, so they cannot be a PK. */
    id: uuid('id').primaryKey().defaultRandom(),
    key: text('key').notNull(),
    channel: channelEnum('channel').notNull(),
    platform: platformEnum('platform'),
    minBuild: integer('min_build'),
    maxBuild: integer('max_build'),
    value: jsonb('value').notNull(),
    ...timestamps,
  },
  (table) => ({
    keyIndex: index('remote_config_key_idx').on(table.key, table.channel),
  }),
);

export const announcements = pgTable(
  'announcements',
  {
    id: text('id').primaryKey(),
    titleAr: text('title_ar').notNull(),
    bodyAr: text('body_ar').notNull(),
    url: text('url'),
    channel: channelEnum('channel').notNull(),
    platform: platformEnum('platform'),
    startsAt: timestamp('starts_at', { withTimezone: true }).notNull(),
    endsAt: timestamp('ends_at', { withTimezone: true }).notNull(),
    priority: announcementPriorityEnum('priority').notNull().default('normal'),
    published: boolean('published').notNull().default(false),
    ...timestamps,
  },
  (table) => ({
    channelIndex: index('announcements_channel_idx').on(table.channel),
  }),
);

/** Only a hash of the session token is stored (02 §3). */
export const adminSessions = pgTable(
  'admin_sessions',
  {
    id: text('id').primaryKey(),
    userId: uuid('user_id')
      .notNull()
      .references(() => adminUsers.id, { onDelete: 'cascade' }),
    expiresAt: timestamp('expires_at', { withTimezone: true }).notNull(),
    createdIpHash: text('created_ip_hash'),
    /** Per-session CSRF token; the browser echoes it back on writes (02 §5). */
    csrfToken: text('csrf_token').notNull(),
    createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
  },
  (table) => ({
    userIndex: index('admin_sessions_user_idx').on(table.userId),
  }),
);

export const notifications = pgTable(
  'notifications',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    channel: channelEnum('channel').notNull(),
    titleAr: text('title_ar').notNull(),
    bodyAr: text('body_ar').notNull(),
    link: text('link'),
    targetPlatforms: text('target_platforms').array().notNull().default([]),
    targetMinBuild: integer('target_min_build'),
    targetMaxBuild: integer('target_max_build'),
    scheduledAt: timestamp('scheduled_at', { withTimezone: true }),
    status: notificationStatusEnum('status').notNull().default('draft'),
    onesignalId: text('onesignal_id'),
    recipients: integer('recipients'),
    error: text('error'),
    createdBy: uuid('created_by').references(() => adminUsers.id),
    ...timestamps,
  },
  (table) => ({
    channelIndex: index('notifications_channel_idx').on(table.channel),
    statusIndex: index('notifications_status_idx').on(table.status),
  }),
);

export const auditLog = pgTable(
  'audit_log',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    userId: uuid('user_id').references(() => adminUsers.id),
    action: text('action').notNull(),
    target: text('target'),
    details: jsonb('details'),
    at: timestamp('at', { withTimezone: true }).notNull().defaultNow(),
  },
  (table) => ({
    actionIndex: index('audit_log_action_idx').on(table.action),
    atIndex: index('audit_log_at_idx').on(table.at),
  }),
);

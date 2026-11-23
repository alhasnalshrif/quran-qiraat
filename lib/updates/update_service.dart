/// Coordinates the update check (03 §5): manifest fetch, revocation, download
/// planning and activation. It never touches the UI; the providers expose its
/// results and the sheets render them.
library;

import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'manifest_client.dart';
import 'pack_store.dart';
import 'protocol.dart';
import 'remote_config.dart';

/// The last check, for the updates screen (03 §7).
class UpdateStatus {
  const UpdateStatus({
    required this.checkedAt,
    this.error,
    this.notModified = false,
    this.downloaded = const [],
  });

  final DateTime checkedAt;
  final String? error;
  final bool notModified;
  final List<String> downloaded;
}

/// What a check decided to do.
enum CheckOutcome {
  /// The stored manifest is still current (304).
  notModified,

  /// No network, or a download was skipped because of the Wi-Fi-only setting.
  skipped,

  /// A manifest was verified and its packs downloaded.
  updated,

  /// Nothing to download: everything offered is already active.
  upToDate,

  /// The manifest was rejected; the app keeps its data (01 §3).
  rejected,
}

const String _lastCheckKey = 'updates_last_check';
const String _etagKey = 'updates_manifest_etag';
const String _manifestKey = 'updates_manifest_payload';
const String _wifiOnlyKey = 'updates_wifi_only';
const String _channelKey = 'update_channel';
const String _dismissedBuildKey = 'dismissed_latest_build';
const String _dismissedAnnouncementsKey = 'dismissed_announcements';

/// Runs the manifest check, downloads eligible packs and activates on demand.
class UpdateService {
  UpdateService({
    required this.client,
    required this.store,
    required this.preferences,
    required this.platform,
    required this.build,
    this.connectivity,
    this.clock = DateTime.now,
    this.onActivated,
  });

  final ManifestClient client;
  final PackStore store;
  final SharedPreferences preferences;
  final String platform;
  final int build;
  final Connectivity? connectivity;
  final DateTime Function() clock;

  /// The app build number this check reports (01 §2.1).
  int get appBuild => build;

  /// Called after activation so the app can reload its repository (D8).
  final Future<void> Function()? onActivated;

  /// The last verified, unexpired manifest, if one was stored.
  Manifest? get manifest {
    final stored = preferences.getString(_manifestKey);
    if (stored == null) return null;
    try {
      final parsed = Manifest.fromJson(
        _decode(stored) as Map<String, dynamic>,
      );
      return parsed.isExpiredAt(clock()) ? null : parsed;
    } catch (_) {
      return null;
    }
  }

  RemoteConfig get config => RemoteConfig(manifest?.config ?? const {});

  String get channel => preferences.getString(_channelKey) ?? 'stable';

  Future<void> setChannel(String value) => preferences.setString(_channelKey, value);

  bool get wifiOnly =>
      preferences.getBool(_wifiOnlyKey) ?? config.wifiOnlyDefault;

  Future<void> setWifiOnly(bool value) => preferences.setBool(_wifiOnlyKey, value);

  DateTime? get lastCheck {
    final value = preferences.getInt(_lastCheckKey);
    if (value == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(value);
  }

  /// Whether an automatic check is due (03 §5 step 1).
  bool shouldCheck({required bool manual}) {
    if (manual) return true;
    final last = lastCheck;
    if (last == null) return true;
    return clock().difference(last) >= config.checkInterval;
  }

  /// The outcome of the last check, for the updates screen.
  UpdateStatus? get status {
    final checked = lastCheck;
    if (checked == null) return null;
    return UpdateStatus(
      checkedAt: checked,
      notModified: preferences.getBool('${_etagKey}_not_modified') ?? false,
    );
  }

  /// Runs the whole sequence of 03 §5. Returns [CheckOutcome.skipped] when
  /// offline or waiting for Wi-Fi, and never throws: failures land in
  /// `state.json` and [lastError].
  Future<CheckOutcome> check({required bool manual}) async {
    if (!shouldCheck(manual: manual)) return CheckOutcome.skipped;

    final connection = await connectivity?.checkConnectivity();
    final online =
        connection == null || connection.any((value) => value != ConnectivityResult.none);
    if (!online) {
      await _recordCheck(notModified: false);
      return CheckOutcome.skipped;
    }

    final ManifestResult result;
    try {
      result = await client.fetch(
        platform: platform,
        build: build,
        etag: preferences.getString(_etagKey),
      );
    } catch (_) {
      await _recordCheck(notModified: false);
      return CheckOutcome.skipped;
    }

    if (result.notModified) {
      final etag = result.etag;
      if (etag != null) await preferences.setString(_etagKey, etag);
      await _recordCheck(notModified: true);
      return CheckOutcome.notModified;
    }

    final manifest = result.manifest;
    if (manifest == null) {
      await _recordCheck(notModified: false);
      return CheckOutcome.rejected;
    }

    await _storeManifest(manifest, result.etag);

    // Step 5: withdraw anything this build may be reading that is revoked.
    final active = store.state.active;
    var withdrawn = false;
    for (final entry in active.entries) {
      if (manifest.isRevoked(entry.key, entry.value)) {
        await store.withdraw(entry.key);
        withdrawn = true;
      }
    }
    if (withdrawn) await onActivated?.call();

    // Step 6–7: plan downloads, but only on a connection we may use.
    final wifiOnlyNow = preferences.getBool(_wifiOnlyKey) ?? config.wifiOnlyDefault;
    if (wifiOnlyNow && !_isWifi(connection)) return CheckOutcome.skipped;

    final wanted = <PackRelease>[];
    for (final pack in manifest.packs) {
      final activeVersion = store.activeVersion(pack.packId) ?? 0;
      final pending = store.state.pending[pack.packId] ?? 0;
      if (pack.version > activeVersion && pack.version > pending) {
        wanted.add(pack);
      }
    }
    if (wanted.isEmpty) {
      await _recordCheck(notModified: false);
      return withdrawn ? CheckOutcome.updated : CheckOutcome.upToDate;
    }

    final staged = <String>[];
    for (final pack in wanted) {
      final downloaded = await store.download(pack);
      if (downloaded == null) continue;
      await store.stage(downloaded);
      staged.add(pack.packId);
    }
    await _recordCheck(notModified: false);
    return staged.isEmpty ? CheckOutcome.upToDate : CheckOutcome.updated;
  }

  /// The packs downloaded and waiting for "apply now" (03 §6).
  List<PackRelease> pendingReleases() {
    final current = manifest;
    final result = <PackRelease>[];
    for (final entry in store.state.pending.entries) {
      final release = current?.release(entry.key);
      if (release != null && release.version == entry.value) {
        result.add(release);
      }
    }
    return result;
  }

  /// Applies every pending pack and asks the app to reload (D8).
  Future<void> activatePending() async {
    await store.activatePending();
    await onActivated?.call();
  }

  /// Whether the app build needs a forced update (03 §6).
  bool get requiresUpdate => build < (manifest?.app.minSupportedBuild ?? 0);

  /// Whether a newer store build exists and was not dismissed.
  ///
  /// A forced update already covers this case: offering "later" on top of it
  /// would be contradictory, so the optional sheet never follows a forced one
  /// (03 §6 priority order).
  bool get hasOptionalUpdate {
    final current = manifest;
    if (current == null) return false;
    if (requiresUpdate) return false;
    final dismissed = preferences.getInt(_dismissedBuildKey) ?? 0;
    return build < current.app.latestBuild && current.app.latestBuild > dismissed;
  }

  Future<void> dismissOptionalUpdate() async {
    final current = manifest;
    if (current == null) return;
    await preferences.setInt(_dismissedBuildKey, current.app.latestBuild);
  }

  /// Active announcements the user has not dismissed (03 §6).
  List<Announcement> pendingAnnouncements() {
    final current = manifest;
    if (current == null || !config.announcementsEnabled) return const [];
    final dismissed =
        preferences.getStringList(_dismissedAnnouncementsKey) ?? const [];
    return [
      for (final announcement in current.activeAnnouncements(clock()))
        if (!dismissed.contains(announcement.id)) announcement,
    ];
  }

  Future<void> dismissAnnouncement(String id) async {
    final dismissed = [
      ...?preferences.getStringList(_dismissedAnnouncementsKey),
      id,
    ];
    await preferences.setStringList(_dismissedAnnouncementsKey, dismissed);
  }

  /// The error from the last failed step, if any (03 §5).
  String? get lastError => store.state.lastError;

  bool _isWifi(List<ConnectivityResult>? connection) {
    if (connection == null) return true;
    return connection.contains(ConnectivityResult.wifi) ||
        connection.contains(ConnectivityResult.ethernet);
  }

  Future<void> _storeManifest(Manifest manifest, String? etag) async {
    await preferences.setString(_manifestKey, _encode(manifest));
    if (etag != null) await preferences.setString(_etagKey, etag);
    await _recordCheck(notModified: false);
  }

  Future<void> _recordCheck({required bool notModified}) async {
    await preferences.setInt(_lastCheckKey, clock().millisecondsSinceEpoch);
    await preferences.setBool('${_etagKey}_not_modified', notModified);
  }

  static Object? _decode(String source) => jsonDecode(source);

  static String _encode(Manifest manifest) => jsonEncode(_toJson(manifest));

  static Map<String, dynamic> _toJson(Manifest manifest) => {
    'protocol': 1,
    'issuedAt': manifest.issuedAt.toUtc().toIso8601String(),
    'expiresAt': manifest.expiresAt.toUtc().toIso8601String(),
    'channel': manifest.channel,
    'app': _appToJson(manifest.app),
    'packs': [
      for (final pack in manifest.packs) _packToJson(pack),
    ],
    'revoked': [
      for (final revoked in manifest.revoked)
        {'packId': revoked.packId, 'version': revoked.version},
    ],
    'config': manifest.config,
    'announcements': [
      for (final announcement in manifest.announcements)
        {
          'id': announcement.id,
          'title': {'ar': announcement.title.ar},
          'body': {'ar': announcement.body.ar},
          'url': announcement.url?.toString(),
          'startsAt': announcement.startsAt.toUtc().toIso8601String(),
          'endsAt': announcement.endsAt.toUtc().toIso8601String(),
          'priority': announcement.priority,
        },
    ],
  };

  static Map<String, dynamic> _appToJson(AppPolicy app) => {
    'latestBuild': app.latestBuild,
    'minSupportedBuild': app.minSupportedBuild,
    'storeUrl': app.storeUrl.toString(),
    if (app.message != null) 'message': {'ar': app.message!.ar},
  };

  static Map<String, dynamic> _packToJson(PackRelease pack) => {
    'packId': pack.packId,
    'version': pack.version,
    'format': pack.format,
    if (pack.source != null)
      'source': {'name': pack.source!.name, 'revision': pack.source!.revision},
    if (pack.notes != null) 'notes': {'ar': pack.notes!.ar},
    'files': [
      for (final file in pack.files)
        {
          'path': file.path,
          'url': file.url.toString(),
          'sha256': file.sha256,
          'size': file.size,
        },
    ],
  };
}

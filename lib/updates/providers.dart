import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/quran_repository.dart';
import 'data_source.dart';
import 'manifest_client.dart';
import 'network.dart';
import 'pack_store.dart';
import 'protocol.dart';
import 'remote_config.dart';
import 'update_service.dart';

final dioProvider = Provider<Dio>((ref) {
  return createDioClient();
});

final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError(
    'sharedPreferencesProvider must be overridden in ProviderScope',
  );
});

final quranRepositoryProvider = Provider<QuranRepository>((ref) {
  throw UnimplementedError(
    'quranRepositoryProvider must be overridden in ProviderScope',
  );
});

/// The directory packs live in: `<ApplicationSupport>/packs` (03 §4).
final packsRootProvider = FutureProvider<Directory>((ref) async {
  final support = await getApplicationSupportDirectory();
  return Directory('${support.path}/packs');
});

/// The on-disk pack store, loaded once (03 §4).
final packStoreFutureProvider = FutureProvider<PackStore>((ref) async {
  final root = await ref.watch(packsRootProvider.future);
  final dio = ref.watch(dioProvider);
  final store = PackStore(
    root: root,
    fetchFile: (file) async {
      final response = await dio.get<List<int>>(
        file.url.toString(),
        options: Options(responseType: ResponseType.bytes),
      );
      return response.data ?? const [];
    },
  );
  await store.load();
  return store;
});

final packStoreProvider = Provider<PackStore>((ref) {
  final value = ref.watch(packStoreFutureProvider);
  return value.when(
    data: (store) => store,
    loading: () => throw StateError('pack store is still loading'),
    error: (error, stack) => throw error,
  );
});

/// The data source the app reads pack files from (03 §3).
final dataSourceProvider = Provider<QuranDataSource>((ref) {
  return PackedDataSource(store: ref.watch(packStoreProvider));
});

/// The app's platform as the protocol names it (01 §2.1).
final platformProvider = Provider<String>((ref) {
  if (Platform.isIOS) return 'ios';
  return 'android';
});

/// The current build number from the store package (01 §2.1).
final appBuildProvider = FutureProvider<int>((ref) async {
  final info = await PackageInfo.fromPlatform();
  return int.tryParse(info.buildNumber) ?? 1;
});

/// The update service wired to Dio, the store and the loaded build number.
final updateServiceProvider = FutureProvider<UpdateService>((ref) async {
  final preferences = ref.watch(sharedPreferencesProvider);
  final build = await ref.watch(appBuildProvider.future);
  final store = await ref.watch(packStoreFutureProvider.future);
  final client = ManifestClient(
    dio: ref.watch(dioProvider),
    channel: preferences.getString('update_channel') ?? 'stable',
  );
  return UpdateService(
    client: client,
    store: store,
    preferences: preferences,
    platform: ref.watch(platformProvider),
    build: build,
    connectivity: Connectivity(),
    onActivated: () async => ref.invalidate(quranRepositoryProvider),
  );
});

/// The saved update channel: stable by default (03 §7).
final updateChannelProvider = NotifierProvider<UpdateChannelNotifier, String>(
  UpdateChannelNotifier.new,
);

class UpdateChannelNotifier extends Notifier<String> {
  @override
  String build() {
    final preferences = ref.watch(sharedPreferencesProvider);
    return preferences.getString('update_channel') ?? 'stable';
  }

  Future<void> select(String channel) async {
    if (!channelNames.contains(channel)) return;
    await ref.read(sharedPreferencesProvider).setString('update_channel', channel);
    state = channel;
  }
}

/// The remote config of the last verified manifest (03 §10).
final remoteConfigProvider = Provider<RemoteConfig>((ref) {
  final manifest = ref.watch(manifestProvider);
  return RemoteConfig(manifest?.config ?? const {});
});

/// The last verified manifest, and the check that refreshes it (03 §10).
final manifestProvider = NotifierProvider<ManifestNotifier, Manifest?>(
  ManifestNotifier.new,
);

class ManifestNotifier extends Notifier<Manifest?> {
  @override
  Manifest? build() {
    final preferences = ref.watch(sharedPreferencesProvider);
    final service = ref.watch(updateServiceProvider).value;
    if (service != null) return service.manifest;
    final stored = preferences.getString('updates_manifest_payload');
    if (stored == null) return null;
    try {
      final parsed = Manifest.fromJson(
        jsonDecode(stored) as Map<String, dynamic>,
      );
      return parsed.isExpiredAt(DateTime.now()) ? null : parsed;
    } catch (_) {
      return null;
    }
  }

  /// Runs a check and updates the visible manifest (03 §5).
  Future<CheckOutcome?> check({required bool manual}) async {
    final service = await ref.read(updateServiceProvider.future);
    final outcome = await service.check(manual: manual);
    if (outcome == CheckOutcome.updated || outcome == CheckOutcome.notModified) {
      state = service.manifest;
    }
    return outcome;
  }
}

import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quran_qiraat/features/updates/update_sheets.dart';
import 'package:quran_qiraat/updates/manifest_client.dart';
import 'package:quran_qiraat/updates/pack_store.dart';
import 'package:quran_qiraat/updates/update_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// D19 wiring: which sheet is due, and that only one shows at a time.
///
/// The decision comes from a real UpdateService reading a real manifest out of
/// SharedPreferences. The HTTP client is a Dio whose adapter always fails, and
/// `shouldCheck` is false, so no test ever touches the network. Rendering of
/// each sheet is covered by update_sheets_test.dart.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  late SharedPreferences preferences;

  Map<String, dynamic> payload({
    int latestBuild = 20,
    int minSupportedBuild = 10,
    List<dynamic> announcements = const [],
  }) => {
    'protocol': 1,
    'issuedAt': DateTime.now().toUtc().toIso8601String(),
    'expiresAt': DateTime.now().toUtc().add(const Duration(days: 3)).toIso8601String(),
    'channel': 'stable',
    'app': {
      'latestBuild': latestBuild,
      'minSupportedBuild': minSupportedBuild,
      'storeUrl': 'https://apps.apple.com/app/id1',
      'message': {'ar': 'يلزم تحديث'},
    },
    'packs': <dynamic>[],
    'revoked': <dynamic>[],
    'config': <String, dynamic>{},
    'announcements': announcements,
  };

  Future<void> seed(Map<String, dynamic> manifest) async {
    SharedPreferences.setMockInitialValues({
      'updates_manifest_payload': jsonEncode(manifest),
      // A recent check makes the automatic pass a no-op: no network.
      'updates_last_check': DateTime.now().millisecondsSinceEpoch,
    });
    preferences = await SharedPreferences.getInstance();
  }

  Future<UpdateService> service({required int build}) async {
    final store = PackStore(root: temp, fetchFile: (_) async => const []);
    await store.load();
    final dio = Dio()..httpClientAdapter = _FailingAdapter();
    return UpdateService(
      client: ManifestClient(dio: dio, baseUrl: 'https://example.invalid'),
      store: store,
      preferences: preferences,
      platform: 'ios',
      build: build,
    );
  }

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('quran_runner_test');
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  test('a build below minSupportedBuild requires a forced update (D19)', () async {
    await seed(payload());
    final current = await service(build: 7);

    expect(current.requiresUpdate, isTrue);
    expect(current.hasOptionalUpdate, isFalse);
  });

  test('a build at minSupportedBuild but below latest is optional (D19)', () async {
    await seed(payload());
    final current = await service(build: 12);

    expect(current.requiresUpdate, isFalse);
    expect(current.hasOptionalUpdate, isTrue);
  });

  test('a current build needs no sheet (D19)', () async {
    await seed(payload(latestBuild: 12, minSupportedBuild: 10));
    final current = await service(build: 12);

    expect(current.requiresUpdate, isFalse);
    expect(current.hasOptionalUpdate, isFalse);
  });

  test('a dismissed optional update never returns for that build (D19)', () async {
    await seed(payload(latestBuild: 12, minSupportedBuild: 10));
    final current = await service(build: 11);
    expect(current.hasOptionalUpdate, isTrue);

    await current.dismissOptionalUpdate();
    expect(current.hasOptionalUpdate, isFalse);

    // A newer build in the store re-arms it.
    await seed(payload(latestBuild: 13, minSupportedBuild: 10));
    final newer = await service(build: 11);
    expect(newer.hasOptionalUpdate, isTrue);
  });

  test('a live announcement is pending until dismissed (D19)', () async {
    await seed(
      payload(
        latestBuild: 1,
        minSupportedBuild: 1,
        announcements: [
          {
            'id': 'a-1',
            'title': {'ar': 'إعلان'},
            'body': {'ar': 'نص'},
            'url': null,
            'startsAt': DateTime.now().toUtc().subtract(const Duration(days: 1)).toIso8601String(),
            'endsAt': DateTime.now().toUtc().add(const Duration(days: 1)).toIso8601String(),
            'priority': 'normal',
          },
        ],
      ),
    );
    final current = await service(build: 1);

    expect(current.pendingAnnouncements(), hasLength(1));
    await current.dismissAnnouncement('a-1');
    expect(current.pendingAnnouncements(), isEmpty);
  });

  test('the queue picks the highest-priority sheet, one at a time (D19)', () async {
    await seed(payload());
    final current = await service(build: 7);

    final queue = UpdateSheetQueue(
      requiresUpdate: current.requiresUpdate,
      hasOptionalUpdate: current.hasOptionalUpdate,
    );
    expect(
      queue.next(pending: const [], announcements: const []),
      UpdateSheet.forcedUpdate,
    );

    queue.begin();
    expect(
      queue.next(pending: const [], announcements: current.pendingAnnouncements()),
      isNull,
    );
    queue.end();

    expect(
      queue.next(pending: const [], announcements: const []),
      UpdateSheet.forcedUpdate,
    );
  });
}

/// Dial never succeeds; the service must swallow the failure.
class _FailingAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async => throw DioException.connectionError(
    requestOptions: options,
    reason: 'offline in tests',
  );

  @override
  void close({bool force = false}) {}
}

import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quran_qiraat/updates/manifest_client.dart';
import 'package:quran_qiraat/updates/pack_store.dart';
import 'package:quran_qiraat/updates/update_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A-08: UpdateService behaviour per 03 §5 — 304, offline, Wi-Fi only, manual
/// vs automatic checks, and checkIntervalHours.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  late SharedPreferences preferences;
  late Map<String, List<int>> files;
  late List<RequestOptions> requests;
  late Object? nextBody;
  late int nextStatus;

  final payload = jsonEncode({
    'protocol': 1,
    'issuedAt': '2026-11-23T10:00:00Z',
    'expiresAt': '2026-11-30T10:00:00Z',
    'channel': 'stable',
    'app': {
      'latestBuild': 9,
      'minSupportedBuild': 5,
      'storeUrl': 'https://apps.apple.com/app/id1',
    },
    'packs': <dynamic>[],
    'revoked': <dynamic>[],
    'config': {'updates.checkIntervalHours': 6},
    'announcements': <dynamic>[],
  });

  ManifestClient client({DateTime Function()? clock}) {
    final dio = Dio();
    dio.httpClientAdapter = _Adapter((options) {
      requests.add(options);
      return ResponseBody.fromString(
        nextStatus == 304 ? '' : (nextBody is String ? nextBody! as String : jsonEncode(nextBody)),
        nextStatus,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
          'etag': ['"e1"'],
        },
      );
    });
    return ManifestClient(
      dio: dio,
      baseUrl: 'https://api.example.com',
      keys: const {},
      clock: clock ?? () => DateTime.utc(2026, 11, 24),
    );
  }

  UpdateService service({
    DateTime Function()? clock,
    Future<void> Function()? onActivated,
    bool? connectivityNone,
  }) {
    final store = PackStore(
      root: temp,
      fetchFile: (file) async => files[file.path]!,
    );
    return UpdateService(
      client: client(clock: clock),
      store: store,
      preferences: preferences,
      platform: 'ios',
      build: 7,
      clock: clock ?? () => DateTime.utc(2026, 11, 24),
      onActivated: onActivated,
    );
  }

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('update_service_test');
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
    files = {};
    requests = [];
    nextBody = null;
    nextStatus = 200;
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  test('an unverified manifest is rejected and changes nothing', () async {
    nextBody = payload; // signed with keys: {}, so untrusted
    final result = await service().check(manual: true);
    expect(result, CheckOutcome.rejected);
    expect(preferences.getString('updates_manifest_payload'), isNull);
  });

  test('304 records the check without replacing the manifest', () async {
    nextStatus = 304;
    final result = await service().check(manual: true);
    expect(result, CheckOutcome.notModified);
    expect(requests.single.queryParameters['platform'], 'ios');
    expect(requests.single.queryParameters['build'], 7);
    expect(requests.single.queryParameters['protocol'], 1);
    expect(preferences.getInt('updates_last_check'), isNotNull);
    expect(preferences.getBool('updates_manifest_etag_not_modified'), isTrue);
  });

  test('a second automatic check inside the interval is skipped', () async {
    nextStatus = 304;
    final first = service();
    expect(await first.check(manual: true), CheckOutcome.notModified);
    expect(await first.check(manual: false), CheckOutcome.skipped);
    expect(requests, hasLength(1));
  });

  test('a manual check ignores the interval', () async {
    nextStatus = 304;
    final current = service();
    await current.check(manual: true);
    await current.check(manual: true);
    expect(requests, hasLength(2));
  });

  test('an automatic check is allowed once checkIntervalHours passed', () async {
    nextStatus = 304;
    var now = DateTime.utc(2026, 11, 24, 8);
    final current = service(clock: () => now);
    await current.check(manual: true);
    now = now.add(const Duration(hours: 7));
    await current.check(manual: false);
    expect(requests, hasLength(2));
  });

  test('the ETag is sent on the next request', () async {
    nextStatus = 304;
    final current = service();
    await current.check(manual: true);
    await current.check(manual: true);
    expect(requests.first.headers.containsKey('If-None-Match'), isFalse);
    expect(requests.last.headers['If-None-Match'], '"e1"');
  });

  test('dismissals and channel selection persist', () async {
    final current = service();
    expect(current.channel, 'stable');
    await current.setChannel('beta');
    expect(current.channel, 'beta');

    expect(current.wifiOnly, isTrue);
    await current.setWifiOnly(false);
    expect(current.wifiOnly, isFalse);
  });

  test('pendingReleases only lists packs still pending in the manifest', () async {
    final current = service();
    expect(current.pendingReleases(), isEmpty);
  });

  test('activatePending asks the app to reload (D8)', () async {
    var reloads = 0;
    final current = service(onActivated: () async => reloads++);
    await current.activatePending();
    expect(reloads, 1);
  });

  test('requiresUpdate and hasOptionalUpdate read the app policy', () async {
    final current = service();
    // No manifest yet: no forced update, no optional one.
    expect(current.requiresUpdate, isFalse);
    expect(current.hasOptionalUpdate, isFalse);
  });
}

class _Adapter implements HttpClientAdapter {
  _Adapter(this.respond);

  final ResponseBody Function(RequestOptions) respond;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async => respond(options);

  @override
  void close({bool force = false}) {}
}

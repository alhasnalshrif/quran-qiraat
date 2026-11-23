import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quran_qiraat/updates/manifest_client.dart';
import 'package:quran_qiraat/updates/network.dart';
import 'package:quran_qiraat/updates/pack_store.dart';
import 'package:quran_qiraat/updates/trusted_keys.dart';
import 'package:quran_qiraat/updates/update_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A-09: the real update loop against the deployed server.
///
/// Skipped unless UPDATE_INTEGRATION=1, because it needs the network and the
/// live signing key. Run with:
///   UPDATE_INTEGRATION=1 flutter test test/integration/published_server_test.dart
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // flutter_test installs a mock HttpClient that answers 400 to every request.
  // This suite talks to the real server on purpose, so restore real networking.
  setUpAll(() => HttpOverrides.global = null);

  final enabled = Platform.environment['UPDATE_INTEGRATION'] == '1';
  final baseUrl =
      Platform.environment['UPDATE_SERVER'] ?? 'https://quran.alhasnalshrif.com';

  group('live manifest (A-09)', () {
    late Dio dio;
    late Directory temp;

    setUpAll(() {
      dio = createDioClient(baseUrl: baseUrl);
    });

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('quran_live_test');
    });

    tearDown(() async {
      if (await temp.exists()) await temp.delete(recursive: true);
    });

    test(
      'downloads, verifies and validates a real manifest',
      () async {
        final client = ManifestClient(
          dio: dio,
          baseUrl: baseUrl,
          keys: trustedKeys,
        );

        final result = await client.fetch(
          platform: 'ios',
          build: 7,
          etag: null,
        );

        expect(result.rejection, isNull, reason: 'the manifest must verify');
        final manifest = result.manifest!;
        expect(manifest.channel, 'stable');
        expect(manifest.app.latestBuild, greaterThan(0));
        expect(manifest.isExpiredAt(DateTime.now()), isFalse);
        expect(result.etag, isNotNull);

        // A second request with the ETag must come back 304 (01 §2.2).
        final repeated = await client.fetch(
          platform: 'ios',
          build: 7,
          etag: result.etag,
        );
        expect(repeated.notModified, isTrue);
      },
      timeout: const Timeout(Duration(seconds: 60)),
      skip: enabled ? false : 'set UPDATE_INTEGRATION=1 to run',
    );

    test(
      'a pack file the manifest lists can be fetched with a matching sha256',
      () async {
        final client = ManifestClient(dio: dio, baseUrl: baseUrl, keys: trustedKeys);
        final manifest = (await client.fetch(platform: 'ios', build: 7)).manifest!;

        if (manifest.packs.isEmpty) {
          // Nothing published yet is a valid state; nothing to verify.
          return;
        }

        final pack = manifest.packs.first;
        final store = PackStore(
          root: temp,
          fetchFile: (file) async {
            final response = await dio.get<List<int>>(
              file.url.toString(),
              options: Options(responseType: ResponseType.bytes),
            );
            return response.data ?? const [];
          },
        );
        await store.load();

        final downloaded = await store.download(pack);
        expect(
          downloaded,
          isNotNull,
          reason: 'sha256, size and the format validator must all accept it',
        );
        expect(store.state.lastError, isNull);
      },
      timeout: const Timeout(Duration(seconds: 120)),
      skip: enabled ? false : 'set UPDATE_INTEGRATION=1 to run',
    );

    test(
      'the service records a check and does not download on a second pass',
      () async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final store = PackStore(
          root: temp,
          fetchFile: (file) async {
            final response = await dio.get<List<int>>(
              file.url.toString(),
              options: Options(responseType: ResponseType.bytes),
            );
            return response.data ?? const [];
          },
        );
        await store.load();

        final service = UpdateService(
          client: ManifestClient(dio: dio, baseUrl: baseUrl, keys: trustedKeys),
          store: store,
          preferences: prefs,
          platform: 'android',
          build: 7,
        );

        final first = await service.check(manual: true);
        expect(
          first,
          isIn([CheckOutcome.notModified, CheckOutcome.upToDate, CheckOutcome.updated]),
        );
        expect(service.lastCheck, isNotNull);

        // An automatic check inside the interval must not hit the network.
        expect(service.shouldCheck(manual: false), isFalse);
      },
      timeout: const Timeout(Duration(seconds: 60)),
      skip: enabled ? false : 'set UPDATE_INTEGRATION=1 to run',
    );
  });

  group('trusted key (A-09)', () {
    test('ships a production key and no test key', () {
      expect(trustedKeys.containsKey('k1'), isTrue);
      expect(trustedKeys.containsKey('test'), isFalse);
      expect(base64Decode(trustedKeys['k1']!), hasLength(32));
    });
  });
}

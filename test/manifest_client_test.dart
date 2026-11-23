import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quran_qiraat/updates/manifest_client.dart';
import 'package:quran_qiraat/updates/network.dart';

/// A-05: manifest request, ETag, signature and expiry checks (01 §2–§3).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final algorithm = Ed25519();
  late SimpleKeyPair keyPair;
  late String publicKeyBase64;

  setUpAll(() async {
    keyPair = await algorithm.newKeyPair();
    final publicKey = await keyPair.extractPublicKey();
    publicKeyBase64 = base64Encode(publicKey.bytes);
  });

  Future<String> signedEnvelope(
    Map<String, dynamic> payload, {
    String keyId = 'k1',
    SimpleKeyPair? signer,
  }) async {
    final bytes = utf8.encode(jsonEncode(payload));
    final signature = await algorithm.sign(bytes, keyPair: signer ?? keyPair);
    return jsonEncode({
      'keyId': keyId,
      'payload': base64Encode(bytes),
      'signature': base64Encode(signature.bytes),
    });
  }

  Map<String, dynamic> payload({
    int protocol = 1,
    String issuedAt = '2026-11-23T10:00:00Z',
    String expiresAt = '2026-11-30T10:00:00Z',
  }) => {
    'protocol': protocol,
    'issuedAt': issuedAt,
    'expiresAt': expiresAt,
    'channel': 'stable',
    'app': {
      'latestBuild': 9,
      'minSupportedBuild': 5,
      'storeUrl': 'https://apps.apple.com/app/id000000000',
    },
    'packs': [
      {
        'packId': 'qiraat-farsh',
        'version': 2,
        'format': 'qiraat-variants@1',
        'files': [
          {
            'path': 'variants.json',
            'url': 'https://cdn.example.com/packs/qiraat-farsh/2/variants.json',
            'sha256': '9f2c5b8e1a7d4f0c3b6e9a2d5f8c1b4e7a0d3f6c9b2e5a8d1f4c7b0e3a6d9f2c',
            'size': 426472,
          },
        ],
      },
    ],
    'revoked': <dynamic>[],
    'config': {'updates.checkIntervalHours': 12},
    'announcements': <dynamic>[],
  };

  ManifestClient client({
    Map<String, String>? keys,
    DateTime Function()? clock,
    Dio? dio,
  }) => ManifestClient(
    dio: dio ?? createDioClient(),
    baseUrl: 'https://api.example.com',
    keys: keys ?? {'k1': publicKeyBase64},
    clock: clock ?? () => DateTime.utc(2026, 11, 24),
  );

  group('verifyResponse (A-05)', () {
    test('accepts a correctly signed, unexpired manifest', () async {
      final check = await client().verifyResponse(
        await signedEnvelope(payload()),
      );
      expect(check, isA<ManifestFetched>());
      final manifest = (check as ManifestFetched).manifest;
      expect(manifest.packs.single.packId, 'qiraat-farsh');
      expect(manifest.app.latestBuild, 9);
    });

    test('rejects an unknown keyId', () async {
      final check = await client().verifyResponse(
        await signedEnvelope(payload(), keyId: 'k9'),
      );
      expect(
        (check as ManifestRejected).reason,
        ManifestRejection.untrustedKey,
      );
    });

    test('rejects a wrong signature', () async {
      final otherKey = await algorithm.newKeyPair();
      final check = await client().verifyResponse(
        await signedEnvelope(payload(), signer: otherKey),
      );
      expect((check as ManifestRejected).reason, ManifestRejection.badSignature);
    });

    test('rejects a tampered payload', () async {
      final envelope =
          jsonDecode(await signedEnvelope(payload())) as Map<String, dynamic>;
      final bytes = base64Decode(envelope['payload'] as String);
      final tampered = utf8.decode(bytes).replaceFirst('"latestBuild":9', '"latestBuild":99');
      envelope['payload'] = base64Encode(utf8.encode(tampered));
      final check = await client().verifyResponse(envelope);
      expect((check as ManifestRejected).reason, ManifestRejection.badSignature);
    });

    test('rejects a different protocol version', () async {
      final check = await client().verifyResponse(
        await signedEnvelope(payload(protocol: 2)),
      );
      expect(
        (check as ManifestRejected).reason,
        ManifestRejection.wrongProtocol,
      );
    });

    test('rejects an expired manifest', () async {
      final check = await client(
        clock: () => DateTime.utc(2026, 12, 1),
      ).verifyResponse(await signedEnvelope(payload()));
      expect((check as ManifestRejected).reason, ManifestRejection.expired);
    });

    test('rejects a body that is not a signed envelope', () async {
      expect(
        (await client().verifyResponse({'nope': true}) as ManifestRejected)
            .reason,
        ManifestRejection.unparseable,
      );
      expect(
        (await client().verifyResponse('not json') as ManifestRejected).reason,
        ManifestRejection.unparseable,
      );
    });
  });

  group('fetch over Dio (A-05)', () {
    late Dio dio;
    late List<RequestOptions> requests;

    Dio dioReturning(ResponseBody Function(RequestOptions) respond) {
      requests = [];
      final clientDio = Dio();
      clientDio.httpClientAdapter = _FakeAdapter((options) {
        requests.add(options);
        return respond(options);
      });
      return clientDio;
    }

    test('sends the contract query and stores the ETag', () async {
      final body = await signedEnvelope(payload());
      dio = dioReturning(
        (_) => ResponseBody.fromString(
          body,
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
            'etag': ['"abc123"'],
          },
        ),
      );

      final result = await client(dio: dio).fetch(platform: 'ios', build: 7);

      final request = requests.single;
      expect(request.path, 'https://api.example.com/v1/manifest');
      expect(request.queryParameters, {
        'platform': 'ios',
        'build': 7,
        'channel': 'stable',
        'protocol': 1,
      });
      expect(request.headers.containsKey('If-None-Match'), isFalse);
      expect(result.etag, '"abc123"');
      expect(result.manifest?.packs.single.version, 2);
    });

    test('sends If-None-Match and reports 304', () async {
      dio = dioReturning(
        (_) => ResponseBody.fromString('', 304, headers: {'etag': ['W/"abc123"']}),
      );

      final result = await client(
        dio: dio,
      ).fetch(platform: 'android', build: 3, etag: '"abc123"');

      expect(requests.single.headers['If-None-Match'], '"abc123"');
      expect(result.notModified, isTrue);
      expect(result.etag, '"abc123"');
      expect(result.manifest, isNull);
    });

    test('maps a server failure to UpdateError', () async {
      dio = dioReturning(
        (_) => ResponseBody.fromString(
          '{"error":{"code":"internal","message":"boom"}}',
          500,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        ),
      );
      await expectLater(
        client(dio: dio).fetch(platform: 'ios', build: 7),
        throwsA(isA<DioException>()),
      );
    });
  });
}

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.respond);

  final ResponseBody Function(RequestOptions) respond;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => respond(options);

  @override
  void close({bool force = false}) {}
}

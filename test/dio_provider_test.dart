import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quran_qiraat/updates/network.dart';
import 'package:quran_qiraat/updates/providers.dart';

class MockAdapter implements HttpClientAdapter {
  MockAdapter(this.handler);

  final Future<ResponseBody> Function(RequestOptions options) handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  group('dioProvider and network retry behavior', () {
    test('dioProvider returns configured Dio instance', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final dio = container.read(dioProvider);
      expect(dio.options.connectTimeout, const Duration(seconds: 10));
      expect(dio.options.receiveTimeout, const Duration(seconds: 30));
      expect(dio.options.headers['User-Agent'], startsWith('QuranQiraat/'));
      expect(dio.interceptors.any((i) => i is DioRetryInterceptor), isTrue);
      expect(dio.interceptors.any((i) => i is DioErrorTransformInterceptor), isTrue);
    });

    test('retries twice on 503 and fails after 3 total attempts', () async {
      int requestCount = 0;
      final delaysRecorded = <Duration>[];

      final dio = createDioClient(
        sleep: (delay) async {
          delaysRecorded.add(delay);
        },
      );

      dio.httpClientAdapter = MockAdapter((options) async {
        requestCount++;
        return ResponseBody.fromString(
          'Service Unavailable',
          503,
          headers: {
            Headers.contentTypeHeader: [Headers.textPlainContentType],
          },
        );
      });

      final container = ProviderContainer(
        overrides: [
          dioProvider.overrideWithValue(dio),
        ],
      );
      addTearDown(container.dispose);

      final client = container.read(dioProvider);

      try {
        await client.get<String>('https://example.com/test');
        fail('Expected DioException');
      } on DioException catch (e) {
        expect(e.error, isA<UpdateError>());
        final updateError = e.error as UpdateError;
        expect(updateError.kind, UpdateErrorKind.server);
      }

      // 1 initial attempt + 2 retries = 3 attempts
      expect(requestCount, 3);
      expect(delaysRecorded, [
        const Duration(seconds: 2),
        const Duration(seconds: 6),
      ]);
    });

    test('does NOT retry on 400 Bad Request (1 attempt only)', () async {
      int requestCount = 0;
      final delaysRecorded = <Duration>[];

      final dio = createDioClient(
        sleep: (delay) async {
          delaysRecorded.add(delay);
        },
      );

      dio.httpClientAdapter = MockAdapter((options) async {
        requestCount++;
        return ResponseBody.fromString(
          'Bad Request',
          400,
          headers: {
            Headers.contentTypeHeader: [Headers.textPlainContentType],
          },
        );
      });

      final container = ProviderContainer(
        overrides: [
          dioProvider.overrideWithValue(dio),
        ],
      );
      addTearDown(container.dispose);

      final client = container.read(dioProvider);

      try {
        await client.get<String>('https://example.com/test');
        fail('Expected DioException');
      } on DioException catch (e) {
        expect(e.error, isA<UpdateError>());
        final updateError = e.error as UpdateError;
        expect(updateError.kind, UpdateErrorKind.invalid);
      }

      // Should only make 1 attempt without retries
      expect(requestCount, 1);
      expect(delaysRecorded, isEmpty);
    });

    test('succeeds if retry succeeds after initial 503', () async {
      int requestCount = 0;

      final dio = createDioClient(
        sleep: (_) async {},
      );

      dio.httpClientAdapter = MockAdapter((options) async {
        requestCount++;
        if (requestCount == 1) {
          return ResponseBody.fromString('Temporary Error', 503);
        }
        return ResponseBody.fromString(
          jsonEncode({'status': 'ok'}),
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      });

      final response = await dio.get<Map<String, dynamic>>('https://example.com/test');
      expect(response.statusCode, 200);
      expect(response.data, {'status': 'ok'});
      expect(requestCount, 2);
    });
  });
}

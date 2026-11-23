import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

enum UpdateErrorKind { offline, server, invalid }

class UpdateError implements Exception {
  const UpdateError(this.kind, [this.message]);
  final UpdateErrorKind kind;
  final String? message;

  @override
  String toString() => 'UpdateError($kind, $message)';
}

/// Custom interceptor that retries on network failures and 5xx responses.
class DioRetryInterceptor extends Interceptor {
  DioRetryInterceptor({
    required this.dio,
    this.maxRetries = 2,
    this.delays = const [Duration(seconds: 2), Duration(seconds: 6)],
    this.sleep = Future.delayed,
  });

  final Dio dio;
  final int maxRetries;
  final List<Duration> delays;
  final Future<void> Function(Duration) sleep;

  static const String retryCountKey = 'x-retry-count';

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    final statusCode = err.response?.statusCode;
    final is5xx = statusCode != null && statusCode >= 500 && statusCode < 600;
    final isNetworkError = err.type == DioExceptionType.connectionTimeout ||
        err.type == DioExceptionType.sendTimeout ||
        err.type == DioExceptionType.receiveTimeout ||
        err.type == DioExceptionType.connectionError;

    if (!is5xx && !isNetworkError) {
      return handler.next(err);
    }

    final currentRetries = (err.requestOptions.extra[retryCountKey] as int?) ?? 0;
    if (currentRetries >= maxRetries) {
      return handler.next(err);
    }

    final nextRetry = currentRetries + 1;
    final delay = delays.length >= nextRetry ? delays[nextRetry - 1] : delays.last;
    await sleep(delay);

    final options = Options(
      method: err.requestOptions.method,
      headers: err.requestOptions.headers,
      responseType: err.requestOptions.responseType,
      contentType: err.requestOptions.contentType,
      validateStatus: err.requestOptions.validateStatus,
      extra: Map<String, dynamic>.from(err.requestOptions.extra)
        ..[retryCountKey] = nextRetry,
    );

    try {
      final response = await dio.request<dynamic>(
        err.requestOptions.path,
        data: err.requestOptions.data,
        queryParameters: err.requestOptions.queryParameters,
        options: options,
        cancelToken: err.requestOptions.cancelToken,
        onReceiveProgress: err.requestOptions.onReceiveProgress,
        onSendProgress: err.requestOptions.onSendProgress,
      );
      return handler.resolve(response);
    } on DioException catch (retryErr) {
      return handler.next(retryErr);
    } catch (e) {
      return handler.next(
        DioException(
          requestOptions: err.requestOptions,
          error: e,
        ),
      );
    }
  }
}

/// Transforms Dio exceptions to UpdateError
class DioErrorTransformInterceptor extends Interceptor {
  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (err.error is UpdateError) {
      return handler.next(err);
    }
    final statusCode = err.response?.statusCode;
    UpdateErrorKind kind;
    if (err.type == DioExceptionType.connectionError ||
        err.type == DioExceptionType.connectionTimeout) {
      kind = UpdateErrorKind.offline;
    } else if (statusCode != null && statusCode >= 500) {
      kind = UpdateErrorKind.server;
    } else {
      kind = UpdateErrorKind.invalid;
    }

    final updateError = UpdateError(kind, err.message);
    handler.next(
      DioException(
        requestOptions: err.requestOptions,
        response: err.response,
        type: err.type,
        error: updateError,
        message: updateError.toString(),
      ),
    );
  }
}

/// Where the update server lives (01 §2.1).
///
/// Every request is built from this, so tests override the provider rather
/// than patching strings at call sites.
const String updateServerBaseUrl = 'https://quran.alhasnalshrif.com';

Dio createDioClient({
  String userAgent = 'QuranQiraat/1.0.0+1',
  String baseUrl = updateServerBaseUrl,
  Future<void> Function(Duration)? sleep,
}) {
  final dio = Dio(
    BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 30),
      headers: {'User-Agent': userAgent},
    ),
  );

  dio.interceptors.addAll([
    DioRetryInterceptor(dio: dio, sleep: sleep ?? Future.delayed),
    DioErrorTransformInterceptor(),
    if (kDebugMode)
      LogInterceptor(
        requestHeader: true,
        requestBody: false,
        responseHeader: false,
        responseBody: false,
      ),
  ]);

  return dio;
}

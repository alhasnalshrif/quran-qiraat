import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:dio/dio.dart';

import 'network.dart';
import 'protocol.dart';
import 'trusted_keys.dart';

/// What a manifest check produced (03 §5 step 2).
sealed class ManifestCheck {
  const ManifestCheck();
}

/// The server answered 304; the stored manifest is still current.
class ManifestNotModified extends ManifestCheck {
  const ManifestNotModified();
}

/// A verified, unexpired manifest.
class ManifestFetched extends ManifestCheck {
  const ManifestFetched(this.manifest);

  final Manifest manifest;
}

/// Why a manifest was rejected (01 §3). The app keeps working unchanged.
enum ManifestRejection {
  unparseable,
  untrustedKey,
  badSignature,
  wrongProtocol,
  expired,
}

/// A manifest that failed verification, with the reason and raw body.
class ManifestRejected extends ManifestCheck {
  const ManifestRejected(this.reason, {this.body});

  final ManifestRejection reason;
  final Object? body;
}

/// The outcome of [ManifestClient.fetch], including the ETag to store.
class ManifestResult {
  const ManifestResult({
    required this.check,
    this.etag,
  });

  final ManifestCheck check;
  final String? etag;

  bool get notModified => check is ManifestNotModified;
  Manifest? get manifest => switch (check) {
    ManifestFetched(:final manifest) => manifest,
    _ => null,
  };
  ManifestRejected? get rejection => switch (check) {
    ManifestRejected rejection => rejection,
    _ => null,
  };
}

/// Requests `GET /v1/manifest`, verifies the signature and expiry, and returns
/// either the manifest or the reason it was rejected (01 §2–§3).
class ManifestClient {
  ManifestClient({
    required this.dio,
    this.baseUrl,
    this.channel = 'stable',
    this.protocol = protocolVersion,
    this.keys = trustedKeys,
    this.clock = DateTime.now,
    SignatureVerifier? verifier,
  }) : _verifier = verifier ?? SignatureVerifier(keys);

  final Dio dio;
  final String? baseUrl;
  final String channel;
  final int protocol;
  final Map<String, String> keys;
  final DateTime Function() clock;
  final SignatureVerifier _verifier;

  /// Fetches the manifest for [platform] and [build]. Errors are reported as
  /// [UpdateError] by the Dio interceptors; a rejected manifest is not an error.
  Future<ManifestResult> fetch({
    required String platform,
    required int build,
    String? etag,
  }) async {
    final response = await dio.get<dynamic>(
      _manifestPath,
      queryParameters: {'platform': platform, 'build': build, 'channel': channel, 'protocol': protocol},
      options: Options(
        headers: {
          'If-None-Match': ?etag,
          'Accept': 'application/json',
        },
        validateStatus: (status) =>
            status != null && (status == 304 || status < 500),
        responseType: ResponseType.json,
      ),
    );

    if (response.statusCode == 304) {
      return ManifestResult(
        check: const ManifestNotModified(),
        etag: _etagOf(response) ?? etag,
      );
    }
    if (response.statusCode != 200) {
      throw UpdateError(
        UpdateErrorKind.server,
        'manifest request failed with ${response.statusCode}',
      );
    }

    final body = response.data;
    final result = await verifyResponse(body);
    return ManifestResult(check: result, etag: _etagOf(response) ?? etag);
  }

  /// Verifies an envelope already obtained from the network. Exposed for tests.
  Future<ManifestCheck> verifyResponse(Object? body) async {
    final Map<String, dynamic> json;
    try {
      final decoded = body is String ? jsonDecode(body) : body;
      json = decoded as Map<String, dynamic>;
    } catch (_) {
      return ManifestRejected(ManifestRejection.unparseable, body: body);
    }

    final SignedManifest envelope;
    try {
      envelope = SignedManifest.fromJson(json);
    } catch (_) {
      return ManifestRejected(ManifestRejection.unparseable, body: body);
    }

    final signatureStatus = await _verifier.verify(envelope);
    if (signatureStatus == SignatureStatus.untrustedKey) {
      return ManifestRejected(ManifestRejection.untrustedKey, body: body);
    }
    if (signatureStatus != SignatureStatus.valid) {
      return ManifestRejected(ManifestRejection.badSignature, body: body);
    }

    final Manifest manifest;
    try {
      manifest = envelope.decodePayload();
    } on FormatException catch (error) {
      final reason = error.message.contains('protocol')
          ? ManifestRejection.wrongProtocol
          : ManifestRejection.unparseable;
      return ManifestRejected(reason, body: body);
    }

    if (manifest.isExpiredAt(clock())) {
      return ManifestRejected(ManifestRejection.expired, body: body);
    }
    return ManifestFetched(manifest);
  }

  String get _manifestPath {
    final base = baseUrl;
    if (base == null) return '/v1/manifest';
    return '${base.endsWith('/') ? base.substring(0, base.length - 1) : base}/v1/manifest';
  }

  static String? _etagOf(Response<dynamic> response) {
    final value = response.headers.value('etag');
    if (value == null || value.isEmpty) return null;
    return value.startsWith('W/') ? value.substring(2) : value;
  }
}

/// The result of checking one signed manifest.
enum SignatureStatus { valid, untrustedKey, badSignature, malformedKey }

/// Verifies Ed25519 signatures against [trustedKeys] (01 §3).
class SignatureVerifier {
  SignatureVerifier(this.keys);

  final Map<String, String> keys;
  final Ed25519 _algorithm = Ed25519();

  Future<SignatureStatus> verify(SignedManifest envelope) async {
    final publicKey = keys[envelope.keyId];
    if (publicKey == null) return SignatureStatus.untrustedKey;

    final List<int> message;
    final List<int> signature;
    try {
      message = envelope.payloadBytes;
      signature = envelope.signatureBytes;
      if (signature.length != 64) return SignatureStatus.badSignature;
      final decodedKey = base64Decode(publicKey);
      if (decodedKey.length != 32) return SignatureStatus.malformedKey;
      final key = SimplePublicKey(decodedKey, type: KeyPairType.ed25519);
      final valid = await _algorithm.verify(
        message,
        signature: Signature(signature, publicKey: key),
      );
      return valid ? SignatureStatus.valid : SignatureStatus.badSignature;
    } on FormatException {
      return SignatureStatus.badSignature;
    }
  }
}

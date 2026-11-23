/// The update protocol types of `docs/plan/01-update-protocol.md`.
///
/// These are parsing-only models: no verification, no network, no state. The
/// manifest client checks the signature and expiry before these are used.
library;

import 'dart:convert';

/// Protocol version this build speaks (01 §1).
const int protocolVersion = 1;

const List<String> channelNames = ['stable', 'beta', 'internal'];

const List<String> platformNames = ['ios', 'android'];

/// Pack ids from 01 §1.1, the only ones the protocol allows.
const List<String> packIds = [
  'editions-manifest',
  'hafs-text',
  'riwayah-shubah-text',
  'riwayah-qalun-text',
  'hafs-layout-1405',
  'mapping-hafs-qalun',
  'qiraat-farsh',
  'published-differences',
  'navigation-hizbs',
];

/// Localised user-facing text; Arabic is mandatory (01 §2.2).
class LocalizedText {
  const LocalizedText({required this.ar});

  factory LocalizedText.fromJson(Map<String, dynamic> json) {
    final ar = json['ar'];
    if (ar is! String || ar.trim().isEmpty) {
      throw const FormatException('Localized text requires a non-empty "ar"');
    }
    return LocalizedText(ar: ar);
  }

  final String ar;

  @override
  String toString() => ar;
}

/// One file of a pack, as listed in the manifest (01 §2.2).
class PackFile {
  const PackFile({
    required this.path,
    required this.url,
    required this.sha256,
    required this.size,
  });

  factory PackFile.fromJson(Map<String, dynamic> json) {
    final path = json['path'];
    if (path is! String || path.isEmpty) {
      throw const FormatException('Pack file has no path');
    }
    if (path.startsWith('/') || path.contains('..')) {
      throw FormatException('Pack file path escapes the pack: $path');
    }
    final sha256 = json['sha256'];
    if (sha256 is! String || !RegExp(r'^[0-9a-f]{64}$').hasMatch(sha256)) {
      throw FormatException('Pack file has an invalid sha256: $path');
    }
    final size = json['size'];
    if (size is! int || size < 0) {
      throw FormatException('Pack file has an invalid size: $path');
    }
    return PackFile(
      path: path,
      url: Uri.parse(json['url'] as String),
      sha256: sha256,
      size: size,
    );
  }

  final String path;
  final Uri url;
  final String sha256;
  final int size;
}

/// The source a pack version was built from (01 §2.2).
class PackSource {
  const PackSource({required this.name, required this.revision});

  factory PackSource.fromJson(Map<String, dynamic> json) => PackSource(
    name: json['name'] as String,
    revision: json['revision'] as String,
  );

  final String name;
  final String revision;
}

/// The newest published version of one pack for this build (01 §2.2).
class PackRelease {
  const PackRelease({
    required this.packId,
    required this.version,
    required this.format,
    required this.files,
    this.source,
    this.notes,
  });

  factory PackRelease.fromJson(Map<String, dynamic> json) => PackRelease(
    packId: json['packId'] as String,
    version: json['version'] as int,
    format: json['format'] as String,
    source: json['source'] == null
        ? null
        : PackSource.fromJson(json['source'] as Map<String, dynamic>),
    notes: json['notes'] == null
        ? null
        : LocalizedText.fromJson(json['notes'] as Map<String, dynamic>),
    files: [
      for (final file in json['files'] as List<dynamic>)
        PackFile.fromJson(file as Map<String, dynamic>),
    ],
  );

  final String packId;
  final int version;
  final String format;
  final PackSource? source;
  final LocalizedText? notes;
  final List<PackFile> files;

  /// The file matching [path], if the pack ships it.
  PackFile? file(String path) {
    for (final candidate in files) {
      if (candidate.path == path) return candidate;
    }
    return null;
  }
}

/// A withdrawn pack version (01 §2.2).
class RevokedVersion {
  const RevokedVersion({required this.packId, required this.version});

  factory RevokedVersion.fromJson(Map<String, dynamic> json) => RevokedVersion(
    packId: json['packId'] as String,
    version: json['version'] as int,
  );

  final String packId;
  final int version;
}

/// The app policy for this build and channel (01 §2.2).
class AppPolicy {
  const AppPolicy({
    required this.latestBuild,
    required this.minSupportedBuild,
    required this.storeUrl,
    this.message,
  });

  factory AppPolicy.fromJson(Map<String, dynamic> json) => AppPolicy(
    latestBuild: json['latestBuild'] as int,
    minSupportedBuild: json['minSupportedBuild'] as int,
    storeUrl: Uri.parse(json['storeUrl'] as String),
    message: json['message'] == null
        ? null
        : LocalizedText.fromJson(json['message'] as Map<String, dynamic>),
  );

  final int latestBuild;
  final int minSupportedBuild;
  final Uri storeUrl;
  final LocalizedText? message;
}

/// A server announcement (01 §2.2).
class Announcement {
  const Announcement({
    required this.id,
    required this.title,
    required this.body,
    required this.startsAt,
    required this.endsAt,
    required this.priority,
    this.url,
  });

  factory Announcement.fromJson(Map<String, dynamic> json) => Announcement(
    id: json['id'] as String,
    title: LocalizedText.fromJson(json['title'] as Map<String, dynamic>),
    body: LocalizedText.fromJson(json['body'] as Map<String, dynamic>),
    url: json['url'] == null ? null : Uri.parse(json['url'] as String),
    startsAt: DateTime.parse(json['startsAt'] as String),
    endsAt: DateTime.parse(json['endsAt'] as String),
    priority: json['priority'] as String,
  );

  final String id;
  final LocalizedText title;
  final LocalizedText body;
  final Uri? url;
  final DateTime startsAt;
  final DateTime endsAt;
  final String priority;

  bool isActiveAt(DateTime now) =>
      !now.isBefore(startsAt) && now.isBefore(endsAt);
}

/// The decoded manifest payload (01 §2.2).
class Manifest {
  const Manifest({
    required this.issuedAt,
    required this.expiresAt,
    required this.channel,
    required this.app,
    required this.packs,
    required this.revoked,
    required this.config,
    required this.announcements,
  });

  factory Manifest.fromJson(Map<String, dynamic> json) {
    final protocol = json['protocol'];
    if (protocol != protocolVersion) {
      throw FormatException('Unsupported manifest protocol: $protocol');
    }
    return Manifest(
      issuedAt: DateTime.parse(json['issuedAt'] as String),
      expiresAt: DateTime.parse(json['expiresAt'] as String),
      channel: json['channel'] as String,
      app: AppPolicy.fromJson(json['app'] as Map<String, dynamic>),
      packs: [
        for (final pack in json['packs'] as List<dynamic>)
          PackRelease.fromJson(pack as Map<String, dynamic>),
      ],
      revoked: [
        for (final revoked in json['revoked'] as List<dynamic>)
          RevokedVersion.fromJson(revoked as Map<String, dynamic>),
      ],
      config: (json['config'] as Map<String, dynamic>?) ?? const {},
      announcements: [
        for (final announcement in json['announcements'] as List<dynamic>)
          Announcement.fromJson(announcement as Map<String, dynamic>),
      ],
    );
  }

  final DateTime issuedAt;
  final DateTime expiresAt;
  final String channel;
  final AppPolicy app;
  final List<PackRelease> packs;
  final List<RevokedVersion> revoked;
  final Map<String, dynamic> config;
  final List<Announcement> announcements;

  /// Whether the manifest may still be used to download new packs (01 §2.2).
  bool isExpiredAt(DateTime now) => !now.isBefore(expiresAt);

  /// The release for [packId], if the server offers one.
  PackRelease? release(String packId) {
    for (final pack in packs) {
      if (pack.packId == packId) return pack;
    }
    return null;
  }

  bool isRevoked(String packId, int version) => revoked.any(
    (entry) => entry.packId == packId && entry.version == version,
  );

  /// Announcements that are active at [now], in server order.
  List<Announcement> activeAnnouncements(DateTime now) => [
    for (final announcement in announcements)
      if (announcement.isActiveAt(now)) announcement,
  ];
}

/// The signed envelope the server returns (01 §2.2).
///
/// [payload] is the manifest JSON exactly as signed; [signature] must be
/// verified against those bytes before [decodePayload] is called.
class SignedManifest {
  const SignedManifest({
    required this.keyId,
    required this.payload,
    required this.signature,
  });

  factory SignedManifest.fromJson(Map<String, dynamic> json) {
    final keyId = json['keyId'];
    final payload = json['payload'];
    final signature = json['signature'];
    if (keyId is! String || keyId.isEmpty) {
      throw const FormatException('Signed manifest has no keyId');
    }
    if (payload is! String || payload.isEmpty) {
      throw const FormatException('Signed manifest has no payload');
    }
    if (signature is! String || signature.isEmpty) {
      throw const FormatException('Signed manifest has no signature');
    }
    return SignedManifest(
      keyId: keyId,
      payload: payload,
      signature: signature,
    );
  }

  final String keyId;

  /// Base64 of the UTF-8 JSON bytes that were signed.
  final String payload;

  /// Base64 of the Ed25519 signature over the decoded [payload] bytes.
  final String signature;

  List<int> get payloadBytes => base64Decode(payload);

  List<int> get signatureBytes => base64Decode(signature);

  /// Decodes the signed payload. Only call after the signature is verified.
  Manifest decodePayload() => Manifest.fromJson(
    jsonDecode(utf8.decode(payloadBytes)) as Map<String, dynamic>,
  );
}

/// A manifest error as defined by 01 §2.3.
class ManifestError {
  const ManifestError({required this.code, required this.message});

  factory ManifestError.fromJson(Map<String, dynamic> json) {
    final error = json['error'] as Map<String, dynamic>;
    return ManifestError(
      code: error['code'] as String,
      message: error['message'] as String,
    );
  }

  final String code;
  final String message;
}

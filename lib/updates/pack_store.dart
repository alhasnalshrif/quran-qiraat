/// On-disk pack storage (03 §4):
///
/// ```
/// <root>/
/// ├── state.json          active/previous/pending versions per pack
/// ├── qiraat-farsh/2/…    unpacked pack versions, at most two per pack
/// └── .incoming/          in-flight downloads, wiped on start
/// ```
///
/// `state.json` is written atomically (temp file then rename), and the newest
/// version is only activated after its files validated.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'pack_validators.dart';
import 'protocol.dart';

/// The persisted `state.json` (03 §4).
class PackStoreState {
  const PackStoreState({
    this.active = const {},
    this.previous = const {},
    this.pending = const {},
    this.lastError,
  });

  factory PackStoreState.fromJson(Map<String, dynamic> json) => PackStoreState(
    active: _versionMap(json['active']),
    previous: _versionMap(json['previous']),
    pending: _versionMap(json['pending']),
    lastError: json['lastError'] as String?,
  );

  final Map<String, int> active;
  final Map<String, int> previous;
  final Map<String, int> pending;
  final String? lastError;

  Map<String, dynamic> toJson() => {
    'active': active,
    'previous': previous,
    'pending': pending,
    if (lastError != null) 'lastError': lastError,
  };

  PackStoreState copyWith({
    Map<String, int>? active,
    Map<String, int>? previous,
    Map<String, int>? pending,
    String? lastError,
    bool clearError = false,
  }) => PackStoreState(
    active: active ?? this.active,
    previous: previous ?? this.previous,
    pending: pending ?? this.pending,
    lastError: clearError ? null : (lastError ?? this.lastError),
  );

  static Map<String, int> _versionMap(Object? raw) {
    if (raw is! Map) return const {};
    return {
      for (final entry in raw.entries)
        if (entry.key is String && entry.value is int)
          entry.key as String: entry.value as int,
    };
  }
}

/// One file of a pack version on disk.
class StoredFile {
  const StoredFile({
    required this.path,
    required this.sha256,
    required this.size,
  });

  final String path;
  final String sha256;
  final int size;

  PackFile get asPackFile => PackFile(
    path: path,
    url: Uri.parse('file:///$path'),
    sha256: sha256,
    size: size,
  );
}

/// A downloaded, validated pack version waiting in `.incoming`.
class DownloadedPack {
  const DownloadedPack({
    required this.release,
    required this.directory,
  });

  final PackRelease release;
  final Directory directory;
}

/// Downloads, validates, activates and withdraws pack versions (03 §4–§5).
class PackStore {
  PackStore({
    required this.root,
    Future<Directory> Function()? supportDirectory,
    this.fetchFile,
    this.validators = validateFormatJson,
  });

  final Directory root;

  /// How a pack file is fetched; the update service wires this to Dio so tests
  /// can supply bytes without a network.
  final Future<List<int>> Function(PackFile file)? fetchFile;

  /// Runs the format validator for the pack (defaults to [validateFormatJson]).
  final ValidationResult Function(String format, String source) validators;

  PackStoreState _state = const PackStoreState();
  bool _loaded = false;

  Directory get incoming => Directory('${root.path}/.incoming');
  File get stateFile => File('${root.path}/state.json');

  PackStoreState get state => _state;

  /// The version [packId] is reading, if a downloaded one is active.
  int? activeVersion(String packId) => _state.active[packId];

  /// The version to fall back to if the active one fails, if any.
  int? previousVersion(String packId) => _state.previous[packId];

  /// Loads `state.json`, wiping any leftover `.incoming` directory.
  Future<void> load() async {
    await root.create(recursive: true);
    if (await incoming.exists()) {
      await incoming.delete(recursive: true);
    }
    final file = stateFile;
    if (await file.exists()) {
      try {
        _state = PackStoreState.fromJson(
          jsonDecode(await file.readAsString()) as Map<String, dynamic>,
        );
      } on FormatException {
        _state = const PackStoreState();
      }
    }
    _loaded = true;
  }

  Directory versionDirectory(String packId, int version) =>
      Directory('${root.path}/$packId/$version');

  /// Downloads every file of [release] into `.incoming`, checking size and
  /// sha256, then runs the pack's validator. Returns null and records the error
  /// on any failure, leaving no partial directory behind (03 §5 steps 8–10).
  Future<DownloadedPack?> download(PackRelease release) async {
    final fetch = fetchFile;
    if (fetch == null) {
      return _fail('no file fetcher configured for ${release.packId}');
    }
    final staging = Directory('${incoming.path}/${release.packId}-${release.version}');
    try {
      if (await staging.exists()) await staging.delete(recursive: true);
      await staging.create(recursive: true);

      for (final file in release.files) {
        final bytes = await fetch(file);
        if (bytes.length != file.size) {
          return await _failAndClean(
            staging,
            'size mismatch for ${file.path}: ${bytes.length} != ${file.size}',
          );
        }
        final digest = sha256.convert(bytes).toString();
        if (digest != file.sha256.toLowerCase()) {
          return await _failAndClean(
            staging,
            'sha256 mismatch for ${file.path}',
          );
        }
        final target = File('${staging.path}/${file.path}');
        await target.parent.create(recursive: true);
        await target.writeAsBytes(bytes, flush: true);
      }

      final primary = release.files.firstWhere(
        (file) => file.path.endsWith('.json'),
        orElse: () => release.files.first,
      );
      final primaryFile = File('${staging.path}/${primary.path}');
      if (await primaryFile.exists()) {
        final result = validators(release.format, await primaryFile.readAsString());
        if (!result.ok) {
          return await _failAndClean(
            staging,
            'validator rejected ${release.packId}: ${result.errors.join('; ')}',
          );
        }
      }

      return DownloadedPack(release: release, directory: staging);
    } on Object catch (error) {
      return await _failAndClean(staging, '$error');
    }
  }

  /// Moves a validated download into `packs/<id>/<version>/` and records it as
  /// pending (03 §5 step 10).
  Future<void> stage(DownloadedPack download) async {
    final release = download.release;
    final target = versionDirectory(release.packId, release.version);
    await target.parent.create(recursive: true);
    if (await target.exists()) await target.delete(recursive: true);
    await download.directory.rename(target.path);
    _state = _state.copyWith(
      pending: {..._state.pending, release.packId: release.version},
    );
    await _save();
  }

  /// Makes a pending version active and forgets the over-older one (D8).
  Future<void> activate(String packId) async {
    final version = _state.pending[packId];
    if (version == null) return;
    final previous = _state.active[packId];
    final active = {..._state.active, packId: version};
    final prev = {..._state.previous};
    if (previous != null && previous != version) {
      prev[packId] = previous;
    } else {
      prev.remove(packId);
    }
    _state = _state.copyWith(
      active: active,
      previous: prev,
      pending: {..._state.pending}..remove(packId),
      clearError: true,
    );
    await _save();
    await _prune(packId);
  }

  /// Activates every pending version (D8: on the next launch).
  Future<void> activatePending() async {
    for (final packId in [..._state.pending.keys]) {
      await activate(packId);
    }
  }

  /// Deactivates [packId], returning to the previous version if there is one,
  /// then the bundled copy.
  Future<void> withdraw(String packId) async {
    final active = {..._state.active}..remove(packId);
    final pending = {..._state.pending}..remove(packId);
    final previous = _state.previous[packId];
    final prev = {..._state.previous};
    if (previous != null) {
      active[packId] = previous;
      prev.remove(packId);
    }
    _state = _state.copyWith(active: active, pending: pending, previous: prev);
    await _save();
  }

  /// Disables every downloaded pack and returns to the bundled copies.
  Future<void> resetAll() async {
    final packDirectories = [
      for (final entity in await root.list().toList())
        if (entity is Directory &&
            !entity.path.endsWith('.incoming'))
          entity,
    ];
    _state = const PackStoreState();
    await _save();
    for (final directory in packDirectories) {
      await directory.delete(recursive: true);
    }
  }

  /// Reads a file from the active version of [packId], or null if absent.
  Future<String?> readActive(String packId, String path) async {
    final version = _state.active[packId];
    if (version == null) return null;
    final file = File('${versionDirectory(packId, version).path}/$path');
    if (!await file.exists()) return null;
    return file.readAsString();
  }

  /// Byte length of a file in the active version, or null.
  Future<List<int>?> readActiveBytes(String packId, String path) async {
    final version = _state.active[packId];
    if (version == null) return null;
    final file = File('${versionDirectory(packId, version).path}/$path');
    if (!await file.exists()) return null;
    return file.readAsBytes();
  }

  /// Marks the active version of [packId] as broken and falls back (03 §5).
  ///
  /// Returns true if the caller should reload because the active version changed.
  Future<bool> markBroken(String packId) async {
    final active = _state.active[packId];
    if (active == null) return false;
    final versionDirectory_ = versionDirectory(packId, active);
    if (await versionDirectory_.exists()) {
      await versionDirectory_.delete(recursive: true);
    }
    await withdraw(packId);
    _state = _state.copyWith(
      lastError: 'pack $packId v$active failed to load and was disabled',
    );
    await _save();
    return true;
  }

  /// Files stored for the active version, for the sources screen.
  Future<List<StoredFile>> activeFiles(String packId) async {
    final version = _state.active[packId];
    if (version == null) return const [];
    final directory = versionDirectory(packId, version);
    if (!await directory.exists()) return const [];
    final files = <StoredFile>[];
    await for (final entity in directory.list(recursive: true)) {
      if (entity is! File) continue;
      final bytes = await entity.readAsBytes();
      files.add(
        StoredFile(
          path: entity.path.substring(directory.path.length + 1),
          sha256: sha256.convert(bytes).toString(),
          size: bytes.length,
        ),
      );
    }
    return files;
  }

  Future<void> _prune(String packId) async {
    final keep = {
      _state.active[packId],
      _state.previous[packId],
      _state.pending[packId],
    }..remove(null);
    final directory = Directory('${root.path}/$packId');
    if (!await directory.exists()) return;
    await for (final entity in directory.list()) {
      if (entity is! Directory) continue;
      final name = entity.path.split(Platform.pathSeparator).last;
      final version = int.tryParse(name);
      if (version != null && !keep.contains(version)) {
        await entity.delete(recursive: true);
      }
    }
  }

  Future<DownloadedPack?> _failAndClean(Directory staging, String message) async {
    if (await staging.exists()) await staging.delete(recursive: true);
    return _fail(message);
  }

  Future<DownloadedPack?> _fail(String message) async {
    _state = _state.copyWith(lastError: message);
    await _save();
    return null;
  }

  /// Writes `state.json` atomically: temporary file, then rename (03 §4).
  Future<void> _save() async {
    if (!_loaded) return;
    await root.create(recursive: true);
    final temp = File('${stateFile.path}.tmp');
    await temp.writeAsString(jsonEncode(_state.toJson()), flush: true);
    await temp.rename(stateFile.path);
  }
}

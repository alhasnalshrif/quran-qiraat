import 'package:flutter/services.dart';

import 'pack_store.dart';

enum PackSourceKind { bundled, downloaded }

class PackState {
  const PackState({
    required this.packId,
    required this.version,
    required this.sourceKind,
  });

  final String packId;
  final int version;
  final PackSourceKind sourceKind;

  @override
  String toString() => 'PackState($packId: v$version ($sourceKind))';

  @override
  bool operator ==(Object other) =>
      other is PackState &&
      other.packId == packId &&
      other.version == version &&
      other.sourceKind == sourceKind;

  @override
  int get hashCode => Object.hash(packId, version, sourceKind);
}

abstract interface class QuranDataSource {
  /// يعيد نص ملف من حزمة، من الإصدار المفعّل إن وُجد وإلا المضمّن.
  Future<String> loadString(String packId, String path, {bool cache = true});
  Future<ByteData> load(String packId, String path);

  /// الإصدار المستخدم فعلًا لكل حزمة، للعرض في شاشة المصادر.
  Map<String, PackState> get states;
}

class BundledDataSource implements QuranDataSource {
  const BundledDataSource();

  static const Map<String, String> _bundledBases = {
    'editions-manifest': 'assets/',
    'hafs-text': 'assets/',
    'riwayah-shubah-text': 'assets/',
    'riwayah-qalun-text': 'assets/',
    'hafs-layout-1405': 'assets/mushaf/layout/',
    'mapping-hafs-qalun': 'assets/mappings/',
    'qiraat-farsh': 'assets/qiraat/',
    'published-differences': 'assets/',
    'navigation-hizbs': 'assets/navigation/',
  };

  static String bundledAssetPath(String packId, String path) {
    final base = _bundledBases[packId];
    if (base == null) {
      throw ArgumentError('Unknown bundled packId: $packId');
    }
    if (path.startsWith(base)) {
      return path;
    }
    final stripped = path.startsWith('assets/') ? path.substring('assets/'.length) : path;
    final filename = stripped.split('/').last;
    return '$base$filename';
  }

  @override
  Future<String> loadString(
    String packId,
    String path, {
    bool cache = true,
  }) {
    final asset = bundledAssetPath(packId, path);
    return rootBundle.loadString(asset, cache: cache);
  }

  @override
  Future<ByteData> load(String packId, String path) {
    final asset = bundledAssetPath(packId, path);
    return rootBundle.load(asset);
  }

  @override
  Map<String, PackState> get states => {
    for (final packId in _bundledBases.keys)
      packId: PackState(
        packId: packId,
        version: 1,
        sourceKind: PackSourceKind.bundled,
      ),
  };
}

/// Reads from an active downloaded pack, falling back to [BundledDataSource]
/// for any pack without an active version (03 §3).
class PackedDataSource implements QuranDataSource {
  PackedDataSource({required this.store, this.bundled = const BundledDataSource()});

  final PackStore store;
  final BundledDataSource bundled;

  @override
  Future<String> loadString(
    String packId,
    String path, {
    bool cache = true,
  }) async {
    final stored = await store.readActive(packId, path);
    if (stored != null) return stored;
    return bundled.loadString(packId, path, cache: cache);
  }

  @override
  Future<ByteData> load(String packId, String path) async {
    final bytes = await store.readActiveBytes(packId, path);
    if (bytes != null) return ByteData.sublistView(Uint8List.fromList(bytes));
    return bundled.load(packId, path);
  }

  @override
  Map<String, PackState> get states {
    final result = <String, PackState>{...bundled.states};
    for (final entry in store.state.active.entries) {
      result[entry.key] = PackState(
        packId: entry.key,
        version: entry.value,
        sourceKind: PackSourceKind.downloaded,
      );
    }
    return result;
  }
}

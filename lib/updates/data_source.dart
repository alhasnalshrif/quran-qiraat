import 'package:flutter/services.dart';

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

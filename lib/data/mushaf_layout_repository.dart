import '../domain/models/mushaf_layout.dart';
import '../updates/data_source.dart';

abstract final class MushafLayoutRepository {
  static const hafsPackId = 'hafs-layout-1405';
  static const hafsAsset = 'hafs_madani_604.json';

  static Future<MushafLayout> loadHafsMadani604({
    QuranDataSource source = const BundledDataSource(),
  }) async =>
      MushafLayout.fromJsonString(
        await source.loadString(hafsPackId, hafsAsset),
      );
}

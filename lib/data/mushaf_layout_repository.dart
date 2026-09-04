import 'package:flutter/services.dart';

import '../domain/models/mushaf_layout.dart';

abstract final class MushafLayoutRepository {
  static const hafsAsset = 'assets/mushaf/layout/hafs_madani_604.json';

  static Future<MushafLayout> loadHafsMadani604() async =>
      MushafLayout.fromJsonString(await rootBundle.loadString(hafsAsset));
}

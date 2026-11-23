enum MarginRiwayah { shubah, qalun }

enum QuranReading { hafs, shubah, qalun }

extension QuranReadingData on QuranReading {
  String get title => switch (this) {
    QuranReading.hafs => 'حفص عن عاصم',
    QuranReading.shubah => 'شعبة عن عاصم',
    QuranReading.qalun => 'قالون عن نافع',
  };

  String get shortTitle => switch (this) {
    QuranReading.hafs => 'حفص',
    QuranReading.shubah => 'شعبة',
    QuranReading.qalun => 'قالون',
  };

  String get fontFamily => switch (this) {
    QuranReading.hafs => 'HafsSmart',
    QuranReading.shubah => 'Shubah',
    QuranReading.qalun => 'Qalun',
  };

  /// Hafs source glyphs use HafsSmart; layout and comparison text use Unicode.
  String get unicodeFontFamily =>
      this == QuranReading.hafs ? 'AmiriQuran' : fontFamily;

  /// Riwayah slug used by the Quran Tajweed Engine farsh.
  String get variantSlug => switch (this) {
    QuranReading.hafs => 'hafs',
    QuranReading.shubah => 'shubah',
    QuranReading.qalun => 'qaloon',
  };

  static QuranReading? fromVariantSlug(String slug) {
    for (final reading in QuranReading.values) {
      if (reading.variantSlug == slug) return reading;
    }
    return null;
  }

  MarginRiwayah? get differenceSource => switch (this) {
    QuranReading.hafs => null,
    QuranReading.shubah => MarginRiwayah.shubah,
    QuranReading.qalun => MarginRiwayah.qalun,
  };
}

extension MarginRiwayahData on MarginRiwayah {
  String get title => switch (this) {
    MarginRiwayah.shubah => 'مصحف حفص وبهامشه شعبة',
    MarginRiwayah.qalun => 'مصحف حفص وبهامشه قالون',
  };

  String get shortName => switch (this) {
    MarginRiwayah.shubah => 'شعبة عن عاصم',
    MarginRiwayah.qalun => 'قالون عن نافع',
  };

  String get storageKey => name;

  String get fontFamily => switch (this) {
    MarginRiwayah.shubah => 'Shubah',
    MarginRiwayah.qalun => 'Qalun',
  };

  QuranReading toReading() => switch (this) {
    MarginRiwayah.shubah => QuranReading.shubah,
    MarginRiwayah.qalun => QuranReading.qalun,
  };
}

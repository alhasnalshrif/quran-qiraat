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

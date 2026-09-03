enum MarginRiwayah { shubah, qalun }

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
}

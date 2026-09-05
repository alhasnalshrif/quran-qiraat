import 'margin_riwayah.dart';

class ReadingAyahRef {
  const ReadingAyahRef({
    required this.reading,
    required this.surah,
    required this.ayah,
  }) : assert(surah > 0 && surah <= 114),
       assert(ayah > 0);

  final QuranReading reading;
  final int surah;
  final int ayah;

  String get key => '$surah:$ayah';
}

/// A reviewed correspondence between independently numbered ayah spans.
/// Supports 1:1, 1:N, N:1 and N:M without borrowing another reading's IDs.
class AyahCorrespondence {
  AyahCorrespondence({
    required this.id,
    required this.base,
    required this.target,
    required this.source,
    this.reviewer,
  }) : assert(base.isNotEmpty),
       assert(target.isNotEmpty),
       assert(source.isNotEmpty);

  final String id;
  final List<ReadingAyahRef> base;
  final List<ReadingAyahRef> target;
  final String source;
  final String? reviewer;

  List<ReadingAyahRef> counterparts(ReadingAyahRef ref) {
    final inBase = base.any(
      (item) =>
          item.reading == ref.reading &&
          item.surah == ref.surah &&
          item.ayah == ref.ayah,
    );
    if (inBase) return target;
    final inTarget = target.any(
      (item) =>
          item.reading == ref.reading &&
          item.surah == ref.surah &&
          item.ayah == ref.ayah,
    );
    return inTarget ? base : const [];
  }
}

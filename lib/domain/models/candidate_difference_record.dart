import 'margin_riwayah.dart';

/// Represents a raw, unverified candidate difference locator from an external
/// or preliminary dataset (e.g. ad-Dānī at-Taysīr / Corpus Coranicum).
///
/// Strictly unaligned: this record does NOT assert a variant reading word span,
/// target word text, or performance-only classification. Such alignments must
/// only be established through qualified scholarly review in `ReadingDifference`.
class CandidateDifferenceRecord {
  const CandidateDifferenceRecord({
    required this.id,
    required this.sourceId,
    required this.sourceReading,
    required this.surah,
    required this.hafsAyah,
    this.hafsPage,
    required this.rawWordIndex,
    this.provenance = '',
    this.notes = '',
  });

  final String id;
  final String sourceId;
  final MarginRiwayah sourceReading;
  final int surah;
  final int hafsAyah;
  final int? hafsPage;
  final int rawWordIndex;
  final String provenance;
  final String notes;

  String get hafsAyahKey => '$surah:$hafsAyah';

  factory CandidateDifferenceRecord.fromJson(Map<String, dynamic> json) =>
      CandidateDifferenceRecord(
        id: json['id'] as String,
        sourceId: json['source_id'] as String? ?? 'differences_taisir',
        sourceReading: MarginRiwayah.values.firstWhere(
          (r) => r.name == json['source_reading'],
          orElse: () => MarginRiwayah.shubah,
        ),
        surah: json['surah'] as int,
        hafsAyah: json['hafs_ayah'] as int,
        hafsPage: json['hafs_page'] as int?,
        rawWordIndex: json['raw_word_index'] as int,
        provenance: json['provenance'] as String? ?? '',
        notes: json['notes'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'source_id': sourceId,
    'source_reading': sourceReading.name,
    'surah': surah,
    'hafs_ayah': hafsAyah,
    if (hafsPage != null) 'hafs_page': hafsPage,
    'raw_word_index': rawWordIndex,
    'provenance': provenance,
    'notes': notes,
  };
}

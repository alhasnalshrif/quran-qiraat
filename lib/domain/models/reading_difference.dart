import 'margin_riwayah.dart';
import 'reading_word_ref.dart';

enum DifferenceReviewStatus {
  /// Unreviewed candidate extracted from raw/external datasets.
  /// Kept for internal tooling and development; must NOT be displayed to end users.
  candidate,

  /// Vetted and approved by qualified scholars for public display.
  published,

  /// Inspected and deemed not a genuine reading difference (e.g. pure Unicode encoding noise).
  rejected,
}

enum AlignmentCardinality {
  /// 1 word in base aligns to 1 word in variant.
  oneToOne,

  /// 1 word in base aligns to multiple words in variant (1:N).
  oneToMany,

  /// Multiple words in base align to 1 word in variant (N:1).
  manyToOne,

  /// Multiple words in base align to multiple words in variant (N:M).
  manyToMany,
}

/// Represents a review-aware, span-aligned difference between two Quran readings.
///
/// Encapsulates scholarly vetting status, exact word spans in each reading's
/// independent numbering, cardinality (1:1, 1:N, N:1), and performance/orthography flags.
class ReadingDifference {
  ReadingDifference({
    required this.id,
    required this.baseReading,
    required this.targetReading,
    required this.baseSpan,
    required this.targetSpan,
    required this.reviewStatus,
    this.isPerformanceOnly = false,
    this.scholarlyNotes,
    this.reviewer,
    this.reviewDate,
  }) {
    if (id.trim().isEmpty ||
        baseReading == targetReading ||
        baseSpan.reading != baseReading ||
        targetSpan.reading != targetReading) {
      throw const FormatException(
        'Invalid reading difference identity or readings.',
      );
    }
    baseSpan.validate();
    targetSpan.validate();
    if (isPublished &&
        ((reviewer?.trim().isEmpty ?? true) || reviewDate == null)) {
      throw const FormatException(
        'Published differences require reviewer and valid review_date.',
      );
    }
  }

  final String id;
  final QuranReading baseReading;
  final QuranReading targetReading;
  final ReadingWordSpan baseSpan;
  final ReadingWordSpan targetSpan;
  final DifferenceReviewStatus reviewStatus;
  final bool isPerformanceOnly;
  final String? scholarlyNotes;
  final String? reviewer;
  final DateTime? reviewDate;

  bool get isPublished => reviewStatus == DifferenceReviewStatus.published;
  bool get isCandidate => reviewStatus == DifferenceReviewStatus.candidate;

  AlignmentCardinality get cardinality {
    final baseCount = baseSpan.wordCount;
    final targetCount = targetSpan.wordCount;
    if (baseCount == 1 && targetCount == 1) {
      return AlignmentCardinality.oneToOne;
    }
    if (baseCount == 1 && targetCount > 1) {
      return AlignmentCardinality.oneToMany;
    }
    if (baseCount > 1 && targetCount == 1) {
      return AlignmentCardinality.manyToOne;
    }
    return AlignmentCardinality.manyToMany;
  }

  bool get isOneToOne => cardinality == AlignmentCardinality.oneToOne;
  bool get isOneToMany => cardinality == AlignmentCardinality.oneToMany;
  bool get isManyToOne => cardinality == AlignmentCardinality.manyToOne;

  factory ReadingDifference.published({
    required String id,
    QuranReading baseReading = QuranReading.hafs,
    required QuranReading targetReading,
    required ReadingWordSpan baseSpan,
    required ReadingWordSpan targetSpan,
    bool isPerformanceOnly = false,
    String? scholarlyNotes,
    String? reviewer,
    DateTime? reviewDate,
  }) => ReadingDifference(
    id: id,
    baseReading: baseReading,
    targetReading: targetReading,
    baseSpan: baseSpan,
    targetSpan: targetSpan,
    reviewStatus: DifferenceReviewStatus.published,
    isPerformanceOnly: isPerformanceOnly,
    scholarlyNotes: scholarlyNotes,
    reviewer: reviewer,
    reviewDate: reviewDate,
  );

  factory ReadingDifference.candidate({
    required String id,
    QuranReading baseReading = QuranReading.hafs,
    required QuranReading targetReading,
    required ReadingWordSpan baseSpan,
    required ReadingWordSpan targetSpan,
    bool isPerformanceOnly = false,
    String? scholarlyNotes,
  }) => ReadingDifference(
    id: id,
    baseReading: baseReading,
    targetReading: targetReading,
    baseSpan: baseSpan,
    targetSpan: targetSpan,
    reviewStatus: DifferenceReviewStatus.candidate,
    isPerformanceOnly: isPerformanceOnly,
    scholarlyNotes: scholarlyNotes,
  );

  factory ReadingDifference.fromJson(Map<String, dynamic> json) {
    final baseReadingName = json['base_reading'] as String? ?? 'hafs';
    final targetReadingName = json['target_reading'] as String;
    final statusName =
        json['review_status'] as String? ??
        DifferenceReviewStatus.candidate.name;

    final reviewer = json['reviewer'] as String?;
    final reviewDate = json['review_date'] != null
        ? _parseReviewDate(json['review_date'] as String)
        : null;
    final reviewStatus = _parseReviewStatus(statusName);
    if (reviewStatus == DifferenceReviewStatus.published &&
        ((reviewer?.trim().isEmpty ?? true) || reviewDate == null)) {
      throw const FormatException(
        'Published differences require reviewer and valid review_date.',
      );
    }

    return ReadingDifference(
      id: json['id'] as String,
      baseReading: _parseReading(baseReadingName),
      targetReading: _parseReading(targetReadingName),
      baseSpan: ReadingWordSpan.fromJson(
        json['base_span'] as Map<String, dynamic>,
      ),
      targetSpan: ReadingWordSpan.fromJson(
        json['target_span'] as Map<String, dynamic>,
      ),
      reviewStatus: reviewStatus,
      isPerformanceOnly: json['is_performance_only'] as bool? ?? false,
      scholarlyNotes: json['scholarly_notes'] as String?,
      reviewer: reviewer,
      reviewDate: reviewDate,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'base_reading': baseReading.name,
    'target_reading': targetReading.name,
    'base_span': baseSpan.toJson(),
    'target_span': targetSpan.toJson(),
    'review_status': reviewStatus.name,
    'is_performance_only': isPerformanceOnly,
    if (scholarlyNotes != null) 'scholarly_notes': scholarlyNotes,
    if (reviewer != null) 'reviewer': reviewer,
    if (reviewDate != null) 'review_date': reviewDate!.toIso8601String(),
  };
}

DateTime? _parseReviewDate(String value) {
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})(?:T|$)').firstMatch(value);
  if (match == null) return null;
  final year = int.parse(match[1]!);
  final month = int.parse(match[2]!);
  final day = int.parse(match[3]!);
  final date = DateTime.utc(year, month, day);
  if (date.year != year || date.month != month || date.day != day) return null;
  return DateTime.tryParse(value);
}

QuranReading _parseReading(String name) {
  for (final reading in QuranReading.values) {
    if (reading.name == name) return reading;
  }
  throw FormatException('Unknown Quran reading: $name');
}

DifferenceReviewStatus _parseReviewStatus(String name) {
  for (final status in DifferenceReviewStatus.values) {
    if (status.name == name) return status;
  }
  throw FormatException('Unknown difference review status: $name');
}

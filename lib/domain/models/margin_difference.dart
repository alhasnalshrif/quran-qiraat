import 'ayah.dart';
import 'reading_difference.dart';

class MarginDifference {
  const MarginDifference({
    required this.hafs,
    required this.variant,
    required this.wordIndexes,
    this.difference,
  });

  final Ayah hafs;
  final Ayah variant;
  final List<int> wordIndexes;
  final ReadingDifference? difference;
}

class WordComparison {
  const WordComparison({
    required this.hafs,
    required this.variant,
    required this.isPerformanceOnly,
    this.scholarlyNotes,
    this.cardinality,
  });

  final String hafs;
  final String variant;
  final bool isPerformanceOnly;
  final String? scholarlyNotes;
  final AlignmentCardinality? cardinality;

  factory WordComparison.fromReadingDifference(ReadingDifference diff) =>
      WordComparison(
        hafs: diff.baseSpan.text,
        variant: diff.targetSpan.text,
        isPerformanceOnly: diff.isPerformanceOnly,
        scholarlyNotes: diff.scholarlyNotes,
        cardinality: diff.cardinality,
      );
}

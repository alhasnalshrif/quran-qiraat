import 'ayah.dart';

class MarginDifference {
  const MarginDifference({
    required this.hafs,
    required this.variant,
    required this.wordIndexes,
  });

  final Ayah hafs;
  final Ayah variant;
  final List<int> wordIndexes;
}

class WordComparison {
  const WordComparison({
    required this.hafs,
    required this.variant,
    required this.isPerformanceOnly,
  });

  final String hafs;
  final String variant;
  final bool isPerformanceOnly;
}

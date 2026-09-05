import 'dart:convert';

import '../models/alignment_review_record.dart';
import '../models/reading_alignment.dart';
import 'reading_alignment_engine.dart';

class AlignmentReviewPipeline {
  const AlignmentReviewPipeline({this.engine = const ReadingAlignmentEngine()});

  final ReadingAlignmentEngine engine;

  AlignmentReviewRecord propose(ExplicitAyahPair pair) {
    final proposal = engine.align(pair);
    return AlignmentReviewRecord(
      id:
          '${pair.baseReading.name}-${pair.baseSurah}-${pair.baseAyah}-'
          '${pair.targetReading.name}-${pair.targetSurah}-${pair.targetAyah}',
      proposal: proposal,
    );
  }

  String encodeQueue(Iterable<AlignmentReviewRecord> records) => jsonEncode({
    'schema_version': '1.0.0',
    'status': 'review_only',
    'records': [for (final record in records) record.toJson()],
  });
}

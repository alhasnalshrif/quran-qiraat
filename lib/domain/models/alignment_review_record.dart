import 'reading_alignment.dart';

enum AlignmentReviewStatus { pending, approved, rejected }

class AlignmentReviewRecord {
  const AlignmentReviewRecord({
    required this.id,
    required this.proposal,
    this.status = AlignmentReviewStatus.pending,
    this.reviewer,
    this.reviewedAt,
  });

  final String id;
  final AyahAlignmentProposal proposal;
  final AlignmentReviewStatus status;
  final String? reviewer;
  final DateTime? reviewedAt;

  double get confidence {
    if (proposal.alignments.isEmpty) return 1;
    return proposal.alignments
        .map((alignment) => alignment.score)
        .reduce((left, right) => left < right ? left : right);
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'status': status.name,
    'confidence': confidence,
    'base': {
      'reading': proposal.pair.baseReading.name,
      'surah': proposal.pair.baseSurah,
      'ayah_start': proposal.pair.baseAyah,
      'ayah_end': proposal.pair.baseAyahEnd ?? proposal.pair.baseAyah,
    },
    'target': {
      'reading': proposal.pair.targetReading.name,
      'surah': proposal.pair.targetSurah,
      'ayah_start': proposal.pair.targetAyah,
      'ayah_end': proposal.pair.targetAyahEnd ?? proposal.pair.targetAyah,
    },
    'alignments': [
      for (final alignment in proposal.alignments)
        {
          'base_words': [
            for (final token in alignment.baseTokens)
              {'index': token.index, 'text': token.text},
          ],
          'target_words': [
            for (final token in alignment.targetTokens)
              {'index': token.index, 'text': token.text},
          ],
          'kind': alignment.kind.name,
          'score': alignment.score,
          'character_edits': [
            for (final edit in alignment.characterEdits)
              {
                'kind': edit.kind.name,
                if (edit.baseText != null) 'base': edit.baseText,
                if (edit.targetText != null) 'target': edit.targetText,
              },
          ],
        },
    ],
    if (reviewer != null) 'reviewer': reviewer,
    if (reviewedAt != null) 'reviewed_at': reviewedAt!.toIso8601String(),
  };
}

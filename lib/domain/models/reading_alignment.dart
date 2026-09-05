import 'margin_riwayah.dart';

/// The kind of change found after two explicitly paired spans are aligned.
enum TextDifferenceKind {
  identical,
  diacriticsOnly,
  letters,
  insertion,
  deletion,
}

enum CharacterEditKind { keep, insert, delete, substitute }

class CharacterEdit {
  const CharacterEdit({required this.kind, this.baseText, this.targetText});

  final CharacterEditKind kind;
  final String? baseText;
  final String? targetText;
}

/// A word produced from one reading's own text and numbering.
class ReadingToken {
  const ReadingToken({required this.index, required this.text});

  final int index;
  final String text;
}

/// One proposed word-span correspondence produced by the automatic engine.
///
/// This is deliberately not a [ReadingDifference]: automatic alignment is
/// evidence for review, not a publishable qira'at assertion.
class ProposedWordAlignment {
  const ProposedWordAlignment({
    required this.baseTokens,
    required this.targetTokens,
    required this.kind,
    required this.score,
    this.characterEdits = const [],
  });

  final List<ReadingToken> baseTokens;
  final List<ReadingToken> targetTokens;
  final TextDifferenceKind kind;

  /// A normalized similarity in the inclusive range 0..1.
  final double score;
  final List<CharacterEdit> characterEdits;

  bool get isDifference => kind != TextDifferenceKind.identical;
}

/// Input for aligning two ayahs that have already been paired explicitly.
///
/// In particular, this type does not infer that a Hafs ayah number is the same
/// ayah number in Qalun.
class ExplicitAyahPair {
  const ExplicitAyahPair({
    required this.baseReading,
    required this.baseSurah,
    required this.baseAyah,
    this.baseAyahEnd,
    required this.baseText,
    required this.targetReading,
    required this.targetSurah,
    required this.targetAyah,
    this.targetAyahEnd,
    required this.targetText,
  });

  final QuranReading baseReading;
  final int baseSurah;
  final int baseAyah;
  final int? baseAyahEnd;
  final String baseText;
  final QuranReading targetReading;
  final int targetSurah;
  final int targetAyah;
  final int? targetAyahEnd;
  final String targetText;
}

/// Review-only result of an automatic alignment pass.
class AyahAlignmentProposal {
  const AyahAlignmentProposal({required this.pair, required this.alignments});

  final ExplicitAyahPair pair;
  final List<ProposedWordAlignment> alignments;

  Iterable<ProposedWordAlignment> get differences =>
      alignments.where((alignment) => alignment.isDifference);
}

import 'package:flutter_test/flutter_test.dart';
import 'package:quran_qiraat/quran_qiraat.dart';

void main() {
  const engine = ReadingAlignmentEngine();

  ExplicitAyahPair pair(String base, String target) => ExplicitAyahPair(
    baseReading: QuranReading.hafs,
    baseSurah: 1,
    baseAyah: 4,
    baseText: base,
    targetReading: QuranReading.qalun,
    targetSurah: 1,
    targetAyah: 3,
    targetText: target,
  );

  test('aligns words before classifying an internal letter change', () {
    final result = engine.align(
      pair('مَالِكِ يَوْمِ الدِّينِ', 'مَلِكِ يَوْمِ الدِّينِ'),
    );

    expect(result.alignments, hasLength(3));
    expect(result.differences, hasLength(1));
    expect(result.alignments.first.baseTokens.single.text, 'مَالِكِ');
    expect(result.alignments.first.targetTokens.single.text, 'مَلِكِ');
    expect(result.alignments.first.kind, TextDifferenceKind.letters);
    expect(
      result.alignments.first.characterEdits.any(
        (edit) => edit.kind == CharacterEditKind.delete && edit.baseText == 'ا',
      ),
      isTrue,
    );
  });

  test('separates a diacritics-only difference from letter changes', () {
    final result = engine.align(pair('كُتِبَ', 'كُتِبْ'));

    expect(result.alignments.single.kind, TextDifferenceKind.diacriticsOnly);
    expect(result.alignments.single.score, 1);
  });

  test('supports one-to-many word alignment without shifting later words', () {
    final result = engine.align(pair('أ بسم الله ج', 'أ ب اسم الله ج'));

    final grouped = result.alignments.firstWhere(
      (alignment) =>
          alignment.baseTokens.length == 1 &&
          alignment.targetTokens.length == 2,
    );
    expect(grouped.baseTokens.single.text, 'بسم');
    expect(grouped.targetTokens.map((token) => token.text), ['ب', 'اسم']);
    expect(result.alignments.last.baseTokens.single.text, 'ج');
    expect(result.alignments.last.targetTokens.single.text, 'ج');
  });

  test('does not infer shared ayah numbering for Qalun', () {
    final result = engine.align(pair('الحمد لله', 'اِ۬لْحَمْدُ لِلهِ'));

    expect(result.pair.baseAyah, 4);
    expect(result.pair.targetAyah, 3);
  });

  test('drops a standalone ayah marker from word numbering', () {
    final tokens = engine.tokenize('اِ۬لْعَٰلَمِينَ ١');

    expect(tokens, hasLength(1));
    expect(tokens.single.index, 1);
  });

  test('rejects an unusable maximum group size', () {
    expect(
      () => ReadingAlignmentEngine(maximumGroupSize: 0),
      throwsAssertionError,
    );
  });

  test('normalizes canonically equivalent Unicode before comparison', () {
    final edits = engine.compareCharacters('\u0623', '\u0627\u0654');

    expect(edits.every((edit) => edit.kind == CharacterEditKind.keep), isTrue);
  });

  test('serializes automatic results as review-only records', () {
    const pipeline = AlignmentReviewPipeline();
    final record = pipeline.propose(pair('مَالِكِ', 'مَلِكِ'));
    final encoded = pipeline.encodeQueue([record]);

    expect(record.status, AlignmentReviewStatus.pending);
    expect(encoded, contains('review_only'));
    expect(encoded, contains('character_edits'));
  });
}

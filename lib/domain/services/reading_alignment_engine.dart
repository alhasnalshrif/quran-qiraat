import '../models/reading_alignment.dart';

import 'package:unorm_dart/unorm_dart.dart' as unicode;

/// Produces review-only alignment proposals from an explicitly paired ayah.
///
/// The engine is intentionally layered: word spans are aligned first, then
/// their Arabic letters and combining marks are classified independently.
class ReadingAlignmentEngine {
  const ReadingAlignmentEngine({this.maximumGroupSize = 3})
    : assert(maximumGroupSize > 0);

  final int maximumGroupSize;

  AyahAlignmentProposal align(ExplicitAyahPair pair) {
    final base = tokenize(pair.baseText);
    final target = tokenize(pair.targetText);
    final rows = base.length + 1;
    final columns = target.length + 1;
    final costs = List.generate(
      rows,
      (_) => List<double>.filled(columns, double.infinity),
    );
    final previous = List.generate(
      rows,
      (_) => List<_Step?>.filled(columns, null),
    );
    costs[0][0] = 0;

    for (var i = 0; i <= base.length; i++) {
      for (var j = 0; j <= target.length; j++) {
        if (costs[i][j].isInfinite) continue;
        for (var baseCount = 0; baseCount <= maximumGroupSize; baseCount++) {
          for (
            var targetCount = 0;
            targetCount <= maximumGroupSize;
            targetCount++
          ) {
            if (baseCount == 0 && targetCount == 0) continue;
            if (baseCount > 0 &&
                targetCount > 0 &&
                baseCount > 1 &&
                targetCount > 1) {
              continue;
            }
            final nextI = i + baseCount;
            final nextJ = j + targetCount;
            if (nextI > base.length || nextJ > target.length) continue;
            final baseSpan = base.sublist(i, nextI);
            final targetSpan = target.sublist(j, nextJ);
            final stepCost = _spanCost(baseSpan, targetSpan);
            final candidate = costs[i][j] + stepCost;
            if (candidate < costs[nextI][nextJ]) {
              costs[nextI][nextJ] = candidate;
              previous[nextI][nextJ] = _Step(i, j, baseCount, targetCount);
            }
          }
        }
      }
    }

    final result = <ProposedWordAlignment>[];
    var i = base.length;
    var j = target.length;
    while (i > 0 || j > 0) {
      final step = previous[i][j];
      if (step == null) {
        throw StateError('Could not align the supplied ayah pair.');
      }
      final baseSpan = base.sublist(step.i, i);
      final targetSpan = target.sublist(step.j, j);
      result.add(_buildAlignment(baseSpan, targetSpan));
      i = step.i;
      j = step.j;
    }

    return AyahAlignmentProposal(
      pair: pair,
      alignments: result.reversed.toList(growable: false),
    );
  }

  List<ReadingToken> tokenize(String text) {
    final values = text
        .replaceAll('\u00a0', ' ')
        .trim()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty && !_isAyahMarker(word));
    var index = 0;
    return [
      for (final value in values) ReadingToken(index: ++index, text: value),
    ];
  }

  List<CharacterEdit> compareCharacters(String baseText, String targetText) =>
      _characterEdits(baseText, targetText);

  ProposedWordAlignment _buildAlignment(
    List<ReadingToken> base,
    List<ReadingToken> target,
  ) {
    if (base.isEmpty) {
      return ProposedWordAlignment(
        baseTokens: base,
        targetTokens: target,
        kind: TextDifferenceKind.insertion,
        score: 0,
      );
    }
    if (target.isEmpty) {
      return ProposedWordAlignment(
        baseTokens: base,
        targetTokens: target,
        kind: TextDifferenceKind.deletion,
        score: 0,
      );
    }
    final baseText = base.map((token) => token.text).join(' ');
    final targetText = target.map((token) => token.text).join(' ');
    final baseLetters = _lettersOnly(baseText);
    final targetLetters = _lettersOnly(targetText);
    final kind = unicode.nfc(baseText) == unicode.nfc(targetText)
        ? TextDifferenceKind.identical
        : baseLetters == targetLetters
        ? TextDifferenceKind.diacriticsOnly
        : TextDifferenceKind.letters;
    return ProposedWordAlignment(
      baseTokens: base,
      targetTokens: target,
      kind: kind,
      score: 1 - _normalizedEditDistance(baseLetters, targetLetters),
      characterEdits: _characterEdits(baseText, targetText),
    );
  }

  List<CharacterEdit> _characterEdits(String left, String right) {
    final a = unicode.nfd(left).runes.toList(growable: false);
    final b = unicode.nfd(right).runes.toList(growable: false);
    final costs = List.generate(
      a.length + 1,
      (i) => List<int>.generate(b.length + 1, (j) => i == 0 ? j : i),
    );
    for (var i = 1; i <= a.length; i++) {
      for (var j = 1; j <= b.length; j++) {
        costs[i][j] = _min3(
          costs[i - 1][j] + 1,
          costs[i][j - 1] + 1,
          costs[i - 1][j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1),
        );
      }
    }
    final edits = <CharacterEdit>[];
    var i = a.length;
    var j = b.length;
    while (i > 0 || j > 0) {
      if (i > 0 && j > 0) {
        final substitutionCost = a[i - 1] == b[j - 1] ? 0 : 1;
        if (costs[i][j] == costs[i - 1][j - 1] + substitutionCost) {
          edits.add(
            CharacterEdit(
              kind: substitutionCost == 0
                  ? CharacterEditKind.keep
                  : CharacterEditKind.substitute,
              baseText: String.fromCharCode(a[i - 1]),
              targetText: String.fromCharCode(b[j - 1]),
            ),
          );
          i--;
          j--;
          continue;
        }
      }
      if (i > 0 && costs[i][j] == costs[i - 1][j] + 1) {
        edits.add(
          CharacterEdit(
            kind: CharacterEditKind.delete,
            baseText: String.fromCharCode(a[--i]),
          ),
        );
      } else {
        edits.add(
          CharacterEdit(
            kind: CharacterEditKind.insert,
            targetText: String.fromCharCode(b[--j]),
          ),
        );
      }
    }
    return edits.reversed.toList(growable: false);
  }

  double _spanCost(List<ReadingToken> base, List<ReadingToken> target) {
    if (base.isEmpty || target.isEmpty) {
      return 1.15 * (base.length + target.length);
    }
    final left = _lettersOnly(base.map((token) => token.text).join());
    final right = _lettersOnly(target.map((token) => token.text).join());
    final groupingPenalty = 0.08 * (base.length + target.length - 2);
    return _normalizedEditDistance(left, right) + groupingPenalty;
  }

  double _normalizedEditDistance(String left, String right) {
    final a = left.runes.toList(growable: false);
    final b = right.runes.toList(growable: false);
    if (a.isEmpty && b.isEmpty) return 0;
    final previous = List<int>.generate(b.length + 1, (i) => i);
    for (var i = 1; i <= a.length; i++) {
      var diagonal = previous[0];
      previous[0] = i;
      for (var j = 1; j <= b.length; j++) {
        final old = previous[j];
        previous[j] = _min3(
          previous[j] + 1,
          previous[j - 1] + 1,
          diagonal + (a[i - 1] == b[j - 1] ? 0 : 1),
        );
        diagonal = old;
      }
    }
    return previous.last / (a.length > b.length ? a.length : b.length);
  }

  String _lettersOnly(String value) => String.fromCharCodes(
    unicode
        .nfd(value)
        .runes
        .where(
          (rune) => !_isArabicMark(rune) && rune != 0x20 && rune != 0x0640,
        ),
  );

  bool _isArabicMark(int rune) =>
      (rune >= 0x0610 && rune <= 0x061a) ||
      (rune >= 0x064b && rune <= 0x065f) ||
      rune == 0x0670 ||
      (rune >= 0x06d6 && rune <= 0x06ed);

  bool _isAyahMarker(String word) => word.runes.every(
    (rune) =>
        (rune >= 0x0660 && rune <= 0x0669) ||
        (rune >= 0x06f0 && rune <= 0x06f9) ||
        rune == 0x06dd,
  );

  int _min3(int a, int b, int c) {
    var result = a < b ? a : b;
    if (c < result) result = c;
    return result;
  }
}

class _Step {
  const _Step(this.i, this.j, this.baseCount, this.targetCount);

  final int i;
  final int j;
  final int baseCount;
  final int targetCount;
}

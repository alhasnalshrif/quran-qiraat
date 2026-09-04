import 'dart:convert';

import 'package:flutter/services.dart';

import '../domain/models/ayah.dart';
import '../domain/models/candidate_difference_record.dart';
import '../domain/models/margin_difference.dart';
import '../domain/models/margin_riwayah.dart';
import '../domain/models/mushaf_edition.dart';
import '../domain/models/reading_difference.dart';

class QuranRepository {
  const QuranRepository({
    required this.hafsByPage,
    required this.shubah,
    required this.qalun,
    this.manifest = MushafManifest.bundledDefault,
    this.publishedDifferences = const [],
    this.candidateDifferences = const [],
    @Deprecated('Use publishedDifferences or candidateDifferences instead.')
    this.differenceWords = const {},
  });

  final MushafManifest manifest;
  final Map<int, List<Ayah>> hafsByPage;
  final Map<String, Ayah> shubah;
  final Map<String, Ayah> qalun;

  /// Published, peer-reviewed reading differences vetted for public display.
  final List<ReadingDifference> publishedDifferences;

  /// Raw candidate difference locators from unvetted source datasets.
  /// Strictly unaligned: contains no inferred target span or performance classification.
  /// Must NOT be displayed as established differences to end users.
  final List<CandidateDifferenceRecord> candidateDifferences;

  /// Deprecated legacy map retained strictly for backward compatibility with isolated tests.
  @Deprecated('Use publishedDifferences or candidateDifferences instead.')
  final Map<MarginRiwayah, Map<String, List<int>>> differenceWords;

  List<Ayah> page(int pageNumber) => hafsByPage[pageNumber] ?? const <Ayah>[];

  List<Ayah> pageForReading(QuranReading reading, int pageNumber) {
    final hafsPage = page(pageNumber);
    if (reading == QuranReading.hafs) return hafsPage;
    final variants = reading == QuranReading.shubah ? shubah : qalun;
    return [for (final hafs in hafsPage) variants[hafs.key] ?? hafs];
  }

  // ---------------------------------------------------------------------------
  // Published / Reviewed Differences API
  // ---------------------------------------------------------------------------

  /// Returns peer-reviewed differences on the given page for the selected [riwayah].
  List<ReadingDifference> publishedDifferencesOnPage(
    MarginRiwayah riwayah,
    int pageNumber,
  ) {
    final targetReading = riwayah.toReading();
    final pageVerseKeys = {for (final ayah in page(pageNumber)) ayah.key};
    return publishedDifferences
        .where(
          (d) =>
              d.targetReading == targetReading &&
              pageVerseKeys.contains(d.baseSpan.ayahKey),
        )
        .toList(growable: false);
  }

  /// Whether any reviewed/published difference exists on this page.
  bool hasPublishedDifferencesOnPage(MarginRiwayah riwayah, int pageNumber) =>
      publishedDifferencesOnPage(riwayah, pageNumber).isNotEmpty;

  /// Whether a reviewed/published difference exists for this specific Hafs verse.
  bool hasPublishedDifference(MarginRiwayah riwayah, Ayah hafs) {
    final targetReading = riwayah.toReading();
    return publishedDifferences.any(
      (d) => d.targetReading == targetReading && d.baseSpan.ayahKey == hafs.key,
    );
  }

  /// Word indices to highlight for this verse in the main reader text.
  /// Only published/reviewed differences are ever highlighted.
  List<int> highlightedWordsFor(MarginRiwayah riwayah, Ayah hafs) {
    final targetReading = riwayah.toReading();
    final matching = publishedDifferences.where(
      (d) => d.targetReading == targetReading && d.baseSpan.ayahKey == hafs.key,
    );

    if (matching.isNotEmpty) {
      final indices = <int>{};
      for (final diff in matching) {
        for (
          var i = diff.baseSpan.startWordIndex;
          i <= diff.baseSpan.endWordIndex;
          i++
        ) {
          indices.add(i);
        }
      }
      return indices.toList()..sort();
    }

    // Fall back to legacy differenceWords if explicitly supplied in test fixture.
    return differenceWords[riwayah]?[hafs.key] ?? const [];
  }

  // ---------------------------------------------------------------------------
  // Candidate / Unreviewed Differences API (Internal Dev Only)
  // ---------------------------------------------------------------------------

  /// Returns raw candidate (unreviewed) difference locators on this page.
  List<CandidateDifferenceRecord> candidateDifferencesOnPage(
    MarginRiwayah riwayah,
    int pageNumber,
  ) {
    final pageAyahs = page(pageNumber);
    final pageVerseKeys = {for (final ayah in pageAyahs) ayah.key};
    return candidateDifferences
        .where(
          (c) =>
              c.sourceReading == riwayah &&
              (c.hafsPage == pageNumber ||
                  pageVerseKeys.contains(c.hafsAyahKey)),
        )
        .toList(growable: false);
  }

  /// Whether candidate (unreviewed) difference records exist on this page.
  bool hasCandidateDifferencesOnPage(MarginRiwayah riwayah, int pageNumber) =>
      candidateDifferencesOnPage(riwayah, pageNumber).isNotEmpty;

  /// Whether candidate data exists for this specific Hafs verse.
  bool hasCandidateDifference(MarginRiwayah riwayah, Ayah hafs) =>
      candidateDifferences.any(
        (c) =>
            c.sourceReading == riwayah &&
            c.surah == hafs.surah &&
            c.hafsAyah == hafs.number,
      );

  /// Returns raw candidate locators for a specific Hafs verse.
  List<CandidateDifferenceRecord> candidateDifferencesForAyah(
    MarginRiwayah riwayah,
    Ayah hafs,
  ) => candidateDifferences
      .where(
        (c) =>
            c.sourceReading == riwayah &&
            c.surah == hafs.surah &&
            c.hafsAyah == hafs.number,
      )
      .toList(growable: false);

  // ---------------------------------------------------------------------------
  // Backward Compatible / Evolved API
  // ---------------------------------------------------------------------------

  /// Returns differences for the provided Hafs verses.
  /// Only published/reviewed differences are returned to end users.
  List<MarginDifference> differencesFor(
    MarginRiwayah riwayah,
    List<Ayah> hafsVerses,
  ) {
    final targetReading = riwayah.toReading();
    final results = <MarginDifference>[];

    for (final hafs in hafsVerses) {
      final variant = variantFor(riwayah, hafs);
      if (variant == null) continue;

      final diffs = publishedDifferences
          .where(
            (d) =>
                d.targetReading == targetReading &&
                d.baseSpan.ayahKey == hafs.key,
          )
          .toList(growable: false);

      if (diffs.isNotEmpty) {
        for (final diff in diffs) {
          final wordIndices = [
            for (
              var i = diff.baseSpan.startWordIndex;
              i <= diff.baseSpan.endWordIndex;
              i++
            )
              i,
          ];
          results.add(
            MarginDifference(
              hafs: hafs,
              variant: variant,
              wordIndexes: wordIndices,
              difference: diff,
            ),
          );
        }
      } else if (differenceWords[riwayah]?[hafs.key]?.isNotEmpty ?? false) {
        // Fallback for legacy fixtures
        results.add(
          MarginDifference(
            hafs: hafs,
            variant: variant,
            wordIndexes: differenceWords[riwayah]![hafs.key]!,
          ),
        );
      }
    }

    return results;
  }

  Ayah? variantFor(MarginRiwayah riwayah, Ayah hafs) => switch (riwayah) {
    MarginRiwayah.shubah => shubah[hafs.key],
    MarginRiwayah.qalun => qalun[hafs.key],
  };

  bool hasDifference(MarginRiwayah riwayah, Ayah hafs) =>
      hasPublishedDifference(riwayah, hafs) ||
      (differenceWords[riwayah]?[hafs.key]?.isNotEmpty ?? false);

  List<int> wordsFor(MarginRiwayah riwayah, Ayah hafs) =>
      highlightedWordsFor(riwayah, hafs);

  WordComparison comparedWord({
    required Ayah hafs,
    required Ayah variant,
    required int wordIndex,
  }) => LegacyDifferenceAdapter.comparedWord(
    hafs: hafs,
    variant: variant,
    wordIndex: wordIndex,
  );

  WordComparison comparedDifference(ReadingDifference diff) =>
      WordComparison.fromReadingDifference(diff);

  // ---------------------------------------------------------------------------
  // Loaders
  // ---------------------------------------------------------------------------

  static Future<QuranRepository> load() async {
    final files = await Future.wait([
      rootBundle.loadString('assets/editions_manifest.json'),
      rootBundle.loadString('assets/quran_hafs.json'),
      rootBundle.loadString('assets/quran_shubah.json'),
      rootBundle.loadString('assets/quran_qalun.json'),
      rootBundle.loadString('assets/differences_taisir.json'),
    ]);

    final manifest = MushafManifest.fromJson(
      jsonDecode(files[0]) as Map<String, dynamic>,
    );
    final hafs = _parseAyahs(files[1], isHafs: true);
    final shubah = _parseAyahs(files[2]);
    final qalun = _parseAyahs(files[3]);

    final hafsByPage = <int, List<Ayah>>{};
    for (final ayah in hafs) {
      if (ayah.page != null) (hafsByPage[ayah.page!] ??= []).add(ayah);
    }

    final shubahMap = {for (final ayah in shubah) ayah.key: ayah};
    final qalunMap = {for (final ayah in qalun) ayah.key: ayah};

    // Parse differences_taisir.json strictly as raw candidate locators without synthetic alignment.
    final candidateDifferences = _parseCandidateDifferences(
      files[4],
      hafsMap: {for (final a in hafs) a.key: a},
    );

    return QuranRepository(
      manifest: manifest,
      hafsByPage: hafsByPage,
      shubah: shubahMap,
      qalun: qalunMap,
      publishedDifferences: const [], // No bundled candidate data is published without scholarly review.
      candidateDifferences: candidateDifferences,
      differenceWords: const {}, // Legacy map remains empty in production.
    );
  }

  static List<CandidateDifferenceRecord> _parseCandidateDifferences(
    String source, {
    required Map<String, Ayah> hafsMap,
  }) {
    final parsed = jsonDecode(source) as Map<String, dynamic>;
    final readings = parsed['readings'] as Map<String, dynamic>? ?? {};
    final provenance =
        parsed['source'] as String? ?? 'Corpus Coranicum / ad-Dānī at-Taysīr';
    final list = <CandidateDifferenceRecord>[];

    void processReading(MarginRiwayah riwayah, String key) {
      final verses = readings[key] as Map<String, dynamic>? ?? {};

      for (final entry in verses.entries) {
        final ayahKey = entry.key;
        final parts = ayahKey.split(':');
        if (parts.length != 2) continue;
        final surah = int.tryParse(parts[0]) ?? 0;
        final ayahNum = int.tryParse(parts[1]) ?? 0;
        final wordIndices = (entry.value as List<dynamic>).cast<num>();
        final hafsAyah = hafsMap[ayahKey];

        for (final wordNum in wordIndices) {
          final wordIndex = wordNum.toInt();
          list.add(
            CandidateDifferenceRecord(
              id: 'taisir_${key}_${ayahKey}_$wordIndex',
              sourceId: 'differences_taisir',
              sourceReading: riwayah,
              surah: surah,
              hafsAyah: ayahNum,
              hafsPage: hafsAyah?.page,
              rawWordIndex: wordIndex,
              provenance: provenance,
              notes: 'موضع مرشح أولي غير محقق؛ لا يشمل محاذاة ولا تصنيف أداء.',
            ),
          );
        }
      }
    }

    processReading(MarginRiwayah.shubah, 'shubah');
    processReading(MarginRiwayah.qalun, 'qalun');
    return list;
  }

  static List<Ayah> _parseAyahs(String source, {bool isHafs = false}) =>
      (jsonDecode(source) as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map((json) => Ayah.fromJson(json, isHafs: isHafs))
          .toList(growable: false);
}

/// Legacy compatibility adapter.
///
/// Visibly isolated to avoid conflating raw whitespace token splitting with
/// genuine scholarly difference alignment. Do not rely on this adapter for
/// new production reading architectures.
abstract final class LegacyDifferenceAdapter {
  static WordComparison comparedWord({
    required Ayah hafs,
    required Ayah variant,
    required int wordIndex,
  }) {
    final hafsWord = wordAt(hafs.comparisonText, wordIndex);
    final variantWord = wordAt(variant.comparisonText, wordIndex);
    return WordComparison(
      hafs: hafsWord.isEmpty ? '—' : hafsWord,
      variant: variantWord.isEmpty
          ? 'وجه الرواية في الكلمة $wordIndex'
          : variantWord,
      isPerformanceOnly: readingKey(hafsWord) == readingKey(variantWord),
    );
  }

  static String wordAt(String text, int index) {
    final words = text
        .replaceAll(RegExp(r'[٠-٩]'), '')
        .trim()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList(growable: false);
    return index > 0 && index <= words.length ? words[index - 1] : '';
  }

  static String readingKey(String text) => text
      .replaceAll(
        RegExp(r'[\u0610-\u061A\u064B-\u065F\u0670\u06D6-\u06ED]'),
        '',
      )
      .replaceAll(RegExp(r'[ٱأإآ]'), 'ا')
      .replaceAll('ى', 'ي')
      .replaceAll('ـ', '')
      .trim();
}

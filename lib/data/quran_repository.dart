import 'dart:convert';

import 'package:flutter/services.dart';

import '../domain/models/ayah.dart';
import '../domain/models/ayah_correspondence.dart';
import '../domain/models/candidate_difference_record.dart';
import '../domain/models/margin_difference.dart';
import '../domain/models/margin_riwayah.dart';
import '../domain/models/mushaf_edition.dart';
import '../domain/models/mushaf_layout.dart';
import '../domain/models/reading_difference.dart';
import '../domain/models/reading_alignment.dart';
import '../domain/services/reading_alignment_engine.dart';
import 'mushaf_layout_repository.dart';

class QuranRepository {
  const QuranRepository({
    required this.hafsByPage,
    required this.shubah,
    required this.qalun,
    this.hafsLayout,
    this.manifest = MushafManifest.bundledDefault,
    this.publishedDifferences = const [],
    this.candidateDifferences = const [],
    this.ayahCorrespondences = const [],
    this.hafsByKey = const {},
    this.ayahCounterpartIndex = const {},
    this.ayahCorrespondenceIndex = const {},
    @Deprecated('Use publishedDifferences or candidateDifferences instead.')
    this.differenceWords = const {},
  });

  final MushafManifest manifest;
  final Map<int, List<Ayah>> hafsByPage;
  final Map<String, Ayah> shubah;
  final Map<String, Ayah> qalun;

  /// Vetted, source-pinned line layout for the Hafs Madani 604-page edition.
  /// Null only in narrow test fixtures or if the caller intentionally omits it.
  final MushafLayout? hafsLayout;

  /// Published, peer-reviewed reading differences vetted for public display.
  final List<ReadingDifference> publishedDifferences;

  /// Raw candidate difference locators from unvetted source datasets.
  /// Strictly unaligned: contains no inferred target span or performance classification.
  /// Must NOT be displayed as established differences to end users.
  final List<CandidateDifferenceRecord> candidateDifferences;

  /// Reviewed mappings between readings that use different ayah numbering.
  final List<AyahCorrespondence> ayahCorrespondences;
  final Map<String, Ayah> hafsByKey;
  final Map<String, List<ReadingAyahRef>> ayahCounterpartIndex;
  final Map<String, AyahCorrespondence> ayahCorrespondenceIndex;

  /// Deprecated legacy map retained strictly for backward compatibility with isolated tests.
  @Deprecated('Use publishedDifferences or candidateDifferences instead.')
  final Map<MarginRiwayah, Map<String, List<int>>> differenceWords;

  List<Ayah> page(int pageNumber) => hafsByPage[pageNumber] ?? const <Ayah>[];

  List<Ayah> pageForReading(QuranReading reading, int pageNumber) {
    final hafsPage = page(pageNumber);
    if (reading == QuranReading.hafs) return hafsPage;
    if (reading == QuranReading.shubah) {
      return [for (final hafs in hafsPage) ?shubah[hafs.key]];
    }
    final values = [
      for (final hafs in hafsPage)
        ...ayahsCorrespondingTo(
          sourceReading: QuranReading.hafs,
          targetReading: reading,
          surah: hafs.surah,
          ayah: hafs.number,
        ),
    ];
    final seen = <String>{};
    return values.where((ayah) => seen.add(ayah.key)).toList(growable: false);
  }

  List<Ayah> ayahsCorrespondingTo({
    required QuranReading sourceReading,
    required QuranReading targetReading,
    required int surah,
    required int ayah,
  }) {
    if (sourceReading == targetReading) {
      final value = _ayahMap(targetReading)['$surah:$ayah'];
      return value == null ? const [] : [value];
    }
    // Hafs and Shu'bah use the same packaged Kufic ayah numbering.
    if ({sourceReading, targetReading}.contains(QuranReading.hafs) &&
        {sourceReading, targetReading}.contains(QuranReading.shubah)) {
      final value = _ayahMap(targetReading)['$surah:$ayah'];
      return value == null ? const [] : [value];
    }
    final sourceRef = ReadingAyahRef(
      reading: sourceReading,
      surah: surah,
      ayah: ayah,
    );
    final refs =
        ayahCounterpartIndex[_correspondenceKey(sourceRef, targetReading)] ??
        [
          for (final correspondence in ayahCorrespondences)
            ...correspondence
                .counterparts(sourceRef)
                .where((ref) => ref.reading == targetReading),
        ];
    final targetMap = _ayahMap(targetReading);
    return [for (final ref in refs) ?targetMap[ref.key]];
  }

  /// Finds a reviewed difference for an explicitly selected reading pair.
  /// The lookup is symmetric so the UI can swap the primary and review readings.
  ReadingDifference? publishedDifferenceForWord({
    required QuranReading baseReading,
    required QuranReading comparisonReading,
    required int surah,
    required int ayah,
    required int wordIndex,
  }) {
    for (final difference in publishedDifferences) {
      final isForward =
          difference.baseReading == baseReading &&
          difference.targetReading == comparisonReading &&
          difference.baseSpan.surah == surah &&
          difference.baseSpan.ayah == ayah &&
          difference.baseSpan.containsWord(wordIndex);
      final isReverse =
          difference.targetReading == baseReading &&
          difference.baseReading == comparisonReading &&
          difference.targetSpan.surah == surah &&
          difference.targetSpan.ayah == ayah &&
          difference.targetSpan.containsWord(wordIndex);
      if (isForward || isReverse) return difference;
    }
    return null;
  }

  /// Returns source evidence only for a Hafs-to-target review pair.  It is not
  /// an approved target word span and callers must label it as pending review.
  CandidateDifferenceRecord? candidateEvidenceForWord({
    required QuranReading baseReading,
    required QuranReading comparisonReading,
    required int surah,
    required int ayah,
    required int wordIndex,
  }) {
    if (baseReading != QuranReading.hafs) return null;
    final target = comparisonReading.differenceSource;
    if (target == null) return null;
    for (final candidate in candidateDifferences) {
      if (candidate.sourceReading == target &&
          candidate.surah == surah &&
          candidate.hafsAyah == ayah &&
          candidate.rawWordIndex == wordIndex) {
        return candidate;
      }
    }
    return null;
  }

  /// Returns an ayah only when the datasets share an explicit ayah key.
  /// This is deliberately not a word alignment across readings.
  Ayah? ayahForReading(
    QuranReading reading,
    String ayahKey, {
    QuranReading? sourceReading,
  }) {
    final parts = ayahKey.split(':');
    if (sourceReading != null && parts.length == 2) {
      final surah = int.tryParse(parts[0]);
      final ayah = int.tryParse(parts[1]);
      if (surah == null || ayah == null) return null;
      return ayahsCorrespondingTo(
        sourceReading: sourceReading,
        targetReading: reading,
        surah: surah,
        ayah: ayah,
      ).firstOrNull;
    }
    return _ayahMap(reading)[ayahKey];
  }

  Map<String, Ayah> _ayahMap(QuranReading reading) => switch (reading) {
    QuranReading.hafs =>
      hafsByKey.isNotEmpty
          ? hafsByKey
          : {
              for (final ayahs in hafsByPage.values)
                for (final ayah in ayahs) ayah.key: ayah,
            },
    QuranReading.shubah => shubah,
    QuranReading.qalun => qalun,
  };

  AyahAlignmentProposal? alignmentProposal({
    required QuranReading sourceReading,
    required QuranReading targetReading,
    required int surah,
    required int ayah,
    ReadingAlignmentEngine engine = const ReadingAlignmentEngine(),
  }) {
    final sourceRef = ReadingAyahRef(
      reading: sourceReading,
      surah: surah,
      ayah: ayah,
    );
    final correspondence =
        ayahCorrespondenceIndex[_correspondenceKey(sourceRef, targetReading)] ??
        ayahCorrespondences
            .where(
              (item) => item
                  .counterparts(sourceRef)
                  .any((ref) => ref.reading == targetReading),
            )
            .firstOrNull;
    final sourceRefs = correspondence == null
        ? [sourceRef]
        : (correspondence.base.first.reading == sourceReading
              ? correspondence.base
              : correspondence.target);
    final targetRefs = correspondence == null
        ? <ReadingAyahRef>[]
        : (correspondence.base.first.reading == targetReading
              ? correspondence.base
              : correspondence.target);
    final sourceMap = _ayahMap(sourceReading);
    final targetMap = _ayahMap(targetReading);
    final sources = [for (final ref in sourceRefs) ?sourceMap[ref.key]];
    final targets = [for (final ref in targetRefs) ?targetMap[ref.key]];
    if (correspondence == null &&
        {sourceReading, targetReading}.contains(QuranReading.hafs) &&
        {sourceReading, targetReading}.contains(QuranReading.shubah)) {
      final directTarget = targetMap['$surah:$ayah'];
      if (directTarget != null) targets.add(directTarget);
    }
    if (sources.isEmpty) return null;
    if (targets.isEmpty) return null;
    return engine.align(
      ExplicitAyahPair(
        baseReading: sourceReading,
        baseSurah: sources.first.surah,
        baseAyah: sources.first.number,
        baseAyahEnd: sources.last.number,
        baseText: sources.map((item) => item.comparisonText).join(' '),
        targetReading: targetReading,
        targetSurah: targets.first.surah,
        targetAyah: targets.first.number,
        targetAyahEnd: targets.last.number,
        targetText: targets.map((item) => item.comparisonText).join(' '),
      ),
    );
  }

  List<AyahAlignmentProposal> alignmentProposalsForPage({
    required int pageNumber,
    required QuranReading targetReading,
    ReadingAlignmentEngine engine = const ReadingAlignmentEngine(),
  }) => [
    for (final ayah in page(pageNumber))
      ?alignmentProposal(
        sourceReading: QuranReading.hafs,
        targetReading: targetReading,
        surah: ayah.surah,
        ayah: ayah.number,
        engine: engine,
      ),
  ];

  ProposedWordAlignment? proposedAlignmentForCandidate(
    CandidateDifferenceRecord candidate, {
    ReadingAlignmentEngine engine = const ReadingAlignmentEngine(),
  }) {
    final proposal = alignmentProposal(
      sourceReading: QuranReading.hafs,
      targetReading: candidate.sourceReading.toReading(),
      surah: candidate.surah,
      ayah: candidate.hafsAyah,
      engine: engine,
    );
    if (proposal == null) return null;
    var offset = 0;
    for (var ayah = proposal.pair.baseAyah; ayah < candidate.hafsAyah; ayah++) {
      final preceding = _ayahMap(QuranReading.hafs)['${candidate.surah}:$ayah'];
      if (preceding != null) {
        offset += engine.tokenize(preceding.comparisonText).length;
      }
    }
    final proposalIndex = offset + candidate.rawWordIndex;
    return proposal.alignments
        .where(
          (alignment) =>
              alignment.baseTokens.any((token) => token.index == proposalIndex),
        )
        .firstOrNull;
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
      MushafLayoutRepository.loadHafsMadani604(),
      rootBundle.loadString('assets/taisir_review_queue.json'),
      rootBundle.loadString('assets/mappings/hafs_to_qalun.json'),
    ]);

    final manifest = MushafManifest.fromJson(
      jsonDecode(files[0] as String) as Map<String, dynamic>,
    );
    final hafs = _parseAyahs(files[1] as String, isHafs: true);
    final shubah = _parseAyahs(files[2] as String);
    final qalun = _parseAyahs(files[3] as String);

    final hafsByPage = <int, List<Ayah>>{};
    for (final ayah in hafs) {
      if (ayah.page != null) (hafsByPage[ayah.page!] ??= []).add(ayah);
    }

    final shubahMap = {for (final ayah in shubah) ayah.key: ayah};
    final qalunMap = {for (final ayah in qalun) ayah.key: ayah};
    final hafsMap = {for (final ayah in hafs) ayah.key: ayah};

    // The review queue holds source evidence but never asserts target Arabic spans.
    final candidateDifferences = _parseTaisirReviewQueue(
      files[5] as String,
      hafsMap: hafsMap,
    );
    final ayahCorrespondences = _parseHafsToQalunMap(files[6] as String);
    final counterpartIndex = <String, List<ReadingAyahRef>>{};
    final correspondenceIndex = <String, AyahCorrespondence>{};
    for (final correspondence in ayahCorrespondences) {
      final targetReading = correspondence.target.first.reading;
      for (final base in correspondence.base) {
        final key = _correspondenceKey(base, targetReading);
        counterpartIndex[key] = correspondence.target;
        correspondenceIndex[key] = correspondence;
      }
      final baseReading = correspondence.base.first.reading;
      for (final target in correspondence.target) {
        final key = _correspondenceKey(target, baseReading);
        counterpartIndex[key] = correspondence.base;
        correspondenceIndex[key] = correspondence;
      }
    }

    return QuranRepository(
      manifest: manifest,
      hafsByPage: hafsByPage,
      shubah: shubahMap,
      qalun: qalunMap,
      publishedDifferences: const [], // No bundled candidate data is published without scholarly review.
      candidateDifferences: candidateDifferences,
      ayahCorrespondences: ayahCorrespondences,
      hafsByKey: hafsMap,
      ayahCounterpartIndex: counterpartIndex,
      ayahCorrespondenceIndex: correspondenceIndex,
      hafsLayout: files[4] as MushafLayout,
      differenceWords: const {}, // Legacy map remains empty in production.
    );
  }

  static List<AyahCorrespondence> _parseHafsToQalunMap(String source) {
    final parsed = jsonDecode(source) as Map<String, dynamic>;
    if (parsed['_version'] != '0.1.0' ||
        parsed['_source'] != 'kufi' ||
        parsed['_rawi'] != 'qalun') {
      throw const FormatException('Unsupported Hafs-to-Qalun ayah map.');
    }
    final surahs = parsed['surahs'] as Map<String, dynamic>;
    final result = <AyahCorrespondence>[];
    for (final surahEntry in surahs.entries) {
      final surah = int.parse(surahEntry.key);
      final data = surahEntry.value as Map<String, dynamic>;
      final ayahs = data['ayahs'] as Map<String, dynamic>;
      final sourceToTargets = <int, Set<int>>{};
      final targetToSources = <int, Set<int>>{};
      for (final ayahEntry in ayahs.entries) {
        final sourceNumber = int.parse(ayahEntry.key);
        final mapping = ayahEntry.value as Map<String, dynamic>;
        final rawTargets = mapping['splits_into'] as List<dynamic>?;
        final targets = rawTargets == null
            ? {mapping['target_ayah'] as int}
            : rawTargets.cast<int>().toSet();
        sourceToTargets[sourceNumber] = targets;
        for (final target in targets) {
          (targetToSources[target] ??= <int>{}).add(sourceNumber);
        }
      }
      final visitedSources = <int>{};
      for (final startSource in sourceToTargets.keys) {
        if (!visitedSources.add(startSource)) continue;
        final componentSources = <int>{startSource};
        final componentTargets = <int>{};
        final sourceQueue = <int>[startSource];
        while (sourceQueue.isNotEmpty) {
          final current = sourceQueue.removeLast();
          for (final target in sourceToTargets[current]!) {
            if (!componentTargets.add(target)) continue;
            for (final linkedSource in targetToSources[target] ?? const {}) {
              if (visitedSources.add(linkedSource)) {
                componentSources.add(linkedSource);
                sourceQueue.add(linkedSource);
              }
            }
          }
        }
        final sortedSources = componentSources.toList()..sort();
        final sortedTargets = componentTargets.toList()..sort();
        result.add(
          AyahCorrespondence(
            id:
                'quranpedia-hafs-qalun-$surah-'
                '${sortedSources.first}-${sortedSources.last}',
            base: [
              for (final hafsAyah in sortedSources)
                ReadingAyahRef(
                  reading: QuranReading.hafs,
                  surah: surah,
                  ayah: hafsAyah,
                ),
            ],
            target: [
              for (final targetAyah in sortedTargets)
                ReadingAyahRef(
                  reading: QuranReading.qalun,
                  surah: surah,
                  ayah: targetAyah,
                ),
            ],
            source: 'quranpedia/qiraat-ayah-map@076255281ec6f76241d7e901e27072733d02a18d',
          ),
        );
      }
    }
    return result;
  }

  static String _correspondenceKey(
    ReadingAyahRef source,
    QuranReading targetReading,
  ) =>
      '${source.reading.name}:${source.surah}:${source.ayah}'
      '>${targetReading.name}';

  static List<CandidateDifferenceRecord> _parseTaisirReviewQueue(
    String source, {
    required Map<String, Ayah> hafsMap,
  }) {
    final parsed = jsonDecode(source) as Map<String, dynamic>;
    if (parsed['schemaVersion'] != '1.0.0') {
      throw const FormatException('Unsupported Taysir review queue schema.');
    }
    final records = parsed['records'] as List<dynamic>? ?? const [];
    final list = <CandidateDifferenceRecord>[];
    final ids = <String>{};
    for (final raw in records) {
      final record = raw as Map<String, dynamic>;
      final readingName = record['reading'] as String?;
      final reading = MarginRiwayah.values
          .where((value) => value.name == readingName)
          .firstOrNull;
      if (reading == null) {
        throw FormatException('Unknown candidate reading: $readingName');
      }
      final surah = record['surah'] as int;
      final ayah = record['ayah'] as int;
      final wordIndex = record['wordIndex'] as int;
      final id = record['id'] as String;
      if (!ids.add(id)) throw FormatException('Duplicate candidate id: $id');
      if (surah < 1 || surah > 114 || ayah < 1 || wordIndex < 1) {
        throw FormatException('Invalid candidate locator: $id');
      }
      if (record['sourceStatus'] != 'candidate_unreviewed' ||
          record['reviewStatus'] != 'pending') {
        throw FormatException('Unsafe candidate review status: $id');
      }
      if (!hafsMap.containsKey('$surah:$ayah')) {
        throw FormatException('Candidate references missing Hafs ayah: $id');
      }
      final hafsWordCount = hafsMap['$surah:$ayah']!.comparisonText
          .trim()
          .split(RegExp(r'\s+'))
          .where((word) => word.isNotEmpty)
          .length;
      if (wordIndex > hafsWordCount) {
        throw FormatException('Candidate word index is out of range: $id');
      }
      list.add(
        CandidateDifferenceRecord(
          id: id,
          sourceId: 'taisir_review_queue',
          sourceReading: reading,
          surah: surah,
          hafsAyah: ayah,
          hafsPage: hafsMap['$surah:$ayah']?.page,
          rawWordIndex: wordIndex,
          provenance: record['source'] as String? ?? 'ad-Dānī at-Taysīr',
          notes: 'موضع مرشح أولي غير محقق؛ لا يشمل محاذاة ولا تصنيف أداء.',
          referenceTransliteration:
              record['referenceTransliteration'] as String?,
          referenceCairoArabic: record['referenceCairoArabic'] as String?,
          variantTransliteration: record['variantTransliteration'] as String?,
        ),
      );
    }
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

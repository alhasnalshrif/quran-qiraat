import 'dart:convert';

import 'package:unorm_dart/unorm_dart.dart' as unicode;

import '../updates/data_source.dart';

import '../domain/models/ayah.dart';
import '../domain/models/ayah_correspondence.dart';
import '../domain/models/candidate_difference_record.dart';
import '../domain/models/margin_riwayah.dart';
import '../domain/models/mushaf_edition.dart';
import '../domain/models/mushaf_layout.dart';
import '../domain/models/reading_difference.dart';
import '../domain/models/reading_alignment.dart';
import '../domain/models/reading_word_ref.dart';
import '../domain/services/reading_alignment_engine.dart';
import '../domain/models/qiraat_variants.dart';
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
    this.qiraatVariants,
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

  /// Farsh of the ten readers from Quran Tajweed Engine, shown as published.
  final QiraatVariants? qiraatVariants;

  static final _caches = Expando<_RepositoryCache>();
  _RepositoryCache get _cache => _caches[this] ??= _RepositoryCache(this);

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
    // Compose the explicit Hafs/Qalun map with the packaged Hafs/Shu'bah
    // ayah numbering. This does not transfer word indices between readings.
    if (sourceReading == QuranReading.shubah &&
        targetReading == QuranReading.qalun) {
      return ayahsCorrespondingTo(
        sourceReading: QuranReading.hafs,
        targetReading: targetReading,
        surah: surah,
        ayah: ayah,
      );
    }
    if (sourceReading == QuranReading.qalun &&
        targetReading == QuranReading.shubah) {
      return [
        for (final hafs in ayahsCorrespondingTo(
          sourceReading: sourceReading,
          targetReading: QuranReading.hafs,
          surah: surah,
          ayah: ayah,
        ))
          ?shubah[hafs.key],
      ];
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
    for (final difference
        in _cache
                .publishedByWord['${baseReading.name}:$surah:$ayah:$wordIndex'] ??
            const <ReadingDifference>[]) {
      if (!difference.isPublished) continue;
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
    for (final candidate
        in _cache.candidatesByWord['$surah:$ayah:$wordIndex'] ??
            const <CandidateDifferenceRecord>[]) {
      if (candidate.sourceReading == target &&
          candidate.surah == surah &&
          candidate.hafsAyah == ayah &&
          candidate.rawWordIndex == wordIndex) {
        return candidate;
      }
    }
    return null;
  }

  /// Farsh junctures on a Hafs page, in page order.
  List<Juncture> qiraatJuncturesOnPage(int pageNumber) {
    final variants = qiraatVariants;
    if (variants == null) return const [];
    final seen = <Juncture>{};
    return [
      for (final ayah in page(pageNumber))
        for (final juncture in variants.forAyah(ayah.key))
          if (seen.add(juncture)) juncture,
    ];
  }

  /// Uthmani Hafs text of an ayah from the line layout, with its number.
  String? hafsLayoutAyahText(String ayahKey) => _cache.hafsLayoutText[ayahKey];

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
    final cacheKey =
        '${sourceReading.name}>${targetReading.name}:$surah:$ayah:${engine.maximumGroupSize}';
    final cached = _cache.alignments[cacheKey];
    if (cached != null) return cached;
    final pair = _comparisonPair(sourceReading, targetReading, surah, ayah);
    if (pair == null) return null;
    final proposal = engine.align(pair);
    if (_cache.alignments.length >= 128) {
      _cache.alignments.remove(_cache.alignments.keys.first);
    }
    _cache.alignments[cacheKey] = proposal;
    return proposal;
  }

  ExplicitAyahPair? _comparisonPair(
    QuranReading sourceReading,
    QuranReading targetReading,
    int surah,
    int ayah, {
    bool useHafsLayout = false,
  }) {
    if (sourceReading == targetReading) return null;
    final comparesQalun =
        sourceReading == QuranReading.qalun ||
        targetReading == QuranReading.qalun;
    // The bundled Qalun text has no numbered basmala in Al-Fatihah.
    // Its mapping groups the Hafs basmala with Qalun 1:1 for navigation.
    final omitBasmala = useHafsLayout && comparesQalun && surah == 1;
    if (omitBasmala && sourceReading != QuranReading.qalun && ayah == 1) {
      return null;
    }
    final mappingSource =
        sourceReading == QuranReading.shubah &&
            targetReading == QuranReading.qalun
        ? QuranReading.hafs
        : sourceReading;
    final mappingTarget =
        targetReading == QuranReading.shubah &&
            sourceReading == QuranReading.qalun
        ? QuranReading.hafs
        : targetReading;
    final sourceRef = ReadingAyahRef(
      reading: mappingSource,
      surah: surah,
      ayah: ayah,
    );
    final correspondence =
        ayahCorrespondenceIndex[_correspondenceKey(sourceRef, mappingTarget)] ??
        ayahCorrespondences
            .where(
              (item) => item
                  .counterparts(sourceRef)
                  .any((ref) => ref.reading == mappingTarget),
            )
            .firstOrNull;
    final sourceRefs = correspondence == null
        ? [sourceRef]
        : (correspondence.base.first.reading == mappingSource
              ? correspondence.base
              : correspondence.target);
    final targetRefs = correspondence == null
        ? <ReadingAyahRef>[]
        : (correspondence.base.first.reading == mappingTarget
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
    if (sources.isEmpty ||
        targets.isEmpty ||
        sources.length != sourceRefs.length ||
        (targetRefs.isNotEmpty && targets.length != targetRefs.length)) {
      return null;
    }
    String textFor(QuranReading reading, List<Ayah> ayahs) => ayahs
        .map(
          (item) => useHafsLayout && reading == QuranReading.hafs
              ? _cache.hafsLayoutText[item.key] ?? item.comparisonText
              : item.comparisonText,
        )
        .join(' ');
    final comparedSources = omitBasmala && sourceReading != QuranReading.qalun
        ? sources.where((item) => item.number != 1).toList()
        : sources;
    final comparedTargets = omitBasmala && targetReading != QuranReading.qalun
        ? targets.where((item) => item.number != 1).toList()
        : targets;
    if (comparedSources.isEmpty || comparedTargets.isEmpty) return null;
    return ExplicitAyahPair(
      baseReading: sourceReading,
      baseSurah: sources.first.surah,
      baseAyah: comparedSources.first.number,
      baseAyahEnd: comparedSources.last.number,
      baseText: textFor(sourceReading, comparedSources),
      targetReading: targetReading,
      targetSurah: targets.first.surah,
      targetAyah: comparedTargets.first.number,
      targetAyahEnd: comparedTargets.last.number,
      targetText: textFor(targetReading, comparedTargets),
    );
  }

  ({List<ExplicitAyahPair> changed, List<Ayah> unpaired}) textDifferencesOnPage(
    QuranReading baseReading,
    QuranReading targetReading,
    int pageNumber,
  ) {
    final changed = <ExplicitAyahPair>[];
    final unpaired = <Ayah>[];
    final seen = <String>{};
    for (final ayah in pageForReading(baseReading, pageNumber)) {
      final pair = _comparisonPair(
        baseReading,
        targetReading,
        ayah.surah,
        ayah.number,
        useHafsLayout: true,
      );
      if (pair == null) {
        unpaired.add(ayah);
        continue;
      }
      final key = '${pair.baseSurah}:${pair.baseAyah}:${pair.baseAyahEnd}';
      if (seen.add(key) &&
          comparableReadingText(pair.baseText) !=
              comparableReadingText(pair.targetText)) {
        changed.add(pair);
      }
    }
    return (changed: changed, unpaired: unpaired);
  }

  static String comparableReadingText(String text) => unicode.nfc(
    const ReadingAlignmentEngine()
        .tokenize(text.replaceAll(RegExp('[\u061c\u0640\u200e\u200f]'), ''))
        .map((token) => token.text)
        .join(' '),
  );

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

  List<ReadingDifference> publishedDifferencesForPairOnPage(
    QuranReading base,
    QuranReading target,
    int pageNumber,
  ) => publishedDifferences
      .where((difference) {
        if (!difference.isPublished) return false;
        if (!((difference.baseReading == base &&
                difference.targetReading == target) ||
            (difference.baseReading == target &&
                difference.targetReading == base))) {
          return false;
        }
        if (difference.baseReading == QuranReading.hafs) {
          return _spanOnPage(difference.baseSpan, pageNumber);
        }
        if (difference.targetReading == QuranReading.hafs) {
          return _spanOnPage(difference.targetSpan, pageNumber);
        }
        final span = difference.baseReading == base
            ? difference.baseSpan
            : difference.targetSpan;
        return pageForReading(
          base,
          pageNumber,
        ).any((ayah) => ayah.key == span.ayahKey);
      })
      .toList(growable: false);

  bool _spanOnPage(ReadingWordSpan span, int pageNumber) {
    if (hafsLayout == null) {
      return page(pageNumber).any((ayah) => ayah.key == span.ayahKey);
    }
    for (var word = span.startWordIndex; word <= span.endWordIndex; word++) {
      if (_cache.wordPages['${span.ayahKey}:$word']?.contains(pageNumber) ??
          false) {
        return true;
      }
    }
    return false;
  }

  // ---------------------------------------------------------------------------
  // Candidate / Unreviewed Differences API (Internal Dev Only)
  // ---------------------------------------------------------------------------

  /// Returns raw candidate (unreviewed) difference locators on this page.
  List<CandidateDifferenceRecord> candidateDifferencesOnPage(
    MarginRiwayah riwayah,
    int pageNumber,
  ) {
    if (hafsLayout != null) {
      return (_cache.candidatesByPage[pageNumber] ??
              const <CandidateDifferenceRecord>[])
          .where((candidate) => candidate.sourceReading == riwayah)
          .toList(growable: false);
    }
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

  // ---------------------------------------------------------------------------
  // Loaders
  // ---------------------------------------------------------------------------

  static Future<QuranRepository> load({
    QuranDataSource source = const BundledDataSource(),
  }) async {
    final files = await Future.wait([
      source.loadString('editions-manifest', 'editions_manifest.json'),
      source.loadString('hafs-text', 'quran_hafs.json'),
      source.loadString('riwayah-shubah-text', 'quran_shubah.json'),
      source.loadString('riwayah-qalun-text', 'quran_qalun.json'),
      MushafLayoutRepository.loadHafsMadani604(source: source),
      source.loadString('mapping-hafs-qalun', 'hafs_to_qalun.json'),
      source.loadString('qiraat-farsh', 'variants.json'),
    ]);

    final manifest = MushafManifest.fromJson(
      jsonDecode(files[0] as String) as Map<String, dynamic>,
    );
    final hafs = _parseAyahs(files[1] as String, isHafs: true);
    final shubah = _parseAyahs(files[2] as String);
    final qalun = _parseAyahs(files[3] as String);

    final shubahMap = {for (final ayah in shubah) ayah.key: ayah};
    final qalunMap = {for (final ayah in qalun) ayah.key: ayah};
    final hafsMap = {for (final ayah in hafs) ayah.key: ayah};
    final layout = files[4] as MushafLayout;
    final hafsByPage = <int, List<Ayah>>{};
    final wordPageIndex = <String, int>{};
    for (final page in layout.pages) {
      final keys = <String>{};
      for (final line in page.lines) {
        for (final word in line.words) {
          keys.add(word.location.split(':').take(2).join(':'));
          wordPageIndex[word.location] = page.number;
        }
      }
      hafsByPage[page.number] = [
        for (final key in keys)
          hafsMap[key] ??
              (throw FormatException('Layout references missing ayah: $key')),
      ];
    }

    final ayahCorrespondences = _parseHafsToQalunMap(files[5] as String);
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
      candidateDifferences: const [],
      ayahCorrespondences: ayahCorrespondences,
      hafsByKey: hafsMap,
      ayahCounterpartIndex: counterpartIndex,
      ayahCorrespondenceIndex: correspondenceIndex,
      qiraatVariants: QiraatVariants.parse(files[6] as String),
      hafsLayout: layout,
    );
  }

  static List<ReadingDifference> parsePublishedDifferences(
    String source, {
    required Map<QuranReading, Map<String, Ayah>> ayahs,
    MushafLayout? hafsLayout,
  }) {
    final document = jsonDecode(source) as Map<String, dynamic>;
    if (document['schema_version'] != '1.0.0') {
      throw const FormatException('Unsupported published differences schema.');
    }
    final records = document['records'] as List<dynamic>;
    if (records.isEmpty) return const [];
    final ids = <String>{};
    final layoutWords = <String, String>{
      for (final page in hafsLayout?.pages ?? const <MushafLayoutPage>[])
        for (final line in page.lines)
          for (final word in line.words)
            word.location: const ReadingAlignmentEngine()
                .tokenize(word.text)
                .map((token) => token.text)
                .join(' '),
    };
    return List.unmodifiable(
      records.map((raw) {
        final difference = ReadingDifference.fromJson(
          raw as Map<String, dynamic>,
        );
        if (!difference.isPublished || !ids.add(difference.id)) {
          throw const FormatException(
            'Published bundle contains unreviewed or duplicate records.',
          );
        }
        for (final span in [difference.baseSpan, difference.targetSpan]) {
          final ayah = ayahs[span.reading]?[span.ayahKey];
          final tokens = ayah == null
              ? const <ReadingToken>[]
              : const ReadingAlignmentEngine().tokenize(ayah.comparisonText);
          if (ayah == null ||
              ((span.reading != QuranReading.hafs || hafsLayout == null) &&
                  span.endWordIndex > tokens.length)) {
            throw FormatException(
              'Invalid published word span: ${difference.id}',
            );
          }
          final expected =
              span.reading == QuranReading.hafs && hafsLayout != null
              ? [
                  for (
                    var word = span.startWordIndex;
                    word <= span.endWordIndex;
                    word++
                  )
                    layoutWords['${span.ayahKey}:$word'] ??
                        (throw FormatException(
                          'Missing published layout word: ${difference.id}',
                        )),
                ].join(' ')
              : tokens
                    .sublist(span.startWordIndex - 1, span.endWordIndex)
                    .map((token) => token.text)
                    .join(' ');
          if (unicode.nfc(
                const ReadingAlignmentEngine()
                    .tokenize(span.text)
                    .map((token) => token.text)
                    .join(' '),
              ) !=
              unicode.nfc(expected)) {
            throw FormatException(
              'Published span text does not match its reading: ${difference.id}',
            );
          }
        }
        return difference;
      }),
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

  static List<CandidateDifferenceRecord> parseTaisirReviewQueue(
    String source, {
    required Map<String, Ayah> hafsMap,
    required Map<String, int> wordPageIndex,
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
      final layoutPage = wordPageIndex['$surah:$ayah:$wordIndex'];
      if (layoutPage == null) {
        throw FormatException('Candidate references missing layout word: $id');
      }
      list.add(
        CandidateDifferenceRecord(
          id: id,
          sourceId: 'taisir_review_queue',
          sourceReading: reading,
          surah: surah,
          hafsAyah: ayah,
          hafsPage: layoutPage,
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

  static List<Ayah> _parseAyahs(String source, {bool isHafs = false}) {
    final ayahs = (jsonDecode(source) as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map((json) => Ayah.fromJson(json, isHafs: isHafs))
        .toList(growable: false);
    final keys = <String>{};
    for (final ayah in ayahs) {
      if (!keys.add(ayah.key) ||
          ayah.surah < 1 ||
          ayah.surah > 114 ||
          ayah.number < 1 ||
          ayah.text.trim().isEmpty ||
          ayah.comparisonText.trim().isEmpty) {
        throw const FormatException('Invalid or duplicate Quran ayah.');
      }
    }
    return ayahs;
  }
}

class _RepositoryCache {
  _RepositoryCache(this.repository);

  final QuranRepository repository;
  final alignments = <String, AyahAlignmentProposal>{};
  late final wordPages = _wordPages();
  late final candidatesByWord = _candidatesByWord();
  late final candidatesByPage = _candidatesByPage();
  late final publishedByWord = _publishedByWord();
  late final hafsLayoutWords = _hafsLayoutWords();
  late final hafsLayoutText = hafsLayoutWords.map(
    (key, words) => MapEntry(key, words.map((word) => word.text).join(' ')),
  );

  Map<String, List<MushafLayoutWord>> _hafsLayoutWords() {
    final words = <String, List<MushafLayoutWord>>{};
    for (final page
        in repository.hafsLayout?.pages ?? const <MushafLayoutPage>[]) {
      for (final line in page.lines) {
        for (final word in line.words) {
          final key = word.location.substring(
            0,
            word.location.lastIndexOf(':'),
          );
          (words[key] ??= []).add(word);
        }
      }
    }
    return words;
  }

  Map<String, List<CandidateDifferenceRecord>> _candidatesByWord() {
    final index = <String, List<CandidateDifferenceRecord>>{};
    for (final candidate in repository.candidateDifferences) {
      (index['${candidate.hafsAyahKey}:${candidate.rawWordIndex}'] ??= []).add(
        candidate,
      );
    }
    return index;
  }

  Map<String, Set<int>> _wordPages() {
    final index = <String, Set<int>>{};
    for (final page
        in repository.hafsLayout?.pages ?? const <MushafLayoutPage>[]) {
      for (final line in page.lines) {
        for (final word in line.words) {
          (index[word.location] ??= {}).add(page.number);
        }
      }
    }
    return index;
  }

  Map<int, List<CandidateDifferenceRecord>> _candidatesByPage() {
    final index = <int, List<CandidateDifferenceRecord>>{};
    for (final candidate in repository.candidateDifferences) {
      for (final page
          in wordPages['${candidate.hafsAyahKey}:${candidate.rawWordIndex}'] ??
              const <int>{}) {
        (index[page] ??= []).add(candidate);
      }
    }
    return index;
  }

  Map<String, List<ReadingDifference>> _publishedByWord() {
    final index = <String, List<ReadingDifference>>{};
    for (final difference in repository.publishedDifferences) {
      if (!difference.isPublished) continue;
      for (final span in [difference.baseSpan, difference.targetSpan]) {
        for (
          var word = span.startWordIndex;
          word <= span.endWordIndex;
          word++
        ) {
          (index['${span.reading.name}:${span.ayahKey}:$word'] ??= []).add(
            difference,
          );
        }
      }
    }
    return index;
  }
}

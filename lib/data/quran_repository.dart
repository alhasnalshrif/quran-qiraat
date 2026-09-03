import 'dart:convert';

import 'package:flutter/services.dart';

import '../domain/models/ayah.dart';
import '../domain/models/margin_difference.dart';
import '../domain/models/margin_riwayah.dart';

class QuranRepository {
  const QuranRepository({
    required this.hafsByPage,
    required this.shubah,
    required this.qalun,
    this.differenceWords = const {},
  });

  final Map<int, List<Ayah>> hafsByPage;
  final Map<String, Ayah> shubah;
  final Map<String, Ayah> qalun;
  final Map<MarginRiwayah, Map<String, List<int>>> differenceWords;

  List<Ayah> page(int pageNumber) => hafsByPage[pageNumber] ?? const <Ayah>[];

  List<Ayah> pageForReading(QuranReading reading, int pageNumber) {
    final hafsPage = page(pageNumber);
    if (reading == QuranReading.hafs) return hafsPage;
    final variants = reading == QuranReading.shubah ? shubah : qalun;
    return [for (final hafs in hafsPage) variants[hafs.key] ?? hafs];
  }

  List<MarginDifference> differencesFor(
    MarginRiwayah riwayah,
    List<Ayah> hafsVerses,
  ) => [
    for (final hafs in hafsVerses)
      if (hasDifference(riwayah, hafs) && variantFor(riwayah, hafs) != null)
        MarginDifference(
          hafs: hafs,
          variant: variantFor(riwayah, hafs)!,
          wordIndexes: wordsFor(riwayah, hafs),
        ),
  ];

  Ayah? variantFor(MarginRiwayah riwayah, Ayah hafs) => switch (riwayah) {
    MarginRiwayah.shubah => shubah[hafs.key],
    MarginRiwayah.qalun => qalun[hafs.key],
  };

  bool hasDifference(MarginRiwayah riwayah, Ayah hafs) =>
      differenceWords[riwayah]?[hafs.key]?.isNotEmpty ?? false;

  List<int> wordsFor(MarginRiwayah riwayah, Ayah hafs) =>
      differenceWords[riwayah]?[hafs.key] ?? const [];

  WordComparison comparedWord({
    required Ayah hafs,
    required Ayah variant,
    required int wordIndex,
  }) {
    final hafsWord = _wordAt(hafs.comparisonText, wordIndex);
    final variantWord = _wordAt(variant.comparisonText, wordIndex);
    return WordComparison(
      hafs: hafsWord.isEmpty ? '—' : hafsWord,
      variant: variantWord.isEmpty
          ? 'وجه الرواية في الكلمة $wordIndex'
          : variantWord,
      isPerformanceOnly: _readingKey(hafsWord) == _readingKey(variantWord),
    );
  }

  static Future<QuranRepository> load() async {
    final files = await Future.wait([
      rootBundle.loadString('assets/quran_hafs.json'),
      rootBundle.loadString('assets/quran_shubah.json'),
      rootBundle.loadString('assets/quran_qalun.json'),
      rootBundle.loadString('assets/differences_taisir.json'),
    ]);
    final hafs = _parseAyahs(files[0], isHafs: true);
    final shubah = _parseAyahs(files[1]);
    final qalun = _parseAyahs(files[2]);
    final hafsByPage = <int, List<Ayah>>{};
    for (final ayah in hafs) {
      if (ayah.page != null) (hafsByPage[ayah.page!] ??= []).add(ayah);
    }
    return QuranRepository(
      hafsByPage: hafsByPage,
      shubah: {for (final ayah in shubah) ayah.key: ayah},
      qalun: {for (final ayah in qalun) ayah.key: ayah},
      differenceWords: _parseDifferences(files[3]),
    );
  }

  static Map<MarginRiwayah, Map<String, List<int>>> _parseDifferences(
    String source,
  ) {
    final readings =
        (jsonDecode(source) as Map<String, dynamic>)['readings']
            as Map<String, dynamic>;
    Map<String, List<int>> parseReading(String name) {
      final verses = readings[name] as Map<String, dynamic>;
      return {
        for (final entry in verses.entries)
          entry.key: (entry.value as List<dynamic>)
              .cast<num>()
              .map((word) => word.toInt())
              .toList(growable: false),
      };
    }

    return {
      MarginRiwayah.shubah: parseReading('shubah'),
      MarginRiwayah.qalun: parseReading('qalun'),
    };
  }

  static List<Ayah> _parseAyahs(String source, {bool isHafs = false}) =>
      (jsonDecode(source) as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map((json) => Ayah.fromJson(json, isHafs: isHafs))
          .toList(growable: false);

  static String _wordAt(String text, int index) {
    final words = text
        .replaceAll(RegExp(r'[٠-٩]'), '')
        .trim()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList(growable: false);
    return index > 0 && index <= words.length ? words[index - 1] : '';
  }

  static String _readingKey(String text) => text
      .replaceAll(
        RegExp(r'[\u0610-\u061A\u064B-\u065F\u0670\u06D6-\u06ED]'),
        '',
      )
      .replaceAll(RegExp(r'[ٱأإآ]'), 'ا')
      .replaceAll('ى', 'ي')
      .replaceAll('ـ', '')
      .trim();
}

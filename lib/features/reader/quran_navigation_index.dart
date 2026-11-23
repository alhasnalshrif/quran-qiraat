import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:unorm_dart/unorm_dart.dart' as unicode;

import '../../data/quran_repository.dart';
import '../../domain/models/ayah.dart';
import '../../domain/models/margin_riwayah.dart';
import 'reader_library_store.dart';

String normalizeQuranSearch(String value) => unicode
    .nfd(value)
    .replaceAll(
      RegExp(
        '[\u0610-\u061a\u064b-\u065f\u0670\u06d6-\u06ed\u0640\u200e\u200f]',
      ),
      '',
    )
    .replaceAll('ٱ', 'ا')
    .replaceAll('ى', 'ي')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

class QuranNavigationIndex {
  QuranNavigationIndex(this.quran) {
    for (final page in quran.hafsLayout?.pages ?? []) {
      for (final line in page.lines) {
        for (final word in line.words) {
          final parts = word.location.split(':');
          final key = '${parts[0]}:${parts[1]}';
          _pages.putIfAbsent(key, () => page.number);
          _wordPages[word.location] = page.number;
        }
      }
    }
    final unique = <String, Ayah>{...quran.hafsByKey};
    for (final page in quran.hafsByPage.values) {
      for (final ayah in page) {
        unique[ayah.key] = ayah;
      }
    }
    ayahs = unique.values.toList()
      ..sort(
        (a, b) => a.surah == b.surah
            ? a.number.compareTo(b.number)
            : a.surah.compareTo(b.surah),
      );
    for (final ayah in ayahs) {
      _hafs[ayah.key] = ayah;
      _pages.putIfAbsent(ayah.key, () => ayah.page ?? 1);
      surahs.putIfAbsent(ayah.surah, () => ayah);
      juzs.putIfAbsent(ayah.juz, () => ayah);
    }
  }
  final QuranRepository quran;
  late final List<Ayah> ayahs;
  final surahs = <int, Ayah>{};
  final juzs = <int, Ayah>{};
  final _hafs = <String, Ayah>{};
  final _pages = <String, int>{};
  final _wordPages = <String, int>{};
  final _search = <QuranReading, List<({Ayah ayah, String normalized})>>{};
  String name(int surah) => surahs[surah]?.surahName ?? '$surah';
  ReaderLocation? firstOnPage(int page) {
    final layout = quran.hafsLayout?.page(page);
    if (layout != null) {
      for (final line in layout.lines) {
        if (line.words.isEmpty) continue;
        final parts = line.words.first.location
            .split(':')
            .map(int.parse)
            .toList();
        return locate(parts[0], parts[1], word: parts[2]);
      }
    }
    final ayahs = quran.page(page);
    return ayahs.isEmpty ? null : locate(ayahs.first.surah, ayahs.first.number);
  }

  ReaderLocation? locate(int surah, int ayah, {int? word}) {
    final key = '$surah:$ayah';
    final page = word == null ? _pages[key] : _wordPages['$key:$word'];
    if (page == null || !_hafs.containsKey(key)) return null;
    return ReaderLocation(page: page, surah: surah, ayah: ayah, word: word);
  }

  ReaderLocation? locateInReading(QuranReading reading, Ayah ayah) {
    if (reading == QuranReading.hafs) return locate(ayah.surah, ayah.number);
    final counterpart = quran
        .ayahsCorrespondingTo(
          sourceReading: reading,
          targetReading: QuranReading.hafs,
          surah: ayah.surah,
          ayah: ayah.number,
        )
        .firstOrNull;
    if (counterpart == null) return null;
    final page = _pages[counterpart.key];
    return page == null
        ? null
        : ReaderLocation(
            page: page,
            surah: ayah.surah,
            ayah: ayah.number,
            reading: reading,
          );
  }

  bool valid(ReaderLocation location) {
    if (location.reading == QuranReading.hafs) {
      return locate(location.surah, location.ayah, word: location.word)?.page ==
          location.page;
    }
    return location.word == null &&
        quran
            .pageForReading(location.reading, location.page)
            .any(
              (ayah) =>
                  ayah.surah == location.surah && ayah.number == location.ayah,
            );
  }

  List<Ayah> search(String query, {QuranReading reading = QuranReading.hafs}) {
    final needle = normalizeQuranSearch(query);
    if (needle.isEmpty) return [];
    final entries = _search.putIfAbsent(
      reading,
      () => [
        for (final ayah in switch (reading) {
          QuranReading.hafs => ayahs,
          QuranReading.shubah => quran.shubah.values,
          QuranReading.qalun => quran.qalun.values,
        })
          (
            ayah: ayah,
            normalized: normalizeQuranSearch(
              QuranRepository.comparableReadingText(ayah.comparisonText),
            ),
          ),
      ],
    );
    return [
      for (final entry in entries)
        if (entry.normalized.contains(needle)) entry.ayah,
    ];
  }

  Future<List<Ayah>> hizbs() async {
    final raw = jsonDecode(
      // Not cached: the reader loads this at start-up, and a cached future
      // must not outlive the zone that created it.
      await rootBundle.loadString(
        'assets/navigation/hafs_hizbs.json',
        cache: false,
      ),
    ) as Map<String, dynamic>;
    final starts = raw['hizb_starts'] as List;
    if (starts.length != 60 ||
        starts.toSet().length != 60 ||
        starts.any((key) => !_hafs.containsKey(key))) {
      throw const FormatException('Invalid Hizb index');
    }
    return [for (final key in starts) _hafs[key]!];
  }
}

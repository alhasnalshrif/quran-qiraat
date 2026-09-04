import 'package:flutter_test/flutter_test.dart';

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:quran_qiraat/quran_qiraat.dart';
import 'package:quran_qiraat/features/reader/mushaf_reader_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('allows page dragging with mouse and trackpad', () {
    const behavior = QuranScrollBehavior();

    expect(behavior.dragDevices, contains(PointerDeviceKind.mouse));
    expect(behavior.dragDevices, contains(PointerDeviceKind.trackpad));
  });

  test('shows imported difference locations in the margin', () {
    const quran = QuranRepository(
      hafsByPage: {},
      shubah: {},
      qalun: {},
      differenceWords: {
        MarginRiwayah.shubah: {
          '2:255': [3],
        },
      },
    );
    const ayah = Ayah(
      surah: 2,
      number: 255,
      page: 42,
      text: 'test',
      comparisonText: 'test',
    );

    expect(quran.hasDifference(MarginRiwayah.shubah, ayah), isTrue);
    expect(quran.wordsFor(MarginRiwayah.shubah, ayah), [3]);
    expect(quran.hasDifference(MarginRiwayah.qalun, ayah), isFalse);
  });

  test('labels the actual Hafs and margin-reading words', () {
    const quran = QuranRepository(hafsByPage: {}, shubah: {}, qalun: {});
    const hafs = Ayah(
      surah: 20,
      number: 10,
      page: 312,
      text: 'test',
      comparisonText: 'إذ رأى نارا',
    );
    const shubah = Ayah(
      surah: 20,
      number: 10,
      page: 312,
      text: 'test',
      comparisonText: 'إذ رٜءٜا نارا',
    );

    final result = quran.comparedWord(
      hafs: hafs,
      variant: shubah,
      wordIndex: 2,
    );

    expect(result.hafs, 'رأى');
    expect(result.variant, 'رٜءٜا');
    expect(result.isPerformanceOnly, isFalse);
  });

  testWidgets('shows the offline Quran reader', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    const quran = QuranRepository(hafsByPage: {}, shubah: {}, qalun: {});
    await tester.pumpWidget(
      QuranQiraatApp(preferences: preferences, quran: quran),
    );

    expect(find.text('مصحف القراءات'), findsOneWidget);
    expect(find.text('القراءة'), findsOneWidget);
    expect(find.text('حفص عن عاصم'), findsOneWidget);
    expect(
      Directionality.of(tester.element(find.byType(Scaffold))),
      TextDirection.rtl,
    );
  });

  testWidgets('renders Hafs using source-defined lines rather than flow text', (
    tester,
  ) async {
    final layout = MushafLayout(
      editionId: 'hafs_madani_604',
      sourceCommit: 'test',
      pages: List.generate(
        604,
        (index) => MushafLayoutPage(
          number: index + 1,
          lines: index == 0
              ? const [
                  MushafLayoutLine(
                    number: 1,
                    type: MushafLayoutLineType.surahHeader,
                    text: 'سورة الفاتحة',
                  ),
                  MushafLayoutLine(
                    number: 2,
                    type: MushafLayoutLineType.text,
                    text: 'ٱلْحَمْدُ لِلَّهِ رَبِّ ٱلْعَـٰلَمِينَ',
                    words: [
                      MushafLayoutWord(location: '1:2:1', text: 'ٱلْحَمْدُ'),
                    ],
                  ),
                ]
              : const [
                  MushafLayoutLine(
                    number: 1,
                    type: MushafLayoutLineType.text,
                    text: 'نص',
                    words: [MushafLayoutWord(location: '1:1:1', text: 'نص')],
                  ),
                ],
        ),
      ),
    );
    final quran = QuranRepository(
      hafsByPage: const {},
      shubah: const {},
      qalun: const {},
      hafsLayout: layout,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: QuranTextPage(
          page: 1,
          reading: QuranReading.hafs,
          highlightRiwayah: MarginRiwayah.shubah,
          quran: quran,
        ),
      ),
    );

    expect(find.byKey(const ValueKey('mushaf-line-1-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('mushaf-line-1-2')), findsOneWidget);
    expect(find.text('ٱلْحَمْدُ لِلَّهِ رَبِّ ٱلْعَـٰلَمِينَ'), findsOneWidget);
  });
}

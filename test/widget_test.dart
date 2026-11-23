import 'package:flutter_test/flutter_test.dart';

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:quran_qiraat/quran_qiraat.dart';
import 'package:quran_qiraat/features/reader/mushaf_reader_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'reader_test_controls.dart';

void main() {
  test('allows page dragging with mouse and trackpad', () {
    const behavior = QuranScrollBehavior();

    expect(behavior.dragDevices, contains(PointerDeviceKind.mouse));
    expect(behavior.dragDevices, contains(PointerDeviceKind.trackpad));
  });

  testWidgets('shows the offline Quran reader', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    const quran = QuranRepository(hafsByPage: {}, shubah: {}, qalun: {});
    await tester.pumpWidget(
      QuranQiraatApp(preferences: preferences, quran: quran),
    );

    const controls = ValueKey('reader-bottom-chrome');
    final toggle = find.text('أدوات القراءة');
    expect(find.byKey(controls), findsNothing);
    expect(toggle, findsNothing);
    final readingBounds = tester.getRect(find.byType(PageView));
    await tapReaderToToggleControls(tester);
    expect(find.byKey(controls), findsOneWidget);
    expect(tester.getRect(find.byType(PageView)), readingBounds);
    expect(
      tester.getRect(find.byKey(controls)).bottom,
      lessThan(readingBounds.bottom),
    );
    expect(toggle, findsNothing);
    await tapReaderToToggleControls(tester);
    expect(find.byKey(controls), findsNothing);
    expect(tester.getRect(find.byType(PageView)), readingBounds);
    await tapReaderToToggleControls(tester);
    expect(find.text('القراءتان'), findsOneWidget);
    expect(find.text('حفص × شعبة'), findsOneWidget);
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
          comparisonReading: QuranReading.shubah,
          quran: quran,
        ),
      ),
    );

    expect(find.byKey(const ValueKey('mushaf-line-1-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('mushaf-line-1-2')), findsOneWidget);
    expect(find.text('ٱلْحَمْدُ'), findsOneWidget);

    await tester.longPress(find.text('ٱلْحَمْدُ'));
    await tester.pumpAndSettle();
    expect(find.text('موضع 1:2:1'), findsOneWidget);
    expect(find.text('لا يذكر الفرش خلافًا في هذه الكلمة.'), findsOneWidget);
  });

  testWidgets('keeps Mushaf line slots fixed while fitting long text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const shortWord = MushafLayoutWord(location: '1:1:1', text: 'الحمد');
    final longWords = List.generate(
      14,
      (index) => MushafLayoutWord(
        location: '1:2:${index + 1}',
        text: 'وَٱلْمُسْتَغْفِرِينَ',
      ),
    );
    final layout = MushafLayout(
      editionId: 'test',
      sourceCommit: 'test',
      pages: [
        MushafLayoutPage(
          number: 1,
          lines: [
            const MushafLayoutLine(
              number: 1,
              type: MushafLayoutLineType.text,
              text: 'الحمد',
              words: [shortWord],
            ),
            MushafLayoutLine(
              number: 2,
              type: MushafLayoutLineType.text,
              text: longWords.map((word) => word.text).join(' '),
              words: longWords,
            ),
          ],
        ),
      ],
    );
    final repository = QuranRepository(
      hafsByPage: const {},
      shubah: const {},
      qalun: const {},
      hafsLayout: layout,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: QuranTextPage(
            page: 1,
            reading: QuranReading.hafs,
            comparisonReading: QuranReading.shubah,
            quran: repository,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final shortLine = find.byKey(const ValueKey('mushaf-line-1-1'));
    final longLine = find.byKey(const ValueKey('mushaf-line-1-2'));
    expect(tester.takeException(), isNull);
    expect(tester.getSize(shortLine).height, tester.getSize(longLine).height);
    expect(tester.getSize(longLine).width, lessThanOrEqualTo(320));
  });
}

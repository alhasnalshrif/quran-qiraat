import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quran_qiraat/app/quran_bootstrap.dart';
import 'package:quran_qiraat/features/reader/mushaf_reader_page.dart';
import 'package:quran_qiraat/features/reader/page_input.dart';
import 'package:quran_qiraat/quran_qiraat.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'reader_test_controls.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late QuranRepository bundled;
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async => bundled = await QuranRepository.load());

  test(
    'bundled page comparisons use real reading pairs in all six directions',
    () {
      for (final base in QuranReading.values) {
        for (final target in QuranReading.values.where(
          (value) => value != base,
        )) {
          final page = bundled.textDifferencesOnPage(base, target, 1);
          expect(page.changed, isNotEmpty, reason: '$base → $target');
          final refs = <String>{};
          for (final pair in page.changed) {
            expect(pair.baseReading, base);
            expect(pair.targetReading, target);
            expect(
              refs.add(
                '${pair.baseSurah}:${pair.baseAyah}:${pair.baseAyahEnd}',
              ),
              isTrue,
            );
            expect(
              QuranRepository.comparableReadingText(pair.baseText),
              isNot(QuranRepository.comparableReadingText(pair.targetText)),
            );
          }
        }
      }
      final towardQalun = bundled.textDifferencesOnPage(
        QuranReading.shubah,
        QuranReading.qalun,
        1,
      );
      final malik = towardQalun.changed.singleWhere(
        (pair) => pair.baseAyah == 4,
      );
      expect(malik.targetAyah, 3);
      expect(towardQalun.unpaired.map((ayah) => ayah.key), contains('1:1'));
      final fromHafs = bundled.textDifferencesOnPage(
        QuranReading.hafs,
        QuranReading.qalun,
        1,
      );
      expect(
        fromHafs.changed.singleWhere((pair) => pair.baseAyah == 4).baseText,
        contains('ِ'),
      );
      expect(bundled.publishedDifferences, isEmpty);
    },
  );

  testWidgets(
    'differences panel opens regular text comparison for Shubah and Qalun',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'primary_reading': 'shubah',
        'comparison_reading': 'qalun',
      });
      final preferences = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        QuranQiraatApp(preferences: preferences, quran: bundled),
      );
      await tapReaderToToggleControls(tester);
      await tester.tap(find.byTooltip('فروق الصفحة'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('قارن نصوص الآيات'),
        80,
        scrollable: find
            .descendant(
              of: find.byType(Drawer),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(find.text('قارن نصوص الآيات'));
      await tester.pumpAndSettle();
      expect(find.text('المقارنة النصية · صفحة 1'), findsOneWidget);
      await tester.tap(find.text('شعبة 1:4\nقالون 1:3'));
      await tester.pumpAndSettle();
      expect(find.text('عرض النصين والمواضع المقترحة'), findsWidgets);
      await tester.tap(find.byTooltip('المصادر وحالة المراجعة'));
      await tester.pumpAndSettle();
      expect(
        find.text('لا توجد فروق منشورة بمراجعة متخصصة في هذه النسخة.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  test('every page index matches the displayed layout in source order', () {
    for (final page in bundled.hafsLayout!.pages) {
      final keys = <String>{};
      for (final line in page.lines) {
        for (final word in line.words) {
          keys.add(word.location.split(':').take(2).join(':'));
        }
      }
      expect(
        bundled.page(page.number).map((a) => a.key),
        keys,
        reason: 'page ${page.number}',
      );
    }
    expect(bundled.page(121).any((a) => a.key == '5:77'), isTrue);
  });

  test('candidate cards belong to the actual page of their source word', () {
    final locations = <String, Set<int>>{};
    for (final page in bundled.hafsLayout!.pages) {
      for (final line in page.lines) {
        for (final word in line.words) {
          (locations[word.location] ??= {}).add(page.number);
        }
      }
    }
    for (final reading in MarginRiwayah.values) {
      final displayed = <String, Set<int>>{};
      for (var page = 1; page <= 604; page++) {
        for (final candidate in bundled.candidateDifferencesOnPage(
          reading,
          page,
        )) {
          (displayed[candidate.id] ??= {}).add(page);
        }
      }
      for (final candidate in bundled.candidateDifferences.where(
        (c) => c.sourceReading == reading,
      )) {
        expect(
          displayed[candidate.id] ?? <int>{},
          locations['${candidate.hafsAyahKey}:${candidate.rawWordIndex}'] ??
              <int>{},
          reason: candidate.id,
        );
      }
    }
    expect(
      bundled
          .candidateDifferencesOnPage(MarginRiwayah.qalun, 584)
          .any((c) => c.id == 'taisir_qalun_79_16_6'),
      isTrue,
    );
    expect(
      bundled
          .candidateDifferencesOnPage(MarginRiwayah.qalun, 583)
          .any((c) => c.id == 'taisir_qalun_79_16_6'),
      isFalse,
    );
  });

  test(
    'Qalun correspondence uses mapped numbering without a shared-key fallback',
    () {
      List<Ayah> counterparts(QuranRepository quran) =>
          quran.ayahsCorrespondingTo(
            sourceReading: QuranReading.hafs,
            targetReading: QuranReading.qalun,
            surah: 1,
            ayah: 4,
          );
      expect(counterparts(bundled).single.number, 3);
      final unlinked = QuranRepository(
        hafsByPage: {
          1: [bundled.hafsByKey['1:4']!],
        },
        shubah: {},
        qalun: bundled.qalun,
      );
      expect(counterparts(unlinked), isEmpty);
    },
  );

  test('Shubah/Qalun composes only the explicit ayah correspondence in both directions', () {
    expect(
      bundled
          .ayahsCorrespondingTo(
            sourceReading: QuranReading.shubah,
            targetReading: QuranReading.qalun,
            surah: 1,
            ayah: 4,
          )
          .single
          .number,
      3,
    );
    expect(
      bundled
          .ayahsCorrespondingTo(
            sourceReading: QuranReading.qalun,
            targetReading: QuranReading.shubah,
            surah: 1,
            ayah: 3,
          )
          .single
          .number,
      4,
    );
    final forward = bundled.alignmentProposal(
      sourceReading: QuranReading.shubah,
      targetReading: QuranReading.qalun,
      surah: 1,
      ayah: 4,
    )!;
    final reverse = bundled.alignmentProposal(
      sourceReading: QuranReading.qalun,
      targetReading: QuranReading.shubah,
      surah: 1,
      ayah: 3,
    )!;
    expect(forward.pair.baseReading, QuranReading.shubah);
    expect(forward.pair.targetAyah, 3);
    expect(reverse.pair.targetReading, QuranReading.shubah);
    expect(reverse.pair.targetAyah, 4);
  });

  test('split ayah comparison preserves all counterpart ayahs', () {
    expect(
      bundled
          .ayahsCorrespondingTo(
            sourceReading: QuranReading.hafs,
            targetReading: QuranReading.qalun,
            surah: 1,
            ayah: 7,
          )
          .map((a) => a.number),
      [6, 7],
    );
  });

  ReadingDifference fixture({bool published = true, int word = 1}) =>
      ReadingDifference(
        id: 'synthetic',
        baseReading: QuranReading.hafs,
        targetReading: QuranReading.qalun,
        baseSpan: ReadingWordSpan.singleWord(
          reading: QuranReading.hafs,
          surah: 1,
          ayah: 4,
          wordIndex: word,
          text: 'مالك',
        ),
        targetSpan: ReadingWordSpan.singleWord(
          reading: QuranReading.qalun,
          surah: 1,
          ayah: 3,
          wordIndex: word,
          text: 'ملك',
        ),
        reviewStatus: published
            ? DifferenceReviewStatus.published
            : DifferenceReviewStatus.candidate,
        reviewer: published ? 'Synthetic test fixture' : null,
        reviewDate: published ? DateTime.utc(2026, 1, 1) : null,
      );

  test('unreviewed records cannot escape through any published API', () {
    final hafs = bundled.hafsByKey['1:4']!;
    final q = QuranRepository(
      hafsByPage: {
        1: [hafs],
      },
      shubah: {},
      qalun: bundled.qalun,
      ayahCorrespondences: bundled.ayahCorrespondences,
      publishedDifferences: [fixture(published: false)],
    );
    expect(
      q.publishedDifferenceForWord(
        baseReading: QuranReading.hafs,
        comparisonReading: QuranReading.qalun,
        surah: 1,
        ayah: 4,
        wordIndex: 1,
      ),
      isNull,
    );
    expect(
      q.publishedDifferencesForPairOnPage(
        QuranReading.hafs,
        QuranReading.qalun,
        1,
      ),
      isEmpty,
    );
  });

  test('review metadata and reading/span identity are checked at runtime', () {
    final data = fixture().toJson();
    expect(
      () => ReadingDifference.fromJson({...data, 'reviewer': ''}),
      throwsFormatException,
    );
    expect(
      () => ReadingDifference.fromJson({...data, 'review_date': '2026-02-31'}),
      throwsFormatException,
    );
    expect(
      () => ReadingDifference.published(
        id: 'no-review',
        targetReading: QuranReading.qalun,
        baseSpan: fixture().baseSpan,
        targetSpan: fixture().targetSpan,
      ),
      throwsFormatException,
    );
    expect(
      () => ReadingDifference.fromJson({...data, 'target_reading': 'shubah'}),
      throwsFormatException,
    );
  });

  test('published importer rejects candidates, duplicate IDs, invalid indices and mismatched text', () {
    final maps = {
      QuranReading.hafs: bundled.hafsByKey,
      QuranReading.shubah: bundled.shubah,
      QuranReading.qalun: bundled.qalun,
    };
    final valid = fixture().toJson();
    valid['target_span'] = {
      ...fixture().targetSpan.toJson(),
      'text': const ReadingAlignmentEngine()
          .tokenize(bundled.qalun['1:3']!.comparisonText)
          .first
          .text,
    };
    String bundle(List<Object> records) =>
        jsonEncode({'schema_version': '1.0.0', 'records': records});
    expect(
      QuranRepository.parsePublishedDifferences(bundle([valid]), ayahs: maps),
      hasLength(1),
    );
    expect(
      () => QuranRepository.parsePublishedDifferences(
        bundle([valid, valid]),
        ayahs: maps,
      ),
      throwsFormatException,
    );
    expect(
      () => QuranRepository.parsePublishedDifferences(
        bundle([fixture(published: false).toJson()]),
        ayahs: maps,
      ),
      throwsFormatException,
    );
    expect(
      () => QuranRepository.parsePublishedDifferences(
        bundle([fixture(word: 100).toJson()]),
        ayahs: maps,
      ),
      throwsFormatException,
    );
    expect(
      () => QuranRepository.parsePublishedDifferences(
        bundle([fixture().toJson()]),
        ayahs: maps,
      ),
      throwsFormatException,
    );
  });

  test('published page lookup follows source word layout and is symmetric', () {
    final record = ReadingDifference.published(
      id: 'page-fixture',
      reviewer: 'Synthetic test fixture',
      reviewDate: DateTime.utc(2026, 1, 1),
      targetReading: QuranReading.qalun,
      baseSpan: ReadingWordSpan.singleWord(
        reading: QuranReading.hafs,
        surah: 79,
        ayah: 16,
        wordIndex: 6,
        text: 'synthetic',
      ),
      targetSpan: ReadingWordSpan.singleWord(
        reading: QuranReading.qalun,
        surah: 79,
        ayah: 16,
        wordIndex: 6,
        text: 'synthetic',
      ),
    );
    final q = QuranRepository(
      hafsByPage: bundled.hafsByPage,
      shubah: bundled.shubah,
      qalun: bundled.qalun,
      hafsLayout: bundled.hafsLayout,
      publishedDifferences: [record],
    );
    expect(
      q.publishedDifferencesForPairOnPage(
        QuranReading.hafs,
        QuranReading.qalun,
        583,
      ),
      isEmpty,
    );
    expect(
      q.publishedDifferencesForPairOnPage(
        QuranReading.hafs,
        QuranReading.qalun,
        584,
      ),
      [record],
    );
    expect(
      q.publishedDifferencesForPairOnPage(
        QuranReading.qalun,
        QuranReading.hafs,
        584,
      ),
      [record],
    );
  });

  test('alignment results are reused within the same repository', () {
    final a = bundled.alignmentProposal(
      sourceReading: QuranReading.hafs,
      targetReading: QuranReading.qalun,
      surah: 1,
      ayah: 4,
    );
    final b = bundled.alignmentProposal(
      sourceReading: QuranReading.hafs,
      targetReading: QuranReading.qalun,
      surah: 1,
      ayah: 4,
    );
    expect(identical(a, b), isTrue);
  });

  testWidgets(
    'word gesture recognizers survive rebuilds and release pending gestures on removal',
    (tester) async {
      Widget page() => MaterialApp(
        home: Scaffold(
          body: QuranTextPage(
            page: 1,
            reading: QuranReading.hafs,
            comparisonReading: QuranReading.qalun,
            quran: bundled,
          ),
        ),
      );
      Object? recognizerIn(InlineSpan span) {
        if (span is! TextSpan) return null;
        if (span.recognizer != null) return span.recognizer;
        for (final child in span.children ?? const <InlineSpan>[]) {
          final recognizer = recognizerIn(child);
          if (recognizer != null) return recognizer;
        }
        return null;
      }

      Object? firstRecognizer() {
        for (final rich in tester.widgetList<RichText>(find.byType(RichText))) {
          final recognizer = recognizerIn(rich.text);
          if (recognizer != null) return recognizer;
        }
        return null;
      }

      await tester.pumpWidget(page());
      final recognizer = firstRecognizer();
      expect(recognizer, isNotNull);
      await tester.pumpWidget(page());
      expect(identical(firstRecognizer(), recognizer), isTrue);
      final paragraph = find
          .byWidgetPredicate(
            (widget) => widget is RichText && recognizerIn(widget.text) != null,
          )
          .first;
      final gesture = await tester.startGesture(tester.getCenter(paragraph));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 700));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'page input accepts Arabic/Persian digits and rejects invalid input',
    () {
      expect(parseMushafPage(' ١٢٣ '), 123);
      expect(parseMushafPage('۶۰۴'), 604);
      for (final input in ['', '0', '-1', '605', '1.5', '+1', 'abc']) {
        expect(parseMushafPage(input), isNull, reason: input);
      }
    },
  );

  testWidgets(
    'invalid saved page is clamped and invalid entry stays open with feedback',
    (tester) async {
      SharedPreferences.setMockInitialValues({'last_page': -7});
      await tester.pumpWidget(
        QuranQiraatApp(
          preferences: await SharedPreferences.getInstance(),
          quran: bundled,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tapReaderToToggleControls(tester);
      await tester.tap(find.text('صفحة 1'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '٦٠٥');
      await tester.tap(find.text('انتقال'));
      await tester.pumpAndSettle();
      expect(find.text('أدخل رقم صفحة من 1 إلى 604'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '١٢٣');
      await tester.tap(find.text('انتقال'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('reverse pair displays reviewed text in selected reading order', (
    tester,
  ) async {
    final record = fixture();
    final q = QuranRepository(
      hafsByPage: {
        1: [bundled.hafsByKey['1:4']!],
      },
      shubah: {},
      qalun: bundled.qalun,
      publishedDifferences: [record],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DifferencesPanel(
            page: 1,
            baseReading: QuranReading.qalun,
            comparisonReading: QuranReading.hafs,
            quran: q,
            onClose: () {},
          ),
        ),
      ),
    );
    expect(find.text('قالون: ملك'), findsOneWidget);
    expect(find.text('حفص: مالك'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('قالون: ملك')).dy,
      lessThan(tester.getTopLeft(find.text('حفص: مالك')).dy),
    );
  });

  testWidgets(
    'bootstrap exposes loading, failure and retry before opening the reader',
    (tester) async {
      final completer = Completer<QuranSession>();
      var attempts = 0;
      await tester.pumpWidget(
        QuranBootstrap(
          loader: () {
            attempts++;
            return attempts == 1
                ? completer.future
                : Future.value((
                    preferences: SharedPreferences.getInstance(),
                    quran: bundled,
                  )).then(
                    (value) async => (
                      preferences: await value.preferences,
                      quran: value.quran,
                    ),
                  );
          },
        ),
      );
      expect(find.text('جارٍ تحميل المصحف'), findsOneWidget);
      completer.completeError(const FormatException('synthetic missing asset'));
      await tester.pumpAndSettle();
      expect(find.text('إعادة المحاولة'), findsOneWidget);
      await tester.tap(find.text('إعادة المحاولة'));
      await tester.pumpAndSettle();
      expect(find.byType(MushafReaderPage), findsOneWidget);
      expect(attempts, 2);
    },
  );
}

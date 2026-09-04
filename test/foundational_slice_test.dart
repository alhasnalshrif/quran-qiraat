import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quran_qiraat/quran_qiraat.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('Domain models and manifest', () {
    test('manifest designates the bundled Hafs line layout and navigation', () {
      const manifest = MushafManifest.bundledDefault;

      final hafs = manifest.editionFor(QuranReading.hafs);
      final shubah = manifest.editionFor(QuranReading.shubah);
      final qalun = manifest.editionFor(QuranReading.qalun);

      expect(hafs, isNotNull);
      expect(hafs!.isPageLayoutCapable, isTrue);
      expect(hafs.targetPageLayout, 'madani_604');
      expect(hafs.supportsPageNavigation, isTrue);
      expect(hafs.isTextComparisonCapable, isTrue);
      expect(hafs.totalAyahs, 6236);
      expect(hafs.pageCount, 604);
      expect(manifest.isLayoutCapable(QuranReading.hafs), isTrue);
      expect(manifest.supportsPageNavigation(QuranReading.hafs), isTrue);

      expect(shubah, isNotNull);
      expect(shubah!.isPageLayoutCapable, isFalse);
      expect(shubah.targetPageLayout, isNull);
      expect(shubah.supportsPageNavigation, isFalse);
      expect(shubah.isTextComparisonCapable, isTrue);
      expect(shubah.totalAyahs, 6236);
      expect(shubah.pageCount, isNull);

      expect(qalun, isNotNull);
      expect(qalun!.isPageLayoutCapable, isFalse);
      expect(qalun.targetPageLayout, isNull);
      expect(qalun.supportsPageNavigation, isFalse);
      expect(qalun.isTextComparisonCapable, isTrue);
      expect(qalun.totalAyahs, 6214);
      expect(qalun.pageCount, isNull);

      expect(manifest.candidateSources, isNotEmpty);
      expect(manifest.candidateSources.first.status, 'candidate_unreviewed');
    });

    test('bundled Hafs layout has all source-pinned pages and preserves structural lines', () async {
      final layout = await MushafLayoutRepository.loadHafsMadani604();

      expect(layout.editionId, 'hafs_madani_604');
      expect(layout.pages, hasLength(604));
      expect(layout.sourceCommit, '72116ce4d405d67823804f0eed795c1e6409b4af');
      expect(layout.page(1)!.lines, isNotEmpty);
      expect(
        layout
            .page(2)!
            .lines
            .any((line) => line.type == MushafLayoutLineType.basmala),
        isTrue,
      );
      expect(layout.page(604)!.number, 604);
      expect(
        layout
            .page(2)!
            .lines
            .where((line) => line.type == MushafLayoutLineType.text)
            .first
            .words
            .first
            .location,
        '2:1:1',
      );
    });

    test('CandidateDifferenceRecord models raw locator without asserted target span or performance classification', () {
      const candidate = CandidateDifferenceRecord(
        id: 'cand_1',
        sourceId: 'differences_taisir',
        sourceReading: MarginRiwayah.shubah,
        surah: 1,
        hafsAyah: 4,
        hafsPage: 1,
        rawWordIndex: 1,
        provenance: 'Corpus Coranicum ad-Dānī at-Taysīr',
      );

      expect(candidate.sourceReading, MarginRiwayah.shubah);
      expect(candidate.surah, 1);
      expect(candidate.hafsAyah, 4);
      expect(candidate.hafsPage, 1);
      expect(candidate.rawWordIndex, 1);
      expect(candidate.hafsAyahKey, '1:4');
      expect(candidate.provenance, contains('Taysīr'));

      // Proves that candidate records do not assert a cross-reading target span or performance classification.
      final json = candidate.toJson();
      expect(json.containsKey('target_span'), isFalse);
      expect(json.containsKey('target_text'), isFalse);
      expect(json.containsKey('is_performance_only'), isFalse);
    });

    test('supports 1:1, 1:N, N:1 alignment cardinalities for published differences', () {
      final oneToOne = ReadingDifference.published(
        id: '1',
        targetReading: QuranReading.shubah,
        baseSpan: ReadingWordSpan.singleWord(
          reading: QuranReading.hafs,
          surah: 1,
          ayah: 4,
          wordIndex: 1,
          text: 'مَالِكِ',
        ),
        targetSpan: ReadingWordSpan.singleWord(
          reading: QuranReading.shubah,
          surah: 1,
          ayah: 4,
          wordIndex: 1,
          text: 'مَلِكِ',
        ),
      );
      expect(oneToOne.cardinality, AlignmentCardinality.oneToOne);
      expect(oneToOne.isOneToOne, isTrue);
      expect(oneToOne.isOneToMany, isFalse);

      final oneToMany = ReadingDifference.published(
        id: '2',
        targetReading: QuranReading.qalun,
        baseSpan: ReadingWordSpan.singleWord(
          reading: QuranReading.hafs,
          surah: 2,
          ayah: 20,
          wordIndex: 5,
          text: 'كَلِمَةً',
        ),
        targetSpan: const ReadingWordSpan(
          reading: QuranReading.qalun,
          surah: 2,
          ayah: 20,
          startWordIndex: 5,
          endWordIndex: 6,
          text: 'كَلِمَةً وَاحِدَةً',
        ),
      );
      expect(oneToMany.cardinality, AlignmentCardinality.oneToMany);
      expect(oneToMany.isOneToMany, isTrue);
      expect(oneToMany.isOneToOne, isFalse);

      final manyToOne = ReadingDifference.published(
        id: '3',
        targetReading: QuranReading.shubah,
        baseSpan: const ReadingWordSpan(
          reading: QuranReading.hafs,
          surah: 3,
          ayah: 15,
          startWordIndex: 2,
          endWordIndex: 3,
          text: 'فِي سَبِيلِ',
        ),
        targetSpan: ReadingWordSpan.singleWord(
          reading: QuranReading.shubah,
          surah: 3,
          ayah: 15,
          wordIndex: 2,
          text: 'بِسَبِيلِ',
        ),
      );
      expect(manyToOne.cardinality, AlignmentCardinality.manyToOne);
      expect(manyToOne.isManyToOne, isTrue);
    });

    test('supports performance-only difference flag', () {
      final perfDiff = ReadingDifference.published(
        id: 'perf_1',
        targetReading: QuranReading.shubah,
        baseSpan: ReadingWordSpan.singleWord(
          reading: QuranReading.hafs,
          surah: 20,
          ayah: 10,
          wordIndex: 2,
          text: 'رَأَىٰ',
        ),
        targetSpan: ReadingWordSpan.singleWord(
          reading: QuranReading.shubah,
          surah: 20,
          ayah: 10,
          wordIndex: 2,
          text: 'رَءَا',
        ),
        isPerformanceOnly: true,
        scholarlyNotes: 'إمالة فتحة الراء والهمزة والألف بعدها',
      );

      expect(perfDiff.isPerformanceOnly, isTrue);
      final comparison = WordComparison.fromReadingDifference(perfDiff);
      expect(comparison.isPerformanceOnly, isTrue);
      expect(comparison.scholarlyNotes, contains('إمالة'));
    });
  });

  group('Candidate vs Published Difference Separation', () {
    const hafsAyah = Ayah(
      surah: 1,
      number: 4,
      page: 1,
      text: 'مَالِكِ يَوْمِ الدِّينِ',
      comparisonText: 'مالك يوم الدين',
      surahName: 'الفاتحة',
    );
    const shubahAyah = Ayah(
      surah: 1,
      number: 4,
      page: 1,
      text: 'مَلِكِ يَوْمِ الدِّينِ',
      comparisonText: 'ملك يوم الدين',
      surahName: 'الفاتحة',
    );

    test(
      'candidate differences are hidden from public display and highlight',
      () {
        const candidateRecord = CandidateDifferenceRecord(
          id: 'candidate_1',
          sourceId: 'differences_taisir',
          sourceReading: MarginRiwayah.shubah,
          surah: 1,
          hafsAyah: 4,
          hafsPage: 1,
          rawWordIndex: 1,
        );

        final quran = QuranRepository(
          hafsByPage: {
            1: [hafsAyah],
          },
          shubah: {'1:4': shubahAyah},
          qalun: {},
          publishedDifferences: const [],
          candidateDifferences: [candidateRecord],
        );

        // Candidate locator is recorded internally
        expect(
          quran.hasCandidateDifference(MarginRiwayah.shubah, hafsAyah),
          isTrue,
        );
        expect(
          quran.hasCandidateDifferencesOnPage(MarginRiwayah.shubah, 1),
          isTrue,
        );

        // But candidate is NOT returned to end-user as published difference
        expect(
          quran.hasPublishedDifference(MarginRiwayah.shubah, hafsAyah),
          isFalse,
        );
        expect(
          quran.hasPublishedDifferencesOnPage(MarginRiwayah.shubah, 1),
          isFalse,
        );
        expect(quran.differencesFor(MarginRiwayah.shubah, [hafsAyah]), isEmpty);
        expect(
          quran.highlightedWordsFor(MarginRiwayah.shubah, hafsAyah),
          isEmpty,
        );
      },
    );

    test(
      'reviewed/published span differences are returned and highlighted',
      () {
        final publishedDiff = ReadingDifference.published(
          id: 'pub_1',
          targetReading: QuranReading.shubah,
          baseSpan: ReadingWordSpan.singleWord(
            reading: QuranReading.hafs,
            surah: 1,
            ayah: 4,
            wordIndex: 1,
            text: 'مَالِكِ',
          ),
          targetSpan: ReadingWordSpan.singleWord(
            reading: QuranReading.shubah,
            surah: 1,
            ayah: 4,
            wordIndex: 1,
            text: 'مَلِكِ',
          ),
        );

        final quran = QuranRepository(
          hafsByPage: {
            1: [hafsAyah],
          },
          shubah: {'1:4': shubahAyah},
          qalun: {},
          publishedDifferences: [publishedDiff],
          candidateDifferences: const [],
        );

        expect(
          quran.hasPublishedDifference(MarginRiwayah.shubah, hafsAyah),
          isTrue,
        );
        expect(
          quran.hasPublishedDifferencesOnPage(MarginRiwayah.shubah, 1),
          isTrue,
        );
        expect(quran.highlightedWordsFor(MarginRiwayah.shubah, hafsAyah), [1]);

        final differences = quran.differencesFor(MarginRiwayah.shubah, [
          hafsAyah,
        ]);
        expect(differences.length, 1);
        expect(differences.first.difference, equals(publishedDiff));
      },
    );
  });

  group('UI behavior and disclosures', () {
    const hafsAyah = Ayah(
      surah: 1,
      number: 1,
      page: 1,
      text: 'بِسْمِ اللَّهِ الرَّحْمَنِ الرَّحِيمِ',
      comparisonText: 'بسم الله الرحمن الرحيم',
      surahName: 'الفاتحة',
    );
    const shubahAyah = Ayah(
      surah: 1,
      number: 1,
      page: 1,
      text: 'بِسْمِ اللَّهِ الرَّحْمَنِ الرَّحِيمِ',
      comparisonText: 'بسم الله الرحمن الرحيم',
      surahName: 'الفاتحة',
    );

    testWidgets(
      'shows Arabic disclosure when Shubah or Qalun reading is selected',
      (tester) async {
        SharedPreferences.setMockInitialValues({
          'primary_reading': 'shubah',
          'last_page': 1,
        });
        final preferences = await SharedPreferences.getInstance();

        final quran = QuranRepository(
          hafsByPage: {
            1: [hafsAyah],
          },
          shubah: {'1:1': shubahAyah},
          qalun: {},
        );

        await tester.pumpWidget(
          QuranQiraatApp(preferences: preferences, quran: quran),
        );
        await tester.pumpAndSettle();

        // Disclosure banner must be visible
        expect(
          find.textContaining('عرض مقارنة نصية لآيات صفحة حفص'),
          findsOneWidget,
        );
        expect(
          find.textContaining('لا يطابق تخطيط صفحات مصحف شعبة'),
          findsOneWidget,
        );
      },
    );

    testWidgets('hides disclosure when Hafs reading is selected', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        'primary_reading': 'hafs',
        'last_page': 1,
      });
      final preferences = await SharedPreferences.getInstance();

      final quran = QuranRepository(
        hafsByPage: {
          1: [hafsAyah],
        },
        shubah: {'1:1': shubahAyah},
        qalun: {},
      );

      await tester.pumpWidget(
        QuranQiraatApp(preferences: preferences, quran: quran),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('عرض مقارنة نصية لآيات صفحة حفص'),
        findsNothing,
      );
    });

    testWidgets(
      'drawer distinguishes candidate unreviewed data from no differences',
      (tester) async {
        SharedPreferences.setMockInitialValues({
          'primary_reading': 'hafs',
          'last_page': 1,
        });
        final preferences = await SharedPreferences.getInstance();

        // Case A: Raw candidate locator exists on page 1
        const candidateRecord = CandidateDifferenceRecord(
          id: 'cand_1',
          sourceId: 'differences_taisir',
          sourceReading: MarginRiwayah.shubah,
          surah: 1,
          hafsAyah: 1,
          hafsPage: 1,
          rawWordIndex: 1,
        );

        final quranWithCandidate = QuranRepository(
          hafsByPage: {
            1: [hafsAyah],
          },
          shubah: {'1:1': shubahAyah},
          qalun: {},
          candidateDifferences: const [candidateRecord],
          publishedDifferences: const [],
        );

        await tester.pumpWidget(
          QuranQiraatApp(preferences: preferences, quran: quranWithCandidate),
        );
        await tester.pumpAndSettle();

        // Open differences drawer
        await tester.tap(find.text('الفروق'));
        await tester.pumpAndSettle();

        // Must clearly state data is unreviewed candidate data and not published
        expect(find.text('بيانات قيد المراجعة العلمية'), findsOneWidget);
        expect(
          find.text('البيانات المرشحة لا تُعرض كفروق منشورة'),
          findsOneWidget,
        );
        expect(find.text('لا توجد فروق معتمدة في هذه الصفحة'), findsNothing);
      },
    );

    testWidgets(
      'drawer accurately reports when no differences or candidates exist',
      (tester) async {
        SharedPreferences.setMockInitialValues({
          'primary_reading': 'hafs',
          'last_page': 1,
        });
        final preferences = await SharedPreferences.getInstance();

        final cleanQuran = QuranRepository(
          hafsByPage: {
            1: [hafsAyah],
          },
          shubah: {'1:1': shubahAyah},
          qalun: {},
          candidateDifferences: const [],
          publishedDifferences: const [],
        );

        await tester.pumpWidget(
          QuranQiraatApp(preferences: preferences, quran: cleanQuran),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('الفروق'));
        await tester.pumpAndSettle();

        expect(find.text('لا توجد فروق معتمدة في هذه الصفحة'), findsOneWidget);
        expect(find.text('بيانات قيد المراجعة العلمية'), findsNothing);
      },
    );

    testWidgets('drawer shows reviewed 1:N difference and performance note', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        'primary_reading': 'hafs',
        'last_page': 1,
      });
      final preferences = await SharedPreferences.getInstance();

      final reviewed1ToN = ReadingDifference.published(
        id: 'rev_1',
        targetReading: QuranReading.shubah,
        baseSpan: ReadingWordSpan.singleWord(
          reading: QuranReading.hafs,
          surah: 1,
          ayah: 1,
          wordIndex: 1,
          text: 'بِسْمِ',
        ),
        targetSpan: const ReadingWordSpan(
          reading: QuranReading.shubah,
          surah: 1,
          ayah: 1,
          startWordIndex: 1,
          endWordIndex: 2,
          text: 'بِ اسْمِ',
        ),
        isPerformanceOnly: true,
        scholarlyNotes: 'فصل في الرسم مع الإشمام',
      );

      final quran = QuranRepository(
        hafsByPage: {
          1: [hafsAyah],
        },
        shubah: {'1:1': shubahAyah},
        qalun: {},
        publishedDifferences: [reviewed1ToN],
      );

      await tester.pumpWidget(
        QuranQiraatApp(preferences: preferences, quran: quran),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('الفروق'));
      await tester.pumpAndSettle();

      expect(find.text('محاذاة ١:N'), findsOneWidget);
      expect(find.text('اختلاف أداء أو رسم'), findsOneWidget);
      expect(find.text('فصل في الرسم مع الإشمام'), findsOneWidget);
    });

    testWidgets('preserves existing RTL reader layout and controls', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      const quran = QuranRepository(hafsByPage: {}, shubah: {}, qalun: {});

      await tester.pumpWidget(
        QuranQiraatApp(preferences: preferences, quran: quran),
      );
      await tester.pumpAndSettle();

      expect(
        Directionality.of(tester.element(find.byType(Scaffold))),
        TextDirection.rtl,
      );
      expect(find.text('مصحف القراءات'), findsOneWidget);
      expect(find.text('القراءتان'), findsOneWidget);
      expect(find.text('حفص × شعبة'), findsOneWidget);
    });
  });
}

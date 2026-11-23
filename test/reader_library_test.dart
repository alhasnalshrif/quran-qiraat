import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quran_qiraat/features/reader/reader_library.dart';
import 'package:quran_qiraat/features/reader/mushaf_reader_page.dart';
import 'package:quran_qiraat/quran_qiraat.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'reader_test_controls.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late QuranRepository quran;
  late QuranNavigationIndex index;
  setUpAll(() async {
    quran = await QuranRepository.load();
    index = QuranNavigationIndex(quran);
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('Qalun search locates the result using Qalun numbering', () {
    final result = index
        .search('ملك يوم الدين', reading: QuranReading.qalun)
        .singleWhere((ayah) => ayah.surah == 1);
    final location = index.locateInReading(QuranReading.qalun, result)!;
    expect(location.ayah, 3);
    expect(location.page, 1);
    expect(location.reading, QuranReading.qalun);
    expect(index.valid(location), isTrue);
  });

  test(
    'bookmark backup merges valid entries and keeps existing notes',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final local = ReaderLibraryStore(prefs);
      final first = index.locate(1, 5)!;
      final second = index.locate(2, 255)!;
      await local.save(first, 'محلية');
      final backup = jsonEncode({
        'format': ReaderLibraryStore.storageKey,
        'bookmarks': [
          ReaderBookmark(first, 'قديمة').toJson(),
          ReaderBookmark(second, 'مستعادة').toJson(),
        ],
      });
      expect(
        await local.importBookmarks(backup, isValidLocation: index.valid),
        1,
      );
      expect(local.bookmarks.map((bookmark) => bookmark.note), [
        'محلية',
        'مستعادة',
      ]);
      expect(
        await local.importBookmarks(
          local.exportBookmarks(),
          isValidLocation: index.valid,
        ),
        0,
      );
      await expectLater(
        local.importBookmarks('[]', isValidLocation: index.valid),
        throwsFormatException,
      );
      expect(local.bookmarks.length, 2);
      local.dispose();
    },
  );

  testWidgets(
    'reader appearance follows the saved choice and zoom preserves the page',
    (tester) async {
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(QuranQiraatApp(preferences: prefs, quran: quran));
      await tapReaderToToggleControls(tester);
      await tester.tap(find.byTooltip('إعدادات القراءة'));
      await tester.pumpAndSettle();
      expect(find.text('إعدادات القراءة'), findsOneWidget);
      await tester.tap(find.text('ليلي'));
      await tester.pumpAndSettle();
      expect(prefs.getString('reader_appearance'), 'dark');
      expect(
        Theme.of(tester.element(find.text('المظهر'))).brightness,
        Brightness.dark,
      );

      await tester.tap(find.text('نهاري'));
      await tester.pumpAndSettle();
      expect(
        Theme.of(tester.element(find.text('المظهر'))).brightness,
        Brightness.light,
      );

      final dispatcher = tester.binding.platformDispatcher;
      addTearDown(dispatcher.clearPlatformBrightnessTestValue);
      await tester.tap(find.text('حسب الجهاز'));
      dispatcher.platformBrightnessTestValue = Brightness.dark;
      await tester.pumpAndSettle();
      expect(prefs.getString('reader_appearance'), 'system');
      expect(
        Theme.of(tester.element(find.text('المظهر'))).brightness,
        Brightness.dark,
      );

      await tester.tap(find.byTooltip('إغلاق الإعدادات'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('تكبير صفحة القراءة'));
      await tester.pumpAndSettle();
      expect(find.text('تكبير صفحة 1'), findsOneWidget);
      await tester.tap(find.byTooltip('تكبير'));
      await tester.pumpAndSettle();
      final viewer = tester.widget<InteractiveViewer>(
        find.byType(InteractiveViewer),
      );
      expect(viewer.transformationController!.value.getMaxScaleOnAxis(), 1.5);
      expect(tester.takeException(), isNull);
    },
  );

  test('all surahs, juzs and hizbs resolve to real layout locations', () async {
    expect(index.surahs.length, 114);
    expect(index.juzs.keys, List.generate(30, (i) => i + 1));
    final hizbs = await index.hizbs();
    expect(hizbs.length, 60);
    expect(hizbs.first.key, '1:1');
    expect(hizbs[1].key, '2:75');
    expect(hizbs.last.key, '87:1');
    expect(
      hizbs.map((a) => index.ayahs.indexOf(a)).toList(),
      orderedEquals(
        (hizbs.map((a) => index.ayahs.indexOf(a)).toList()..sort()),
      ),
    );
    for (final ayah in [
      ...index.surahs.values,
      ...index.juzs.values,
      ...hizbs,
    ]) {
      final location = index.locate(ayah.surah, ayah.number)!;
      expect(
        quran.hafsLayout!
            .page(location.page)!
            .lines
            .expand((l) => l.words)
            .any((w) => w.location.startsWith('${ayah.key}:')),
        true,
      );
    }
    expect(index.locate(114, 7), isNull);
    expect(index.locate(5, 77, word: 1)!.page, 121);
    expect(index.locate(1, 1, word: 999), isNull);
    for (var page = 1; page <= 604; page++) {
      expect(
        index.firstOnPage(page)!.page,
        page,
        reason:
            'page $page must not bookmark the previous page when its first ayah continues',
      );
    }
  });

  test('search ignores marks, hamza forms, tatweel and Arabic spacing without modifying source', () {
    expect(normalizeQuranSearch('إِيَّاكَ  نَـعْبُدُ'), 'اياك نعبد');
    expect(normalizeQuranSearch('ٱلرَّحْمَٰنِ'), 'الرحمن');
    expect(
      index.search('إِيَّاكَ نَعْبُدُ').map((a) => a.key),
      contains('1:5'),
    );
    expect(
      index.search('اياك نعبد').map((a) => a.key),
      index.search('إِيَّاكَ نَعْبُدُ').map((a) => a.key),
    );
    expect(index.search('الله').length, greaterThan(100));
    expect(index.search('َ  ُ'), isEmpty);
    expect(index.search('عبارة غير موجودة إطلاقا'), isEmpty);
  });

  test(
    'multiple marks, notes, edits, deletion and word resume survive restart',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final store = ReaderLibraryStore(prefs);
      final first = index.locate(1, 1, word: 2)!,
          second = index.locate(2, 255)!;
      await Future.wait([
        store.save(first, 'الأولى'),
        store.save(second, 'الثانية'),
      ]);
      await store.save(first, ' تعديل ');
      await store.setResume(first);
      final restarted = ReaderLibraryStore(prefs);
      expect(restarted.bookmarks.length, 2);
      expect(restarted.bookmarks.first.note, 'تعديل');
      expect(restarted.resume!.key, first.key);
      expect(restarted.resume!.word, 2);
      await restarted.remove(first);
      expect(
        ReaderLibraryStore(prefs).bookmarks.single.location.key,
        second.key,
      );
      store.dispose();
      restarted.dispose();
    },
  );

  test('corrupt or invalid saved locations cannot break reading', () async {
    SharedPreferences.setMockInitialValues({
      ReaderLibraryStore.storageKey: '{broken',
    });
    var prefs = await SharedPreferences.getInstance();
    expect(ReaderLibraryStore(prefs).bookmarks, isEmpty);
    SharedPreferences.setMockInitialValues({
      ReaderLibraryStore.storageKey: jsonEncode({
        'version': 1,
        'resume': {'page': -1},
        'bookmarks': [
          false,
          {
            'location': {'page': 605},
            'note': 3,
          },
        ],
      }),
    });
    prefs = await SharedPreferences.getInstance();
    final store = ReaderLibraryStore(prefs);
    expect(store.resume, isNull);
    expect(store.bookmarks, isEmpty);
    expect(
      index.valid(const ReaderLocation(page: 1, surah: 114, ayah: 6)),
      false,
    );
  });

  testWidgets(
    'library searches and opens a result in Hafs with persisted precise position',
    (tester) async {
      SharedPreferences.setMockInitialValues({'primary_reading': 'qalun'});
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(QuranQiraatApp(preferences: prefs, quran: quran));
      await tapReaderToToggleControls(tester);
      await tester.tap(find.byTooltip('الفهرس والبحث والعلامات'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('البحث'));
      await tester.pumpAndSettle();
      expect(find.text('البحث في قالون'), findsOneWidget);
      await tester.tap(find.byType(DropdownButton<QuranReading>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('البحث في حفص').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'اياك نعبد');
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('إياك نعبد').first);
      await tester.pumpAndSettle();
      expect(find.byType(ReaderLibraryPage), findsNothing);
      expect(find.textContaining('آية 5'), findsOneWidget);
      expect(prefs.getString('primary_reading'), 'hafs');
      expect(ReaderLibraryStore(prefs).resume!.ayah, 5);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('night mode is shared by the reader, picker and library', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'night_reading': true,
      'last_page': 6,
    });
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(QuranQiraatApp(preferences: prefs, quran: quran));
    await tapReaderToToggleControls(tester);
    await tester.tap(find.text('القراءتان'));
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.text('اختر قراءتين للمقارنة'))).brightness,
      Brightness.dark,
    );
    Navigator.of(tester.element(find.text('اختر قراءتين للمقارنة'))).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('الفهرس والبحث والعلامات'));
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.byType(ReaderLibraryPage))).brightness,
      Brightness.dark,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'direct ayah entry accepts Arabic digits and retains invalid input with feedback',
    (tester) async {
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(QuranQiraatApp(preferences: prefs, quran: quran));
      await tapReaderToToggleControls(tester);
      await tester.tap(find.byTooltip('الفهرس والبحث والعلامات'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('الانتقال إلى آية'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(0), '١١٤');
      await tester.enterText(find.byType(TextField).at(1), '٧');
      await tester.tap(find.text('انتقال'));
      await tester.pumpAndSettle();
      expect(find.text('أدخل رقم سورة وآية موجودين'), findsOneWidget);
      await tester.enterText(find.byType(TextField).at(1), '٦');
      await tester.tap(find.text('انتقال'));
      await tester.pumpAndSettle();
      expect(prefs.getInt('last_page'), 604);
      expect(ReaderLibraryStore(prefs).resume!.surah, 114);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'bookmark notes save, edit and delete on a narrow screen with large text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final prefs = await SharedPreferences.getInstance();
      final store = ReaderLibraryStore(prefs);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => Directionality(
            textDirection: TextDirection.rtl,
            child: MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(1.5)),
              child: child!,
            ),
          ),
          home: ReaderLibraryPage(
            index: index,
            store: store,
            current: index.locate(2, 255)!,
            initialTab: 2,
          ),
        ),
      );
      await tester.tap(find.text('حفظ الموضع الحالي'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'مراجعة آية الكرسي');
      await tester.tap(find.text('حفظ'));
      await tester.pumpAndSettle();
      expect(store.bookmarks.single.note, 'مراجعة آية الكرسي');
      await tester.longPress(find.textContaining('آية 255').last);
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'مراجعة آية الكرسي',
      );
      await tester.enterText(find.byType(TextField), 'تمت المراجعة');
      await tester.tap(find.text('حفظ'));
      await tester.pumpAndSettle();
      expect(store.bookmarks.single.note, 'تمت المراجعة');
      await tester.tap(find.byTooltip('خيارات العلامة'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('حذف العلامة'));
      await tester.pumpAndSettle();
      expect(store.bookmarks, isEmpty);
      await tester.tap(find.text('تراجع'));
      await tester.pumpAndSettle();
      expect(store.bookmarks.single.note, 'تمت المراجعة');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('reader restores saved word position and highlights the word', (
    tester,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final store = ReaderLibraryStore(prefs);
    await store.setResume(index.locate(1, 1, word: 2)!);
    await tester.pumpWidget(QuranQiraatApp(preferences: prefs, quran: quran));
    await tester.pumpAndSettle();
    await tapReaderToToggleControls(tester);
    expect(find.textContaining('كلمة 2'), findsOneWidget);
    expect(find.byType(QuranTextPage), findsWidgets);
    final spans = tester.widgetList<RichText>(find.byType(RichText));
    bool marked(InlineSpan span) =>
        (span.style?.backgroundColor != null) ||
        (span is TextSpan && (span.children?.any(marked) ?? false));
    expect(spans.any((text) => marked(text.text)), true);
    expect(tester.takeException(), isNull);
  });

  testWidgets('bookmark library visual review in Arabic on mobile', (
    tester,
  ) async {
    for (final font in {
      'NotoSansArabic': 'assets/fonts/noto_sans_arabic.ttf',
      'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
    }.entries) {
      await (FontLoader(font.key)..addFont(rootBundle.load(font.value))).load();
    }
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final prefs = await SharedPreferences.getInstance();
    final store = ReaderLibraryStore(prefs);
    final current = index.locate(2, 255)!;
    await store.save(current, 'مراجعة آية الكرسي');
    await store.save(index.locate(1, 5)!, 'متابعة الحفظ');
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          fontFamily: 'NotoSansArabic',
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff3f7a48)),
        ),
        builder: (context, child) =>
            Directionality(textDirection: TextDirection.rtl, child: child!),
        home: ReaderLibraryPage(
          index: index,
          store: store,
          current: current,
          initialTab: 2,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/reader_library_bookmarks_rtl.png'),
    );
    expect(tester.takeException(), isNull);
  });
}

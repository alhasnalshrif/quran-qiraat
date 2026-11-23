import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quran_qiraat/features/reader/mushaf_reader_page.dart';
import 'package:quran_qiraat/quran_qiraat.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'reader_test_controls.dart';

void main() {
  late QuranRepository quran;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    quran = await QuranRepository.load();
    for (final entry in {
      'NotoSansArabic': 'assets/fonts/noto_sans_arabic.ttf',
      'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
      'AmiriQuran': 'assets/fonts/amiri_quran.ttf',
      'Shubah': 'assets/fonts/shubah.ttf',
      'Qalun': 'assets/fonts/qalun.ttf',
      'packages/iconsax_flutter/FlutterIconsax':
          'packages/iconsax_flutter/fonts/FlutterIconsax.ttf',
    }.entries) {
      await (FontLoader(
        entry.key,
      )..addFont(rootBundle.load(entry.value))).load();
    }
  });

  Future<SharedPreferences> openReader(
    WidgetTester tester, {
    Size size = const Size(430, 932),
    String? placement = 'hidden',
    String comparison = 'qalun',
    int page = 3,
    double textScale = 1,
    bool night = false,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    SharedPreferences.setMockInitialValues({
      'last_page': page,
      'night_reading': night,
      'differences_placement': ?placement,
      'comparison_reading': comparison,
    });
    final preferences = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      QuranQiraatApp(preferences: preferences, quran: quran),
    );
    await tester.pumpAndSettle();
    await tapReaderToToggleControls(tester);
    return preferences;
  }

  test('farsh gives each riwayah its reading at Maliki yawm al-din', () {
    final variants = quran.qiraatVariants!;
    final juncture = variants.forWord('1:4:1').single;
    expect(variants.readingFor(juncture, 'hafs')!.text, 'مَالِكِ');
    expect(variants.readingFor(juncture, 'qaloon')!.text, 'مَلِكِ');
    expect(variants.readingFor(juncture, 'warsh')!.text, 'مَلِكِ');
    expect(variants.differsFromHafs(juncture, 'qaloon'), isTrue);
    expect(variants.differsFromHafs(juncture, 'shubah'), isFalse);
    expect(
      variants.attribution(variants.readingFor(juncture, 'hafs')!),
      contains('عاصم'),
    );
    expect(variants.forWord('1:4:2'), isEmpty);
    expect(variants.riwayat, hasLength(20));
    expect(quran.publishedDifferences, isEmpty);
  });

  test('a transmitter split beats the imam (Shubah at Baqarah 97)', () {
    final variants = quran.qiraatVariants!;
    final juncture = variants.forWord('2:97:5').single;
    expect(variants.differsFromHafs(juncture, 'shubah'), isTrue);
    expect(variants.readingFor(juncture, 'shubah')!.text, 'لِجَبۡرَئِلَ');
  });

  test('spans that disagree with the source reading stay untinted', () {
    final variants = quran.qiraatVariants!;
    final misplaced = variants
        .forAyah('2:85')
        .where((juncture) => juncture.word == 'مَن يَفۡعَلُ')
        .single;
    expect(misplaced.locations, isEmpty);
    expect(variants.forWord('2:85:30'), isEmpty);
  });

  testWidgets('margin shows Qalun reading from the farsh beside its word', (
    tester,
  ) async {
    await openReader(tester, placement: 'margin', page: 1);
    await tapReaderToToggleControls(tester);
    expect(find.text('مَلِكِ'), findsOneWidget);
    final word = tester.widget<Text>(find.text('مَلِكِ'));
    expect(word.style?.color, const Color(0xffad2626));
    final verseLine = find.byKey(const ValueKey('mushaf-line-1-4'));
    final texts = tester.widgetList<RichText>(
      find.descendant(of: verseLine, matching: find.byType(RichText)),
    );
    bool hasColoredWord(InlineSpan span) =>
        span is TextSpan &&
        (((span.text?.contains('مَـٰلِكِ') ?? false) &&
                span.style?.color == const Color(0xffad2626)) ||
            (span.children?.any(hasColoredWord) ?? false));
    expect(texts.any((text) => hasColoredWord(text.text)), isTrue);
    final marginLine = find.byKey(const ValueKey('mushaf-margin-line-1-4'));
    expect(tester.getCenter(marginLine).dy, tester.getCenter(verseLine).dy);
    expect(
      tester.getRect(marginLine).right,
      lessThan(tester.getRect(verseLine).left),
    );
    await tester.tap(marginLine);
    await tester.pumpAndSettle();
    expect(find.textContaining('Quran Tajweed Engine'), findsOneWidget);
    expect(find.textContaining('قراءة قالون'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('اختر رواية الهامش'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('المقارنة النصية'));
    await tester.pumpAndSettle();
    expect(find.text('المقارنة النصية · صفحة 1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('margin can follow any of the twenty riwayat', (tester) async {
    final preferences = await openReader(tester, placement: 'margin', page: 1);
    await tapReaderToToggleControls(tester);
    await tester.tap(find.byTooltip('اختر رواية الهامش'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ورش · نافع'));
    await tester.pumpAndSettle();
    expect(preferences.getString('margin_riwayah'), 'warsh');
    expect(find.byKey(const ValueKey('mushaf-margin-1-warsh')), findsOneWidget);
    expect(find.text('مَلِكِ'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Shubah shows the farsh difference at Baqarah 97 on page 15', (
    tester,
  ) async {
    await openReader(
      tester,
      placement: 'margin',
      comparison: 'shubah',
      page: 15,
    );
    await tapReaderToToggleControls(tester);

    final margin = find.byKey(const ValueKey('mushaf-margin-15-shubah'));
    expect(
      find.descendant(of: margin, matching: find.text('شعبة')),
      findsOneWidget,
    );
    final note = find.byKey(const ValueKey('mushaf-margin-line-15-7'));
    final line = find.byKey(const ValueKey('mushaf-line-15-7'));
    expect(
      find.descendant(of: note, matching: find.text('لِجَبۡرَئِلَ')),
      findsOneWidget,
    );
    expect(tester.getCenter(note).dy, tester.getCenter(line).dy);
  });

  testWidgets(
    'page three keeps aligned margin notes outside the reading frame',
    (tester) async {
      await openReader(tester, placement: 'margin', page: 3);
      await tapReaderToToggleControls(tester);
      final note = find.byKey(const ValueKey('mushaf-margin-line-3-5'));
      final line = find.byKey(const ValueKey('mushaf-line-3-5'));
      expect(note, findsOneWidget);
      expect(tester.getCenter(note).dy, tester.getCenter(line).dy);
      expect(tester.getRect(note).right, lessThan(tester.getRect(line).left));
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(QuranQiraatApp),
        matchesGoldenFile('goldens/hafs_qalun_margin_page_3.png'),
      );

      tester.view.physicalSize = const Size(320, 740);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      await tester.pumpAndSettle();
      expect(note, findsNothing);
      expect(find.text('هامش قالون'), findsOneWidget);
      await tester.tap(find.byTooltip('عرض الفروق'));
      await tester.pumpAndSettle();
      expect(find.text('فروق قالون'), findsOneWidget);
      expect(find.textContaining('الآية 2:'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('page three uses a pure black canvas in night mode', (
    tester,
  ) async {
    await openReader(tester, placement: 'margin', page: 3, night: true);
    await tapReaderToToggleControls(tester);

    final reader = find.byKey(const ValueKey('reader-page-3'));
    final canvas = find.descendant(
      of: reader,
      matching: find.byWidgetPredicate(
        (widget) => widget is ColoredBox && widget.color == Colors.black,
      ),
    );
    expect(canvas, findsOneWidget);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(QuranQiraatApp),
      matchesGoldenFile('goldens/hafs_qalun_margin_page_3_night.png'),
    );
  });

  testWidgets('pins from drawer, switches placement, and saves visibility', (
    tester,
  ) async {
    final preferences = await openReader(tester);
    await tester.tap(find.text('الفروق'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('أسفل الصفحة'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('differences-bottom-panel')),
      findsOneWidget,
    );
    expect(find.byType(PageView), findsOneWidget);
    expect(preferences.getString('differences_placement'), 'bottom');
    expect(find.text('ما يخالف فيه قالون حفصًا'), findsOneWidget);
    expect(find.text('فروق معتمدة'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('موضع الاختلافات'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('على الجانب'));
    await tester.pumpAndSettle();
    expect(preferences.getString('differences_placement'), 'side');
    expect(
      find.byKey(const ValueKey('differences-bottom-panel')),
      findsOneWidget,
    );

    tester.view.physicalSize = const Size(1180, 900);
    await tester.pumpAndSettle();
    final side = find.byKey(const ValueKey('differences-side-panel'));
    expect(side, findsOneWidget);
    expect(
      tester.getTopLeft(side).dx,
      greaterThan(tester.getTopRight(find.byType(PageView)).dx),
    );
    expect(find.text('اختلافات الصفحة 3'), findsOneWidget);

    await tapReaderToToggleControls(tester);
    await tester.tap(find.byTooltip('إغلاق الاختلافات'));
    await tester.pumpAndSettle();
    expect(find.byType(DifferencesPanel), findsNothing);
    expect(preferences.getString('differences_placement'), 'hidden');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'margin mode keeps Hafs in the body when switching the margin to Qalun',
    (tester) async {
      final preferences = await openReader(
        tester,
        comparison: 'shubah',
        placement: null,
      );
      final line = find.byKey(const ValueKey('mushaf-line-3-1'));
      expect(
        find.byKey(const ValueKey('mushaf-margin-3-shubah')),
        findsOneWidget,
      );
      await tapReaderToToggleControls(tester);
      await tester.tap(find.byTooltip('اختر رواية الهامش'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.ancestor(
          of: find.text('قالون · نافع'),
          matching: find.byWidgetPredicate((widget) => widget is PopupMenuItem),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('mushaf-margin-3-qaloon')),
        findsOneWidget,
      );
      final mainLine = tester.getRect(
        find.byKey(const ValueKey('mushaf-line-3-1')),
      );
      final margin = tester.getRect(
        find.byKey(const ValueKey('mushaf-margin-3-qaloon')),
      );
      expect(
        mainLine.left >= margin.right || mainLine.bottom <= margin.top,
        isTrue,
      );
      expect(preferences.getString('primary_reading'), 'hafs');
      expect(preferences.getString('differences_placement'), 'margin');
      await tapReaderToToggleControls(tester);
      await tester.tap(find.byTooltip('إخفاء الفروق'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('mushaf-margin-3-qaloon')),
        findsNothing,
      );
      expect(tester.getSize(line).width, greaterThanOrEqualTo(mainLine.width));
      await tester.tap(find.byTooltip('إظهار الهامش'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('mushaf-margin-3-qaloon')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'updates pinned differences after navigation and reading changes',
    (tester) async {
      await openReader(tester, placement: 'bottom');
      await tester.tap(find.text('صفحة 3'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '4');
      await tester.tap(find.text('انتقال'));
      await tester.pumpAndSettle();
      expect(find.text('اختلافات الصفحة 4'), findsOneWidget);
      expect(
        tester.widget<DifferencesPanel>(find.byType(DifferencesPanel)).page,
        4,
      );

      await tester.drag(find.byType(PageView), const Offset(350, 0));
      await tester.pumpAndSettle();
      expect(find.text('اختلافات الصفحة 5'), findsOneWidget);

      await tester.tap(find.text('القراءتان'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(QuranReading.shubah.title).last);
      await tester.tap(find.text('تأكيد المقارنة'));
      await tester.pumpAndSettle();
      final panel = tester.widget<DifferencesPanel>(
        find.byType(DifferencesPanel),
      );
      expect(panel.baseReading, QuranReading.hafs);
      expect(panel.comparisonReading, QuranReading.shubah);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('إخفاء الفروق'));
      await tester.pumpAndSettle();
      expect(find.byType(DifferencesPanel), findsNothing);
    },
  );

  testWidgets(
    'restores side preference and keeps the page across layout changes',
    (tester) async {
      final preferences = await openReader(
        tester,
        placement: 'side',
        size: const Size(1180, 900),
      );
      await tester.drag(find.byType(PageView), const Offset(600, 0));
      await tester.pumpAndSettle();
      expect(find.text('اختلافات الصفحة 4'), findsOneWidget);
      tester.view.physicalSize = const Size(430, 932);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('differences-bottom-panel')),
        findsOneWidget,
      );
      expect(find.text('اختلافات الصفحة 4'), findsOneWidget);
      expect(preferences.getString('differences_placement'), 'side');
      expect(preferences.getInt('last_page'), 4);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('placement menu supports keyboard selection and Escape', (
    tester,
  ) async {
    final preferences = await openReader(tester, placement: 'bottom');
    await tester.tap(find.byTooltip('موضع الاختلافات'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('على الجانب'), findsNothing);
    await tester.tap(find.byTooltip('موضع الاختلافات'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(preferences.getString('differences_placement'), 'side');
    expect(tester.takeException(), isNull);
  });

  for (final size in [
    const Size(320, 700),
    const Size(430, 932),
    const Size(800, 600),
    const Size(700, 400),
    const Size(1180, 900),
  ]) {
    testWidgets('bottom panel fits $size and can scroll its content', (
      tester,
    ) async {
      await openReader(tester, size: size, placement: 'bottom');
      await tapReaderToToggleControls(tester);
      final panel = find.byKey(const ValueKey('differences-bottom-panel'));
      expect(panel, findsOneWidget);
      expect(tester.takeException(), isNull);
      final list = find.descendant(of: panel, matching: find.byType(ListView));
      await tester.drag(list, const Offset(0, -150));
      await tester.pumpAndSettle();
      expect(tester.getBottomRight(panel).dy, lessThanOrEqualTo(size.height));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('bottom panel handles 200 percent text scaling', (tester) async {
    await openReader(
      tester,
      size: const Size(320, 700),
      placement: 'bottom',
      textScale: 2,
    );
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('موضع الاختلافات'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
  });

  testWidgets('large text fits with a landscape bottom panel', (tester) async {
    await openReader(
      tester,
      size: const Size(700, 400),
      placement: 'bottom',
      textScale: 2,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('large text fits with a tablet side panel', (tester) async {
    await openReader(
      tester,
      size: const Size(800, 600),
      placement: 'side',
      textScale: 2,
    );
    expect(tester.takeException(), isNull);
  });

  for (final size in [const Size(320, 700), const Size(430, 932)]) {
    testWidgets('side preference preserves full width on a phone at $size', (
      tester,
    ) async {
      final preferences = await openReader(
        tester,
        size: size,
        placement: 'side',
      );
      final panel = find.byKey(const ValueKey('differences-bottom-panel'));
      final page = find.byType(PageView);
      expect(panel, findsOneWidget);
      expect(tester.getSize(page).width, size.width);
      expect(
        tester.getTopLeft(panel).dy,
        greaterThanOrEqualTo(tester.getBottomLeft(page).dy),
      );
      expect(preferences.getString('differences_placement'), 'side');
      await tester.drag(page, Offset(size.width * .75, 0));
      await tester.pumpAndSettle();
      expect(find.text('اختلافات الصفحة 4'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('mobile side panel supports large text and placement switching', (
    tester,
  ) async {
    final preferences = await openReader(
      tester,
      size: const Size(320, 700),
      placement: 'side',
      textScale: 2,
    );
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('موضع الاختلافات'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('أسفل الصفحة'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('differences-bottom-panel')),
      findsOneWidget,
    );
    expect(preferences.getString('differences_placement'), 'bottom');
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile side panel visual regression', (tester) async {
    await openReader(tester, placement: 'side');
    await expectLater(
      find.byType(QuranQiraatApp),
      matchesGoldenFile('goldens/differences_mobile_side_panel_rtl.png'),
    );
  });

  testWidgets('reader exposes zoom while a compact difference panel is open', (
    tester,
  ) async {
    await openReader(tester, placement: 'side');
    await tester.tap(find.byTooltip('تكبير صفحة القراءة'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('تكبير'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<InteractiveViewer>(find.byType(InteractiveViewer))
          .transformationController!
          .value
          .getMaxScaleOnAxis(),
      1.5,
    );
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('differences-bottom-panel')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'page without reviewed records still reaches the text comparison',
    (tester) async {
      await openReader(
        tester,
        placement: 'bottom',
        size: const Size(700, 400),
        comparison: 'shubah',
      );
      await tester.tap(find.text('صفحة 3'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '1');
      await tester.tap(find.text('انتقال'));
      await tester.pumpAndSettle();
      final panel = find.byKey(const ValueKey('differences-bottom-panel'));
      final scrollable = find
          .descendant(of: panel, matching: find.byType(Scrollable))
          .first;
      // The reader controls float over this short panel, so scroll it
      // directly instead of dragging under them.
      final position = tester.state<ScrollableState>(scrollable).position;
      position.jumpTo(position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(find.text('قارن نصوص الآيات'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('phone side panel lists the farsh of the page', (tester) async {
    await openReader(tester, placement: 'side', comparison: 'shubah');
    await tester.tap(find.text('صفحة 3'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '1');
    await tester.tap(find.text('انتقال'));
    await tester.pumpAndSettle();
    expect(find.text('خلاف بقية القراء في الصفحة'), findsOneWidget);
    expect(find.text('مَلِكِ'), findsWidgets);
    expect(find.textContaining('قراءة حفص'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  for (final placement in ['side', 'bottom']) {
    testWidgets('$placement panel visual regression', (tester) async {
      await openReader(
        tester,
        placement: placement,
        size: placement == 'side'
            ? const Size(1180, 900)
            : const Size(430, 932),
      );
      await expectLater(
        find.byType(QuranQiraatApp),
        matchesGoldenFile('goldens/differences_${placement}_panel_rtl.png'),
      );
    });
  }
}

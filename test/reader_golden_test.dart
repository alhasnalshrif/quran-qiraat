import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quran_qiraat/quran_qiraat.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'reader_test_controls.dart';

void main() {
  testWidgets('Hafs Madani page uses a fixed 15-line reading grid', (
    tester,
  ) async {
    await _loadFonts();
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({
      'primary_reading': 'hafs',
      'differences_placement': 'hidden',
      'comparison_reading': 'shubah',
      'last_page': 3,
    });
    final preferences = await SharedPreferences.getInstance();
    final quran = _hafsPageFixture();

    await tester.pumpWidget(
      QuranQiraatApp(preferences: preferences, quran: quran),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tapReaderToToggleControls(tester);

    expect(find.byKey(const ValueKey('mushaf-line-3-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('mushaf-line-3-15')), findsOneWidget);
    for (var row = 1; row <= 15; row++) {
      final line = find.byKey(ValueKey('mushaf-line-3-$row'));
      final words = tester.renderObjectList<RenderParagraph>(
        find.descendant(of: line, matching: find.byType(RichText)),
      );
      final ink = [
        for (final paragraph in words)
          for (final box in paragraph.getBoxesForSelection(
            TextSelection(
              baseOffset: 0,
              extentOffset: paragraph.text.toPlainText().length,
            ),
          ))
            Rect.fromPoints(
              paragraph.localToGlobal(box.toRect().topLeft),
              paragraph.localToGlobal(box.toRect().bottomRight),
            ),
      ].reduce((bounds, box) => bounds.expandToInclude(box));
      final lineBounds = tester.getRect(line);
      final leftEdge = ink.left;
      final rightEdge = ink.right;
      expect(leftEdge, closeTo(lineBounds.left + 4, 1), reason: 'row $row');
      expect(rightEdge, closeTo(lineBounds.right - 4, 1), reason: 'row $row');
    }
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(QuranQiraatApp),
      matchesGoldenFile('goldens/hafs_madani_page_3.png'),
    );

    final line = find.byKey(const ValueKey('mushaf-line-3-8'));
    final lineBounds = tester.getRect(line);
    await tapReaderToToggleControls(tester);
    expect(find.byKey(const ValueKey('reader-top-chrome')), findsNothing);
    expect(find.byKey(const ValueKey('reader-bottom-chrome')), findsNothing);
    expect(tester.getRect(line), lineBounds);

    await tester.longPress(find.byKey(const ValueKey('mushaf-line-3-8')));
    await tester.pumpAndSettle();
    // Long press saves the position and offers the comparison without
    // covering the page.
    expect(find.text('حُفظ موضع القراءة'), findsOneWidget);
    expect(find.textContaining('موضع 2:6:'), findsNothing);
    await tester.tap(find.text('المقارنة والتلاوة'));
    await tester.pumpAndSettle();
    expect(find.textContaining('موضع 2:6:'), findsOneWidget);
  });

  testWidgets('RTL reader mobile layout', (tester) async {
    await _loadFonts();
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({
      'primary_reading': 'shubah',
      'last_page': 1,
    });
    final preferences = await SharedPreferences.getInstance();
    const sampleText =
        'بِسْمِ اللَّهِ الرَّحْمَنِ الرَّحِيمِ الحمد لله رب العالمين '
        'الرَّحْمَنِ الرَّحِيمِ مالك يوم الدين إياك نعبد وإياك نستعين '
        'اهدنا الصراط المستقيم صراط الذين أنعمت عليهم غير المغضوب '
        'عليهم ولا الضالين ';
    const denseText = '$sampleText$sampleText$sampleText';
    const ayah = Ayah(
      surah: 1,
      number: 1,
      page: 1,
      text: denseText,
      comparisonText: denseText,
      surahName: 'الفاتحة',
    );
    const quran = QuranRepository(
      hafsByPage: {
        1: [ayah],
      },
      shubah: {'1:1': ayah},
      qalun: {},
    );

    await tester.pumpWidget(
      QuranQiraatApp(preferences: preferences, quran: quran),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tapReaderToToggleControls(tester);

    await expectLater(
      find.byType(QuranQiraatApp),
      matchesGoldenFile('goldens/reader_rtl.png'),
    );

    await tester.tap(find.text('شعبة × حفص'));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(QuranQiraatApp),
      matchesGoldenFile('goldens/reading_sheet_rtl.png'),
    );

    await tester.tap(find.text('تأكيد المقارنة'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('الفروق'));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(QuranQiraatApp),
      matchesGoldenFile('goldens/differences_drawer_rtl.png'),
    );
  });
}

QuranRepository _hafsPageFixture() {
  const sourceLines = [
    'إِنَّ ٱلَّذِينَ كَفَرُوا۟ سَوَآءٌ عَلَيْهِمْ ءَأَنذَرْتَهُمْ أَمْ لَمْ تُنذِرْهُمْ',
    'لَا يُؤْمِنُونَ ٦ خَتَمَ ٱللَّهُ عَلَىٰ قُلُوبِهِمْ وَعَلَىٰ سَمْعِهِمْ وَعَلَىٰٓ',
    'أَبْصَـٰرِهِمْ غِشَـٰوَةٌۭ وَلَهُمْ عَذَابٌ عَظِيمٌۭ ٧ وَمِنَ ٱلنَّاسِ',
    'مَن يَقُولُ ءَامَنَّا بِٱللَّهِ وَبِٱلْيَوْمِ ٱلْـَٔاخِرِ وَمَا هُم بِمُؤْمِنِينَ ٨',
    'يُخَـٰدِعُونَ ٱللَّهَ وَٱلَّذِينَ ءَامَنُوا۟ وَمَا يَخْدَعُونَ إِلَّآ أَنفُسَهُمْ',
    'وَمَا يَشْعُرُونَ ٩ فِى قُلُوبِهِم مَّرَضٌۭ فَزَادَهُمُ ٱللَّهُ مَرَضًۭا',
    'وَلَهُمْ عَذَابٌ أَلِيمٌۢ بِمَا كَانُوا۟ يَكْذِبُونَ ١٠ وَإِذَا قِيلَ لَهُمْ',
    'لَا تُفْسِدُوا۟ فِى ٱلْأَرْضِ قَالُوٓا۟ إِنَّمَا نَحْنُ مُصْلِحُونَ ١١',
    'أَلَآ إِنَّهُمْ هُمُ ٱلْمُفْسِدُونَ وَلَـٰكِن لَّا يَشْعُرُونَ ١٢ وَإِذَا قِيلَ',
    'لَهُمْ ءَامِنُوا۟ كَمَآ ءَامَنَ ٱلنَّاسُ قَالُوٓا۟ أَنُؤْمِنُ كَمَآ ءَامَنَ ٱلسُّفَهَآءُ',
    'أَلَآ إِنَّهُمْ هُمُ ٱلسُّفَهَآءُ وَلَـٰكِن لَّا يَعْلَمُونَ ١٣ وَإِذَا لَقُوا۟',
    'ٱلَّذِينَ ءَامَنُوا۟ قَالُوٓا۟ ءَامَنَّا وَإِذَا خَلَوْا۟ إِلَىٰ شَيَـٰطِينِهِمْ قَالُوٓا۟ إِنَّا',
    'مَعَكُمْ إِنَّمَا نَحْنُ مُسْتَهْزِءُونَ ١٤ ٱللَّهُ يَسْتَهْزِئُ بِهِمْ وَيَمُدُّهُمْ',
    'فِى طُغْيَـٰنِهِمْ يَعْمَهُونَ ١٥ أُو۟لَـٰٓئِكَ ٱلَّذِينَ ٱشْتَرَوُا۟ ٱلضَّلَـٰلَةَ',
    'بِٱلْهُدَىٰ فَمَا رَبِحَت تِّجَـٰرَتُهُمْ وَمَا كَانُوا۟ مُهْتَدِينَ ١٦',
  ];
  final lines = <MushafLayoutLine>[
    for (var lineIndex = 0; lineIndex < sourceLines.length; lineIndex++)
      MushafLayoutLine(
        number: lineIndex + 1,
        type: MushafLayoutLineType.text,
        text: sourceLines[lineIndex],
        words: [
          for (
            var wordIndex = 0;
            wordIndex < sourceLines[lineIndex].split(' ').length;
            wordIndex++
          )
            MushafLayoutWord(
              location: '2:6:${wordIndex + 1}',
              text: sourceLines[lineIndex].split(' ')[wordIndex],
            ),
        ],
      ),
  ];
  final layout = MushafLayout(
    editionId: 'golden',
    sourceCommit: 'fixture',
    pages: [
      const MushafLayoutPage(
        number: 1,
        lines: [
          MushafLayoutLine(
            number: 1,
            type: MushafLayoutLineType.basmala,
            text: 'بِسْمِ اللَّهِ',
          ),
        ],
      ),
      const MushafLayoutPage(
        number: 2,
        lines: [
          MushafLayoutLine(
            number: 1,
            type: MushafLayoutLineType.basmala,
            text: 'بِسْمِ اللَّهِ',
          ),
        ],
      ),
      MushafLayoutPage(number: 3, lines: lines),
    ],
  );
  final ayah = Ayah(
    surah: 2,
    number: 6,
    page: 3,
    text: sourceLines[0],
    comparisonText: sourceLines[0],
    surahName: 'البقرة',
  );
  return QuranRepository(
    hafsByPage: {
      3: [ayah],
    },
    shubah: {'2:6': ayah},
    qalun: const {},
    hafsLayout: layout,
  );
}

Future<void> _loadFonts() async {
  final fonts = {
    'NotoSansArabic': 'assets/fonts/noto_sans_arabic.ttf',
    'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
    'HafsSmart': 'assets/fonts/hafs_smart.ttf',
    'AmiriQuran': 'assets/fonts/amiri_quran.ttf',
    'Shubah': 'assets/fonts/shubah.ttf',
    'Qalun': 'assets/fonts/qalun.ttf',
    'packages/iconsax_flutter/FlutterIconsax':
        'packages/iconsax_flutter/fonts/FlutterIconsax.ttf',
  };
  for (final entry in fonts.entries) {
    final loader = FontLoader(entry.key)..addFont(rootBundle.load(entry.value));
    await loader.load();
  }
}

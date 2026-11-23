import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quran_qiraat/features/reader/mushaf_reader_page.dart';
import 'package:quran_qiraat/quran_qiraat.dart';

/// Every printed line keeps its own words: none may wrap to a hidden second
/// line or spill outside the page, on any of the 604 pages.
void main() {
  testWidgets('all 604 pages keep every word of every line visible', (
    tester,
  ) async {
    for (final entry in {
      'NotoSansArabic': 'assets/fonts/noto_sans_arabic.ttf',
      'AmiriQuran': 'assets/fonts/amiri_quran.ttf',
    }.entries) {
      await (FontLoader(
        entry.key,
      )..addFont(rootBundle.load(entry.value))).load();
    }
    final quran = (await tester.runAsync(QuranRepository.load))!;
    tester.view.physicalSize = const Size(440, 956);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final problems = <String>[];
    for (var page = 1; page <= 604; page++) {
      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: QuranTextPage(
                page: page,
                reading: QuranReading.hafs,
                comparisonReading: QuranReading.shubah,
                quran: quran,
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull, reason: 'page $page');
      final mushafLines = find.byWidgetPredicate(
        (widget) =>
            widget.key is ValueKey<String> &&
            (widget.key! as ValueKey<String>).value.startsWith(
              'mushaf-line-$page-',
            ),
      );
      for (final paragraph in tester.renderObjectList<RenderParagraph>(
        find.descendant(of: mushafLines, matching: find.byType(RichText)),
      )) {
        final text = paragraph.text.toPlainText();
        if (text.isEmpty) continue;
        final boxes = paragraph.getBoxesForSelection(
          TextSelection(baseOffset: 0, extentOffset: text.length),
        );
        final lines = boxes.map((box) => box.top.round()).toSet();
        if (paragraph.didExceedMaxLines || lines.length > 1) {
          problems.add('$page: $text');
        }
      }
    }
    expect(problems, isEmpty);
  });
}

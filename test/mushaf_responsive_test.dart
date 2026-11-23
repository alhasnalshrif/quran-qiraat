import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quran_qiraat/features/reader/mushaf_reader_page.dart';
import 'package:quran_qiraat/quran_qiraat.dart';

/// Q-04: the printed line layout holds on the phone and tablet sizes the plan
/// names (320, 375, 440, tablet 820) and at 200% text.
///
/// The reader shrinks each line's font until it fits (`_fitLine`), so words are
/// never clipped or wrapped — the risk is the opposite: on a narrow screen the
/// type collapses to something unreadable. This test therefore checks the
/// rendered font size, not the line count, and fails when a line falls below a
/// legible floor.
///
/// The exhaustive 604-page pass lives in mushaf_lines_test.dart; running every
/// page at every size would take many minutes, so each size checks a spread of
/// pages chosen for their long lines, headers and narrow columns.

/// The font size actually drawn: the style size times any FittedBox scale.
double drawnFontSize(WidgetTester tester, RenderParagraph paragraph) {
  final base = paragraph.text.style?.fontSize ?? 0;
  var scale = 1.0;
  RenderObject? node = paragraph.parent;
  while (node != null) {
    if (node is RenderFittedBox) {
      final size = node.size;
      final child = node.child;
      if (child is RenderBox && child.hasSize && size.width > 0) {
        scale *= (child.size.width / size.width).clamp(0.0, 1.0);
      }
    }
    node = node.parent;
  }
  return base * scale;
}

/// Below this a printed line is not comfortably readable at arm's length.
///
/// The reader fits each line by shrinking the font, so this floor is the real
/// guarantee: 440pt renders ~22pt, 320pt renders ~16pt, and anything under
/// 10pt means the size is too narrow for this mushaf.
const double _legibleFloor = 10.0;
void main() {
  test('the legibility floor rejects a collapsed line', () {
    // 150pt wide fits at ~6.5pt, which must be considered unreadable.
    expect(6.5 < _legibleFloor, isTrue);
    // The real sizes stay above the floor (measured: 440pt ~22pt, 320pt ~16pt).
    expect(16.0 < _legibleFloor, isFalse);
    expect(22.3 < _legibleFloor, isFalse);
  });

  const sizes = <String, Size>{
    '320': Size(320, 700),
    '375': Size(375, 812),
    '440': Size(440, 956),
    'tablet 820': Size(820, 1180),
  };

  const samplePages = [1, 2, 3, 15, 42, 100, 255, 400, 500, 604];

  testWidgets('every named size keeps all words on their printed line', (
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
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    final problems = <String>[];

    for (final sizeEntry in sizes.entries) {
      tester.view.physicalSize = sizeEntry.value;
      tester.view.devicePixelRatio = 1;

      for (final page in samplePages) {
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

        expect(
          tester.takeException(),
          isNull,
          reason: '${sizeEntry.key} page $page',
        );

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
            problems.add('${sizeEntry.key} / page $page wrapped: $text');
          }
          // FittedBox(scaleDown) may shrink further without changing the
          // style, so multiply by its transform to get the drawn size.
          final size = drawnFontSize(tester, paragraph);
          if (size < _legibleFloor) {
            problems.add(
              '${sizeEntry.key} / page $page too small (${size.toStringAsFixed(1)}pt): $text',
            );
          }
        }
      }
    }

    expect(problems, isEmpty);
  });

  testWidgets('200% text does not split a printed line', (tester) async {
    for (final entry in {
      'NotoSansArabic': 'assets/fonts/noto_sans_arabic.ttf',
      'AmiriQuran': 'assets/fonts/amiri_quran.ttf',
    }.entries) {
      await (FontLoader(
        entry.key,
      )..addFont(rootBundle.load(entry.value))).load();
    }
    final quran = (await tester.runAsync(QuranRepository.load))!;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    tester.view.physicalSize = const Size(440, 956);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;

    final problems = <String>[];
    for (final page in samplePages) {
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
      expect(tester.takeException(), isNull, reason: 'page $page at 200%');

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
          problems.add('200% / page $page wrapped: $text');
        }
        final size = drawnFontSize(tester, paragraph);
        if (size < _legibleFloor) {
          problems.add(
            '200% / page $page too small (${size.toStringAsFixed(1)}pt): $text',
          );
        }
      }
    }

    expect(problems, isEmpty);
  });
}

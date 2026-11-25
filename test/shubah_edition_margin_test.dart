import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quran_qiraat/features/reader/mushaf_reader_page.dart';
import 'package:quran_qiraat/quran_qiraat.dart';

void main() {
  for (final (page, location, note, shubah) in [
    (8, '2:51:7', 'الإدغام', 'ٱتَّخَذتُّمُ'),
    (10, '2:67:13', 'الحرف المخالف لحفص', 'هُزُؤٗاۖ'),
  ]) {
    testWidgets('page $page shows the imported Shubah edition note', (
      tester,
    ) async {
      final quran = (await tester.runAsync(QuranRepository.load))!;
      final variants = quran.qiraatVariants!;
      final entry = variants
          .forWord(location)
          .singleWhere((entry) => entry.editionNote == note);
      expect(variants.readingFor(entry, 'shubah')!.text, shubah);
      expect(quran.qiraatJuncturesOnPage(page), contains(entry));

      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
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
                onMarginRiwayahChanged: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text(shubah).first);
      await tester.pumpAndSettle();
      expect(find.text(note), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  }
}

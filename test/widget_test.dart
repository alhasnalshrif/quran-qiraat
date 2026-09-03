import 'package:flutter_test/flutter_test.dart';

import 'dart:ui';

import 'package:quran_qiraat/quran_qiraat.dart';
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

    expect(find.text('مصحف حفص بالهامش'), findsOneWidget);
    expect(find.text('مصحف حفص وبهامشه شعبة'), findsOneWidget);
    expect(find.text('مصحف حفص وبهامشه قالون'), findsOneWidget);
  });
}

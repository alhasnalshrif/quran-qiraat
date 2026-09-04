import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quran_qiraat/quran_qiraat.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
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
      differenceWords: {
        MarginRiwayah.shubah: {
          '1:1': [5, 10],
        },
      },
    );

    await tester.pumpWidget(
      QuranQiraatApp(preferences: preferences, quran: quran),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

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

Future<void> _loadFonts() async {
  final fonts = {
    'NotoSansArabic': 'assets/fonts/noto_sans_arabic.ttf',
    'HafsSmart': 'assets/fonts/hafs_smart.ttf',
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

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/quran_repository.dart';
import '../features/reader/mushaf_reader_page.dart';

class QuranQiraatApp extends StatelessWidget {
  const QuranQiraatApp({
    super.key,
    required this.preferences,
    required this.quran,
  });

  final SharedPreferences preferences;
  final QuranRepository quran;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'مصحف القراءات',
    scrollBehavior: const QuranScrollBehavior(),
    theme: ThemeData(
      useMaterial3: true,
      fontFamily: 'NotoSansArabic',
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xff4f9259),
        surface: const Color(0xfffffdf7),
      ),
      scaffoldBackgroundColor: const Color(0xfffffdf7),
    ),
    builder: (context, child) => Directionality(
      textDirection: TextDirection.rtl,
      child: child ?? const SizedBox.shrink(),
    ),
    home: MushafReaderPage(preferences: preferences, quran: quran),
  );
}

class QuranScrollBehavior extends MaterialScrollBehavior {
  const QuranScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => const {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.stylus,
  };
}

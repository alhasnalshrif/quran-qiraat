import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/quran_repository.dart';
import '../features/home/mushaf_picker_page.dart';

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
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff0d6249)),
      scaffoldBackgroundColor: const Color(0xfff8f5ed),
    ),
    home: MushafPickerPage(preferences: preferences, quran: quran),
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

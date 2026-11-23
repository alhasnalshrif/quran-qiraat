import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/quran_repository.dart';
import '../features/reader/mushaf_reader_page.dart';
import 'quran_theme.dart';

class QuranQiraatApp extends StatefulWidget {
  const QuranQiraatApp({
    super.key,
    required this.preferences,
    required this.quran,
  });

  final SharedPreferences preferences;
  final QuranRepository quran;

  @override
  State<QuranQiraatApp> createState() => _QuranQiraatAppState();
}

class _QuranQiraatAppState extends State<QuranQiraatApp> {
  late ThemeMode _appearance = readerThemeMode(widget.preferences);

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'مصحف القراءات',
    scrollBehavior: const QuranScrollBehavior(),
    locale: quranLocales.first,
    supportedLocales: quranLocales,
    localizationsDelegates: quranLocalizations,
    theme: quranTheme(night: false),
    darkTheme: quranTheme(night: true),
    themeMode: _appearance,
    themeAnimationDuration: Duration.zero,
    home: MushafReaderPage(
      preferences: widget.preferences,
      quran: widget.quran,
      onAppearanceChanged: (mode) => setState(() => _appearance = mode),
    ),
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

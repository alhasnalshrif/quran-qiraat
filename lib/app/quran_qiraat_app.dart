import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/quran_repository.dart';
import '../features/reader/mushaf_reader_page.dart';
import '../updates/providers.dart';
import '../updates/update_check_runner.dart';
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
    home: _ProvidedAppScope(
      preferences: widget.preferences,
      quran: widget.quran,
      child: UpdateCheckRunner(
        child: MushafReaderPage(
          preferences: widget.preferences,
          quran: widget.quran,
          onAppearanceChanged: (mode) => setState(() => _appearance = mode),
        ),
      ),
    ),
  );
}

/// Guarantees a ProviderScope exists above the app.
///
/// `QuranBootstrap` already provides one when the app starts normally. Widget
/// tests and embedders mount this widget directly, and the reader now depends
/// on providers (A-12), so a missing scope would throw. When a scope is
/// already present its container is reused, so the bootstrap overrides still
/// win.
class _ProvidedAppScope extends ConsumerWidget {
  const _ProvidedAppScope({
    required this.preferences,
    required this.quran,
    required this.child,
  });

  final SharedPreferences preferences;
  final QuranRepository quran;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    try {
      ProviderScope.containerOf(context, listen: false);
      return child;
    } catch (_) {
      return ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          quranRepositoryProvider.overrideWithValue(quran),
        ],
        child: child,
      );
    }
  }
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

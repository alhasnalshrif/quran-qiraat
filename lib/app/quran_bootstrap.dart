import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/quran_repository.dart';
import 'quran_qiraat_app.dart';
import 'quran_theme.dart';

typedef QuranSession = ({SharedPreferences preferences, QuranRepository quran});

Future<QuranSession> loadQuranSession() async {
  final preferences = await SharedPreferences.getInstance();
  final quran = await QuranRepository.load();
  return (preferences: preferences, quran: quran);
}

class QuranBootstrap extends StatefulWidget {
  const QuranBootstrap({super.key, this.loader = loadQuranSession});

  final Future<QuranSession> Function() loader;

  @override
  State<QuranBootstrap> createState() => _QuranBootstrapState();
}

class _QuranBootstrapState extends State<QuranBootstrap> {
  late Future<QuranSession> _session;

  @override
  void initState() {
    super.initState();
    _session = Future.sync(widget.loader);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<QuranSession>(
    future: _session,
    builder: (context, snapshot) {
      final session = snapshot.data;
      if (session != null) {
        return QuranQiraatApp(
          preferences: session.preferences,
          quran: session.quran,
        );
      }
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: quranTheme(night: false),
        darkTheme: quranTheme(night: true),
        themeMode: ThemeMode.system,
        locale: quranLocales.first,
        supportedLocales: quranLocales,
        localizationsDelegates: quranLocalizations,
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!snapshot.hasError) ...[
                      const CircularProgressIndicator(),
                      const SizedBox(height: 16),
                      const Text('جارٍ تحميل المصحف'),
                    ] else ...[
                      const Text(
                        'تعذر فتح بيانات المصحف. جرّب إعادة المحاولة.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: () => setState(() {
                          _session = Future.sync(widget.loader);
                        }),
                        child: const Text('إعادة المحاولة'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

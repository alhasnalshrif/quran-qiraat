import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/quran_repository.dart';
import '../../domain/models/margin_riwayah.dart';
import '../reader/mushaf_reader_page.dart';

class MushafPickerPage extends StatelessWidget {
  const MushafPickerPage({
    super.key,
    required this.preferences,
    required this.quran,
  });

  final SharedPreferences preferences;
  final QuranRepository quran;

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Icon(
                Icons.menu_book_rounded,
                size: 74,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 18),
              const Text(
                'مصحف حفص بالهامش',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'اختر الرواية الظاهرة في الهامش',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 38),
              for (final riwayah in MarginRiwayah.values) ...[
                _MushafChoice(
                  riwayah: riwayah,
                  preferences: preferences,
                  quran: quran,
                ),
                if (riwayah != MarginRiwayah.values.last)
                  const SizedBox(height: 14),
              ],
              const Spacer(flex: 2),
              const Text(
                'النصوص والخطوط مضمّنة داخل التطبيق — بلا إنترنت',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Color(0xff6a6a62)),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _MushafChoice extends StatelessWidget {
  const _MushafChoice({
    required this.riwayah,
    required this.preferences,
    required this.quran,
  });

  final MarginRiwayah riwayah;
  final SharedPreferences preferences;
  final QuranRepository quran;

  @override
  Widget build(BuildContext context) => FilledButton.tonalIcon(
    style: FilledButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
      alignment: Alignment.centerRight,
    ),
    icon: const Icon(Icons.auto_stories_outlined),
    label: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(riwayah.title, style: const TextStyle(fontSize: 17)),
        const SizedBox(height: 4),
        Text(riwayah.shortName, style: const TextStyle(fontSize: 13)),
      ],
    ),
    onPressed: () => Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MushafReaderPage(
          riwayah: riwayah,
          preferences: preferences,
          quran: quran,
        ),
      ),
    ),
  );
}

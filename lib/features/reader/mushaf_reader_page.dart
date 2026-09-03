import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/quran_repository.dart';
import '../../domain/models/ayah.dart';
import '../../domain/models/margin_difference.dart';
import '../../domain/models/margin_riwayah.dart';

class MushafReaderPage extends StatefulWidget {
  const MushafReaderPage({
    super.key,
    required this.riwayah,
    required this.preferences,
    required this.quran,
  });

  final MarginRiwayah riwayah;
  final SharedPreferences preferences;
  final QuranRepository quran;

  @override
  State<MushafReaderPage> createState() => _MushafReaderPageState();
}

class _MushafReaderPageState extends State<MushafReaderPage> {
  static const pageCount = 604;
  late final PageController _controller;
  late int _page;

  String get _pageKey => 'last_page_${widget.riwayah.storageKey}';

  @override
  void initState() {
    super.initState();
    _page = widget.preferences.getInt(_pageKey) ?? 1;
    _controller = PageController(initialPage: _page - 1);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _goToPage() async {
    final result = await showDialog<int>(
      context: context,
      builder: (context) {
        final input = TextEditingController(text: '$_page');
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Text('الانتقال إلى صفحة'),
            content: TextField(
              controller: input,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(hintText: 'من 1 إلى 604'),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('إلغاء'),
              ),
              FilledButton(
                onPressed: () =>
                    Navigator.pop(context, int.tryParse(input.text)),
                child: const Text('انتقال'),
              ),
            ],
          ),
        );
      },
    );
    if (result == null || result < 1 || result > pageCount) return;
    await _controller.animateToPage(
      result - 1,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  void _onPageChanged(int index) {
    final page = index + 1;
    setState(() => _page = page);
    widget.preferences.setInt(_pageKey, page);
  }

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(
      appBar: AppBar(
        title: Text(widget.riwayah.title, style: const TextStyle(fontSize: 17)),
        actions: [
          TextButton(
            onPressed: _goToPage,
            child: Text(
              'صفحة $_page',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      body: PageView.builder(
        controller: _controller,
        itemCount: pageCount,
        reverse: true,
        onPageChanged: _onPageChanged,
        itemBuilder: (_, index) => QuranTextPage(
          page: index + 1,
          riwayah: widget.riwayah,
          quran: widget.quran,
        ),
      ),
    ),
  );
}

class QuranTextPage extends StatelessWidget {
  const QuranTextPage({
    super.key,
    required this.page,
    required this.riwayah,
    required this.quran,
  });

  final int page;
  final MarginRiwayah riwayah;
  final QuranRepository quran;

  @override
  Widget build(BuildContext context) {
    final verses = quran.page(page);
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(18),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1080, minHeight: 760),
            child: Container(
              color: const Color(0xfffffdf8),
              padding: const EdgeInsets.fromLTRB(28, 26, 28, 22),
              child: Row(
                textDirection: TextDirection.ltr,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 158,
                    child: _Margin(
                      verses: verses,
                      riwayah: riwayah,
                      quran: quran,
                    ),
                  ),
                  const VerticalDivider(
                    width: 28,
                    thickness: 1,
                    color: Color(0xffd7cfbc),
                  ),
                  Expanded(
                    child: Directionality(
                      textDirection: TextDirection.rtl,
                      child: Column(
                        children: [
                          const Text(
                            'حفص عن عاصم',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Color(0xff0d6249),
                            ),
                          ),
                          const Divider(height: 19),
                          _MushafText(
                            verses: verses,
                            riwayah: riwayah,
                            quran: quran,
                          ),
                          const SizedBox(height: 18),
                          Text('$page', style: const TextStyle(fontSize: 14)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MushafText extends StatelessWidget {
  const _MushafText({
    required this.verses,
    required this.riwayah,
    required this.quran,
  });

  final List<Ayah> verses;
  final MarginRiwayah riwayah;
  final QuranRepository quran;

  @override
  Widget build(BuildContext context) => Text.rich(
    TextSpan(
      children: [
        for (final ayah in verses)
          TextSpan(
            text: '${ayah.text} ',
            style: quran.hasDifference(riwayah, ayah)
                ? const TextStyle(backgroundColor: Color(0x18b96d47))
                : null,
          ),
      ],
    ),
    textDirection: TextDirection.rtl,
    textAlign: TextAlign.justify,
    style: const TextStyle(
      fontFamily: 'HafsSmart',
      fontSize: 23,
      height: 1.72,
      color: Color(0xff171717),
    ),
  );
}

class _Margin extends StatelessWidget {
  const _Margin({
    required this.verses,
    required this.riwayah,
    required this.quran,
  });

  final List<Ayah> verses;
  final MarginRiwayah riwayah;
  final QuranRepository quran;

  @override
  Widget build(BuildContext context) {
    final differences = quran.differencesFor(riwayah, verses);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Column(
        children: [
          Text(
            riwayah.shortName,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 12,
              color: Color(0xff0d6249),
            ),
          ),
          const Text(
            'اضغط على علامة الفرق',
            style: TextStyle(fontSize: 9, color: Color(0xff6a6a62)),
          ),
          const Divider(height: 16, color: Color(0xffa38b61)),
          if (differences.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text(
                'لا توجد فروق في هذه الصفحة',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 10, color: Color(0xff6a6a62)),
              ),
            )
          else
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 3,
              runSpacing: 3,
              children: [
                for (final difference in differences)
                  _MarginMarker(
                    difference: difference,
                    riwayah: riwayah,
                    quran: quran,
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _MarginMarker extends StatelessWidget {
  const _MarginMarker({
    required this.difference,
    required this.riwayah,
    required this.quran,
  });

  final MarginDifference difference;
  final MarginRiwayah riwayah;
  final QuranRepository quran;

  @override
  Widget build(BuildContext context) => TextButton.icon(
    onPressed: () => _showComparison(context),
    icon: const Icon(Icons.bookmark_rounded, size: 13),
    label: Text(
      '${difference.hafs.surah}:${difference.hafs.number}',
      style: const TextStyle(fontSize: 10),
    ),
    style: TextButton.styleFrom(
      foregroundColor: const Color(0xff9e3f2e),
      padding: const EdgeInsets.symmetric(horizontal: 3),
      minimumSize: Size.zero,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    ),
  );

  void _showComparison(BuildContext context) => showDialog<void>(
    context: context,
    builder: (context) => Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: Text('الآية ${difference.hafs.surah}:${difference.hafs.number}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final wordIndex in difference.wordIndexes)
              _WordComparisonRow(
                comparison: quran.comparedWord(
                  hafs: difference.hafs,
                  variant: difference.variant,
                  wordIndex: wordIndex,
                ),
                riwayah: riwayah,
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    ),
  );
}

class _WordComparisonRow extends StatelessWidget {
  const _WordComparisonRow({required this.comparison, required this.riwayah});

  final WordComparison comparison;
  final MarginRiwayah riwayah;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(
      'حفص: ${comparison.hafs}\n'
      '${riwayah.shortName.split(' ').first}: ${comparison.variant}'
      '${comparison.isPerformanceOnly ? '\nاختلاف أداء أو رسم' : ''}',
      style: const TextStyle(height: 1.45),
    ),
  );
}

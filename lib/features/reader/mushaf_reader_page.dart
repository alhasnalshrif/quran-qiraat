import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:quran_qiraat/domain/models/ayah.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/quran_repository.dart';
import '../../domain/models/margin_difference.dart';
import '../../domain/models/margin_riwayah.dart';

const _green = Color(0xff4f9259);
const _paper = Color(0xfffffdf7);

class MushafReaderPage extends StatefulWidget {
  const MushafReaderPage({
    super.key,
    required this.preferences,
    required this.quran,
  });

  final SharedPreferences preferences;
  final QuranRepository quran;

  @override
  State<MushafReaderPage> createState() => _MushafReaderPageState();
}

class _MushafReaderPageState extends State<MushafReaderPage> {
  static const _pageCount = 604;
  static const _lastPageKey = 'last_page';
  static const _readingKey = 'primary_reading';

  final _scaffoldKey = GlobalKey<ScaffoldState>();
  late final PageController _pageController;
  late int _page;
  late QuranReading _reading;
  MarginRiwayah _differenceRiwayah = MarginRiwayah.shubah;

  @override
  void initState() {
    super.initState();
    _page = widget.preferences.getInt(_lastPageKey) ?? 1;
    _reading = _savedReading(widget.preferences.getString(_readingKey));
    _differenceRiwayah = _reading.differenceSource ?? MarginRiwayah.shubah;
    _pageController = PageController(initialPage: _page - 1);
  }

  QuranReading _savedReading(String? value) => QuranReading.values.firstWhere(
    (reading) => reading.name == value,
    orElse: () => QuranReading.hafs,
  );

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onPageChanged(int index) {
    setState(() => _page = index + 1);
    widget.preferences.setInt(_lastPageKey, _page);
  }

  Future<void> _selectReading() async {
    final selected = await showModalBottomSheet<QuranReading>(
      context: context,
      backgroundColor: _paper,
      showDragHandle: true,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (_) => _ReadingSheet(selected: _reading),
    );
    if (!mounted || selected == null || selected == _reading) return;
    setState(() {
      _reading = selected;
      _differenceRiwayah = selected.differenceSource ?? _differenceRiwayah;
    });
    widget.preferences.setString(_readingKey, selected.name);
  }

  Future<void> _goToPage() async {
    final result = await showDialog<int>(
      context: context,
      builder: (_) => _GoToPageDialog(initialPage: _page),
    );
    if (!mounted || result == null || result < 1 || result > _pageCount) {
      return;
    }
    await _pageController.animateToPage(
      result - 1,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    key: _scaffoldKey,
    drawer: DifferencesDrawer(
      page: _page,
      riwayah: _differenceRiwayah,
      quran: widget.quran,
      onRiwayahChanged: (value) => setState(() => _differenceRiwayah = value),
    ),
    body: SafeArea(
      bottom: false,
      child: Column(
        children: [
          ReaderTopBar(
            page: _page,
            onOpenDifferences: () => _scaffoldKey.currentState?.openDrawer(),
          ),
          Expanded(
            child: PageView.builder(
              controller: _pageController,
              itemCount: _pageCount,
              // In an RTL mushaf, the reader advances with a right-to-left swipe.
              reverse: false,
              onPageChanged: _onPageChanged,
              itemBuilder: (_, index) => QuranTextPage(
                page: index + 1,
                reading: _reading,
                highlightRiwayah: _differenceRiwayah,
                quran: widget.quran,
              ),
            ),
          ),
        ],
      ),
    ),
    bottomNavigationBar: ReaderControls(
      page: _page,
      reading: _reading,
      onOpenDifferences: () => _scaffoldKey.currentState?.openDrawer(),
      onSelectReading: _selectReading,
      onGoToPage: _goToPage,
    ),
  );
}

class _GoToPageDialog extends StatefulWidget {
  const _GoToPageDialog({required this.initialPage});

  final int initialPage;

  @override
  State<_GoToPageDialog> createState() => _GoToPageDialogState();
}

class _GoToPageDialogState extends State<_GoToPageDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: '${widget.initialPage}');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('الانتقال إلى صفحة'),
    content: TextField(
      controller: _controller,
      autofocus: true,
      keyboardType: TextInputType.number,
      textDirection: TextDirection.rtl,
      decoration: const InputDecoration(hintText: 'من 1 إلى 604'),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('إلغاء'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, int.tryParse(_controller.text)),
        child: const Text('انتقال'),
      ),
    ],
  );
}

class ReaderTopBar extends StatelessWidget {
  const ReaderTopBar({
    super.key,
    required this.page,
    required this.onOpenDifferences,
  });

  final int page;
  final VoidCallback onOpenDifferences;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
    child: Material(
      color: _green,
      elevation: 3,
      shadowColor: const Color(0x33000000),
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        height: 62,
        child: Row(
          children: [
            IconButton(
              tooltip: 'فروق الصفحة',
              onPressed: onOpenDifferences,
              color: Colors.white,
              icon: const Icon(Iconsax.book_1),
            ),
            const Expanded(
              child: Text(
                'مصحف القراءات',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 12),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .16),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 11,
                    vertical: 6,
                  ),
                  child: Text(
                    '$page',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class ReaderControls extends StatelessWidget {
  const ReaderControls({
    super.key,
    required this.page,
    required this.reading,
    required this.onOpenDifferences,
    required this.onSelectReading,
    required this.onGoToPage,
  });

  final int page;
  final QuranReading reading;
  final VoidCallback onOpenDifferences;
  final VoidCallback onSelectReading;
  final VoidCallback onGoToPage;

  @override
  Widget build(BuildContext context) => SafeArea(
    minimum: const EdgeInsets.fromLTRB(12, 6, 12, 10),
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: _green,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x26000000),
            blurRadius: 14,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: SizedBox(
        height: 70,
        child: Row(
          children: [
            Expanded(
              child: _ControlButton(
                icon: Iconsax.book_1,
                label: 'الفروق',
                onPressed: onOpenDifferences,
              ),
            ),
            Expanded(
              flex: 2,
              child: _ReadingButton(
                reading: reading,
                onPressed: onSelectReading,
              ),
            ),
            Expanded(
              child: _ControlButton(
                icon: Iconsax.search_normal,
                label: 'صفحة $page',
                onPressed: onGoToPage,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onPressed,
    borderRadius: BorderRadius.circular(20),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, color: Colors.white, size: 25),
        const SizedBox(height: 3),
        Text(label, style: const TextStyle(color: Colors.white, fontSize: 11)),
      ],
    ),
  );
}

class _ReadingButton extends StatelessWidget {
  const _ReadingButton({required this.reading, required this.onPressed});

  final QuranReading reading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
    child: FilledButton.icon(
      onPressed: onPressed,
      icon: const Icon(Iconsax.book_saved),
      label: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('القراءة', style: TextStyle(fontSize: 10)),
          Text(
            reading.title,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ],
      ),
      style: FilledButton.styleFrom(
        backgroundColor: const Color(0xfff2df9b),
        foregroundColor: const Color(0xff315f39),
      ),
    ),
  );
}

class _ReadingSheet extends StatelessWidget {
  const _ReadingSheet({required this.selected});

  final QuranReading selected;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'اختر القراءة',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 16),
        for (final reading in QuranReading.values)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: ListTile(
              onTap: () => Navigator.pop(context, reading),
              selected: reading == selected,
              selectedTileColor: const Color(0xffe2efdc),
              tileColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: BorderSide(
                  color: reading == selected ? _green : const Color(0xffe4dfcf),
                ),
              ),
              leading: CircleAvatar(
                backgroundColor: reading == selected
                    ? _green
                    : const Color(0xfff0ebdc),
                foregroundColor: reading == selected ? Colors.white : _green,
                child: Text(reading.shortTitle.characters.first),
              ),
              title: Text(
                reading.title,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                reading == QuranReading.hafs
                    ? 'القراءة الافتراضية'
                    : 'متاحة بالكامل دون إنترنت',
              ),
              trailing: reading == selected
                  ? const Icon(Iconsax.tick_circle, color: _green)
                  : null,
            ),
          ),
      ],
    ),
  );
}

class QuranTextPage extends StatelessWidget {
  const QuranTextPage({
    super.key,
    required this.page,
    required this.reading,
    required this.highlightRiwayah,
    required this.quran,
  });

  final int page;
  final QuranReading reading;
  final MarginRiwayah highlightRiwayah;
  final QuranRepository quran;

  @override
  Widget build(BuildContext context) {
    final verses = quran.pageForReading(reading, page);
    final surahNames = quran
        .page(page)
        .map((ayah) => ayah.surahName)
        .toSet()
        .join(' • ');
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 900,
              minHeight: math.max(0, constraints.maxHeight - 38),
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(6),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x10000000),
                    blurRadius: 12,
                    offset: Offset(0, 3),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'صفحة $page',
                          style: const TextStyle(
                            color: _green,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Flexible(
                          child: Text(
                            surahNames,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Text(
                          reading.shortTitle,
                          style: const TextStyle(
                            color: _green,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 24, color: Color(0xffd9dfd5)),
                    Text.rich(
                      TextSpan(
                        children: [
                          for (final ayah in verses) ...[
                            _ayahTextSpan(
                              ayah: ayah,
                              highlightedWordIndexes: quran.wordsFor(
                                highlightRiwayah,
                                ayah,
                              ),
                            ),
                            WidgetSpan(
                              alignment: PlaceholderAlignment.middle,
                              child: _VerseNumberMarker(number: ayah.number),
                            ),
                            const TextSpan(text: ' '),
                          ],
                        ],
                      ),
                      textDirection: TextDirection.rtl,
                      textAlign: TextAlign.justify,
                      style: TextStyle(
                        fontFamily: reading.fontFamily,
                        fontSize: 25,
                        height: 1.8,
                        color: const Color(0xff151515),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      '$page',
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xff685f51),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

TextSpan _ayahTextSpan({
  required Ayah ayah,
  required List<int> highlightedWordIndexes,
}) {
  final words = ayah.text.trim().split(RegExp(r'\s+'));
  final comparisonWordCount = ayah.comparisonText
      .trim()
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .length;
  final highlightsWholeAyah =
      highlightedWordIndexes.isNotEmpty &&
      highlightedWordIndexes.length >= comparisonWordCount;

  if (highlightsWholeAyah) {
    return TextSpan(text: ayah.text.trim(), style: _wholeAyahDifferenceStyle);
  }

  final highlightedWords = highlightedWordIndexes.toSet();
  return TextSpan(
    children: [
      for (var index = 0; index < words.length; index++)
        TextSpan(
          text: '${words[index]}${index == words.length - 1 ? '' : ' '}',
          style: highlightedWords.contains(index + 1)
              ? _wordDifferenceStyle
              : null,
        ),
    ],
  );
}

const _wordDifferenceStyle = TextStyle(
  backgroundColor: Color(0x2A61A06C),
  color: Color(0xff174d20),
);

const _wholeAyahDifferenceStyle = TextStyle(
  backgroundColor: Color(0x1F61A06C),
  color: Color(0xff174d20),
);

class _VerseNumberMarker extends StatelessWidget {
  const _VerseNumberMarker({required this.number});

  final int number;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsetsDirectional.only(start: 5, end: 2),
    child: DecoratedBox(
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: Color(0xffeef3e9),
      ),
      child: SizedBox(
        width: 24,
        height: 24,
        child: Center(
          child: Text(
            _toArabicDigits(number),
            textDirection: TextDirection.rtl,
            style: const TextStyle(
              fontFamily: 'NotoSansArabic',
              fontSize: 11,
              height: 1,
              fontWeight: FontWeight.w700,
              color: _green,
            ),
          ),
        ),
      ),
    ),
  );
}

String _toArabicDigits(int value) => value
    .toString()
    .split('')
    .map((digit) => String.fromCharCode('٠'.codeUnitAt(0) + int.parse(digit)))
    .join();

class DifferencesDrawer extends StatelessWidget {
  const DifferencesDrawer({
    super.key,
    required this.page,
    required this.riwayah,
    required this.quran,
    required this.onRiwayahChanged,
  });

  final int page;
  final MarginRiwayah riwayah;
  final QuranRepository quran;
  final ValueChanged<MarginRiwayah> onRiwayahChanged;

  @override
  Widget build(BuildContext context) {
    final differences = quran.differencesFor(riwayah, quran.page(page));
    return Drawer(
      width: math.min(MediaQuery.sizeOf(context).width * .9, 420),
      backgroundColor: _paper,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Iconsax.close_circle),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'اختلافات الصفحة $page',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: SegmentedButton<MarginRiwayah>(
                segments: const [
                  ButtonSegment(
                    value: MarginRiwayah.shubah,
                    label: Text('شعبة'),
                  ),
                  ButtonSegment(
                    value: MarginRiwayah.qalun,
                    label: Text('قالون'),
                  ),
                ],
                selected: {riwayah},
                onSelectionChanged: (value) => onRiwayahChanged(value.first),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: differences.isEmpty
                  ? const Center(
                      child: Text('لا توجد اختلافات مسجلة في هذه الصفحة'),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
                      itemCount: differences.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (_, index) => DifferenceCard(
                        difference: differences[index],
                        riwayah: riwayah,
                        quran: quran,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class DifferenceCard extends StatelessWidget {
  const DifferenceCard({
    super.key,
    required this.difference,
    required this.riwayah,
    required this.quran,
  });

  final MarginDifference difference;
  final MarginRiwayah riwayah;
  final QuranRepository quran;

  @override
  Widget build(BuildContext context) => Card(
    elevation: 0,
    color: Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: const BorderSide(color: Color(0xffdce7d9)),
    ),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'الآية ${difference.hafs.surah}:${difference.hafs.number}',
            style: const TextStyle(color: _green, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          for (final wordIndex in difference.wordIndexes)
            _ComparisonRow(
              comparison: quran.comparedWord(
                hafs: difference.hafs,
                variant: difference.variant,
                wordIndex: wordIndex,
              ),
              riwayah: riwayah,
            ),
        ],
      ),
    ),
  );
}

class _ComparisonRow extends StatelessWidget {
  const _ComparisonRow({required this.comparison, required this.riwayah});

  final WordComparison comparison;
  final MarginRiwayah riwayah;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('حفص: ${comparison.hafs}', style: const TextStyle(fontSize: 16)),
        Text(
          '${riwayah.shortName.split(' ').first}: ${comparison.variant}',
          style: TextStyle(
            fontFamily: riwayah.fontFamily,
            fontSize: 16,
            color: const Color(0xff8c3e32),
          ),
        ),
        if (comparison.isPerformanceOnly)
          const Text(
            'اختلاف أداء أو رسم',
            style: TextStyle(fontSize: 11, color: Color(0xff746f65)),
          ),
      ],
    ),
  );
}

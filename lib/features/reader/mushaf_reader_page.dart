import 'dart:math' as math;

import 'package:flutter/gestures.dart';

import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:quran_qiraat/domain/models/ayah.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/quran_repository.dart';
import '../../domain/models/margin_difference.dart';
import '../../domain/models/margin_riwayah.dart';
import '../../domain/models/mushaf_layout.dart';
import '../../domain/models/reading_difference.dart';

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
  static const _primaryReadingKey = 'primary_reading';
  static const _comparisonReadingKey = 'comparison_reading';

  final _scaffoldKey = GlobalKey<ScaffoldState>();
  late final PageController _pageController;
  late int _page;
  late QuranReading _primaryReading;
  late QuranReading _comparisonReading;

  @override
  void initState() {
    super.initState();
    _page = widget.preferences.getInt(_lastPageKey) ?? 1;
    _primaryReading = _savedReading(
      widget.preferences.getString(_primaryReadingKey),
    );
    _comparisonReading = _savedReading(
      widget.preferences.getString(_comparisonReadingKey),
    );
    if (_comparisonReading == _primaryReading) {
      _comparisonReading = _primaryReading == QuranReading.hafs
          ? QuranReading.shubah
          : QuranReading.hafs;
    }
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

  Future<void> _selectReadings() async {
    final selected = await showModalBottomSheet<_ReadingPair>(
      context: context,
      backgroundColor: _paper,
      showDragHandle: true,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (_) => _ReadingPairSheet(
        primary: _primaryReading,
        comparison: _comparisonReading,
      ),
    );
    if (!mounted || selected == null) return;
    setState(() {
      _primaryReading = selected.primary;
      _comparisonReading = selected.comparison;
    });
    widget.preferences.setString(_primaryReadingKey, selected.primary.name);
    widget.preferences.setString(
      _comparisonReadingKey,
      selected.comparison.name,
    );
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
      baseReading: _primaryReading,
      comparisonReading: _comparisonReading,
      quran: widget.quran,
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
                reading: _primaryReading,
                comparisonReading: _comparisonReading,
                quran: widget.quran,
              ),
            ),
          ),
        ],
      ),
    ),
    bottomNavigationBar: ReaderControls(
      page: _page,
      primaryReading: _primaryReading,
      comparisonReading: _comparisonReading,
      onOpenDifferences: () => _scaffoldKey.currentState?.openDrawer(),
      onSelectReading: _selectReadings,
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
    required this.primaryReading,
    required this.comparisonReading,
    required this.onOpenDifferences,
    required this.onSelectReading,
    required this.onGoToPage,
  });

  final int page;
  final QuranReading primaryReading;
  final QuranReading comparisonReading;
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
                primaryReading: primaryReading,
                comparisonReading: comparisonReading,
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
  const _ReadingButton({
    required this.primaryReading,
    required this.comparisonReading,
    required this.onPressed,
  });

  final QuranReading primaryReading;
  final QuranReading comparisonReading;
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
          const Text('القراءتان', style: TextStyle(fontSize: 10)),
          Text(
            '${primaryReading.shortTitle} × ${comparisonReading.shortTitle}',
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

class _ReadingPair {
  const _ReadingPair({required this.primary, required this.comparison});

  final QuranReading primary;
  final QuranReading comparison;
}

class _ReadingPairSheet extends StatefulWidget {
  const _ReadingPairSheet({required this.primary, required this.comparison});

  final QuranReading primary;
  final QuranReading comparison;

  @override
  State<_ReadingPairSheet> createState() => _ReadingPairSheetState();
}

class _ReadingPairSheetState extends State<_ReadingPairSheet> {
  late QuranReading _primary = widget.primary;
  late QuranReading _comparison = widget.comparison;

  void _setPrimary(QuranReading value) => setState(() {
    _primary = value;
    if (_comparison == value) {
      _comparison = value == QuranReading.hafs
          ? QuranReading.shubah
          : QuranReading.hafs;
    }
  });

  void _setComparison(QuranReading value) => setState(() {
    _comparison = value;
    if (_primary == value) {
      _primary = value == QuranReading.hafs
          ? QuranReading.shubah
          : QuranReading.hafs;
    }
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'اختر قراءتين للمقارنة',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        const Text(
          'الأولى هي النص الأساسي، والثانية هي النص الذي تراجعه. لا يمكن اختيار القراءة نفسها مرتين.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            color: Color(0xff645f55),
            height: 1.45,
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'القراءة الأساسية',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        for (final reading in QuranReading.values)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: ListTile(
              onTap: () => _setPrimary(reading),
              selected: reading == _primary,
              selectedTileColor: const Color(0xffe2efdc),
              tileColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: BorderSide(
                  color: reading == _primary ? _green : const Color(0xffe4dfcf),
                ),
              ),
              leading: CircleAvatar(
                backgroundColor: reading == _primary
                    ? _green
                    : const Color(0xfff0ebdc),
                foregroundColor: reading == _primary ? Colors.white : _green,
                child: Text(reading.shortTitle.characters.first),
              ),
              title: Text(
                reading.title,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              trailing: reading == _primary
                  ? const Icon(Iconsax.tick_circle, color: _green)
                  : null,
            ),
          ),
        const SizedBox(height: 4),
        const Text(
          'قراءة المراجعة',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        for (final reading in QuranReading.values)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: ListTile(
              onTap: () => _setComparison(reading),
              selected: reading == _comparison,
              selectedTileColor: const Color(0xffe2efdc),
              tileColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: BorderSide(
                  color: reading == _comparison
                      ? _green
                      : const Color(0xffe4dfcf),
                ),
              ),
              leading: CircleAvatar(
                backgroundColor: reading == _comparison
                    ? _green
                    : const Color(0xfff0ebdc),
                foregroundColor: reading == _comparison ? Colors.white : _green,
                child: Text(reading.shortTitle.characters.first),
              ),
              title: Text(
                reading.title,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              trailing: reading == _comparison
                  ? const Icon(Iconsax.tick_circle, color: _green)
                  : null,
            ),
          ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            _ReadingPair(primary: _primary, comparison: _comparison),
          ),
          child: const Text('تأكيد المقارنة'),
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
    required this.comparisonReading,
    required this.quran,
  });

  final int page;
  final QuranReading reading;
  final QuranReading comparisonReading;
  final QuranRepository quran;

  @override
  Widget build(BuildContext context) {
    if (reading == QuranReading.hafs) {
      final layoutPage = quran.hafsLayout?.page(page);
      if (layoutPage == null) {
        return const _LayoutUnavailablePage();
      }
      return _HafsLineLayoutPage(
        page: layoutPage,
        primaryReading: reading,
        comparisonReading: comparisonReading,
        quran: quran,
      );
    }
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
                    if (reading != QuranReading.hafs) ...[
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: const Color(0xfff8f5ee),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xffe8dfcc)),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Iconsax.info_circle,
                                size: 16,
                                color: Color(0xff8c703e),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'عرض مقارنة نصية لآيات صفحة حفص؛ لا يطابق تخطيط صفحات مصحف ${reading.shortTitle} الأصلي حتى توفر حزمة التخطيط.',
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    height: 1.4,
                                    color: Color(0xff5f4c27),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    for (final ayah in verses)
                      _TappableFlowAyah(
                        ayah: ayah,
                        primaryReading: reading,
                        comparisonReading: comparisonReading,
                        quran: quran,
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

class _TappableFlowAyah extends StatelessWidget {
  const _TappableFlowAyah({
    required this.ayah,
    required this.primaryReading,
    required this.comparisonReading,
    required this.quran,
  });

  final Ayah ayah;
  final QuranReading primaryReading;
  final QuranReading comparisonReading;
  final QuranRepository quran;

  @override
  Widget build(BuildContext context) {
    final words = ayah.comparisonText
        .trim()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList(growable: false);
    return Text.rich(
      TextSpan(
        children: [
          for (var index = 0; index < words.length; index++)
            TextSpan(
              text: '${words[index]} ',
              recognizer: TapGestureRecognizer()
                ..onTap = () => _showWordComparison(
                  context,
                  quran: quran,
                  primaryReading: primaryReading,
                  comparisonReading: comparisonReading,
                  word: MushafLayoutWord(
                    location: '${ayah.surah}:${ayah.number}:${index + 1}',
                    text: words[index],
                  ),
                ),
            ),
        ],
      ),
      textDirection: TextDirection.rtl,
      textAlign: TextAlign.justify,
      style: TextStyle(
        fontFamily: primaryReading.fontFamily,
        fontSize: 25,
        height: 1.8,
        color: const Color(0xff151515),
      ),
    );
  }
}

class _LayoutUnavailablePage extends StatelessWidget {
  const _LayoutUnavailablePage();

  @override
  Widget build(BuildContext context) => const Center(
    child: Padding(
      padding: EdgeInsets.all(28),
      child: Text(
        'تعذر تحميل تخطيط صفحة المصحف الموثق. لن يُستبدل بتدفق نصي تلقائيًا.',
        textAlign: TextAlign.center,
        textDirection: TextDirection.rtl,
      ),
    ),
  );
}

class _HafsLineLayoutPage extends StatelessWidget {
  const _HafsLineLayoutPage({
    required this.page,
    required this.primaryReading,
    required this.comparisonReading,
    required this.quran,
  });

  final MushafLayoutPage page;
  final QuranReading primaryReading;
  final QuranReading comparisonReading;
  final QuranRepository quran;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
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
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'صفحة ${page.number}',
                    style: const TextStyle(
                      color: _green,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Divider(height: 18, color: Color(0xffd9dfd5)),
                  for (final line in page.lines)
                    _MushafLine(
                      page: page.number,
                      line: line,
                      primaryReading: primaryReading,
                      comparisonReading: comparisonReading,
                      quran: quran,
                    ),
                  const SizedBox(height: 10),
                  Text(
                    '${page.number}',
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

class _MushafLine extends StatelessWidget {
  const _MushafLine({
    required this.page,
    required this.line,
    required this.primaryReading,
    required this.comparisonReading,
    required this.quran,
  });

  final int page;
  final MushafLayoutLine line;
  final QuranReading primaryReading;
  final QuranReading comparisonReading;
  final QuranRepository quran;

  @override
  Widget build(BuildContext context) {
    final text = line.displayText;
    if (line.type == MushafLayoutLineType.surahHeader) {
      return Padding(
        key: ValueKey('mushaf-line-$page-${line.number}'),
        padding: const EdgeInsets.only(bottom: 5),
        child: Text(
          text,
          textDirection: TextDirection.rtl,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontFamily: 'NotoSansArabic',
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
      );
    }
    if (line.type == MushafLayoutLineType.basmala) {
      return Padding(
        key: ValueKey('mushaf-line-$page-${line.number}'),
        padding: const EdgeInsets.only(bottom: 7),
        child: Text(
          text.isEmpty ? 'بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ' : text,
          textDirection: TextDirection.rtl,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontFamily: 'NotoSansArabic',
            fontSize: 18,
            height: 1.35,
          ),
        ),
      );
    }
    return Padding(
      key: ValueKey('mushaf-line-$page-${line.number}'),
      padding: const EdgeInsets.only(bottom: 3),
      child: LayoutBuilder(
        builder: (context, constraints) => _TappableJustifiedLine(
          words: line.words,
          fallbackText: text,
          maxWidth: constraints.maxWidth,
          onWordTap: (word) => _showWordComparison(
            context,
            quran: quran,
            primaryReading: primaryReading,
            comparisonReading: comparisonReading,
            word: word,
          ),
        ),
      ),
    );
  }
}

class _TappableJustifiedLine extends StatelessWidget {
  const _TappableJustifiedLine({
    required this.words,
    required this.fallbackText,
    required this.maxWidth,
    required this.onWordTap,
  });

  final List<MushafLayoutWord> words;
  final String fallbackText;
  final double maxWidth;
  final ValueChanged<MushafLayoutWord> onWordTap;

  static const _style = TextStyle(
    fontFamily: 'NotoSansArabic',
    fontSize: 22,
    height: 1.47,
    color: Color(0xff151515),
  );

  @override
  Widget build(BuildContext context) {
    if (words.isEmpty) {
      return Text(
        fallbackText,
        textDirection: TextDirection.rtl,
        style: _style,
      );
    }
    final displayWords = words
        .map((word) => _withAyahMarker(word.text))
        .toList(growable: false);
    final plain = displayWords.join(' ');
    final painter = TextPainter(
      text: TextSpan(text: plain, style: _style),
      textDirection: TextDirection.rtl,
      maxLines: 1,
    )..layout();
    final gaps = math.max(1, words.length - 1);
    final wordSpacing = ((maxWidth - painter.width) / gaps).clamp(-2.0, 10.0);
    return Text.rich(
      TextSpan(
        children: [
          for (var index = 0; index < words.length; index++)
            TextSpan(
              text:
                  '${displayWords[index]}${index == words.length - 1 ? '' : ' '}',
              recognizer: TapGestureRecognizer()
                ..onTap = () => onWordTap(words[index]),
            ),
        ],
      ),
      textDirection: TextDirection.rtl,
      textAlign: TextAlign.justify,
      softWrap: false,
      style: _style.copyWith(wordSpacing: wordSpacing),
    );
  }
}

/// Restores the Medina end-of-ayah sign around the source's plain Arabic
/// verse number while keeping its location identity untouched for comparison.
String _withAyahMarker(String text) => text.replaceFirstMapped(
  RegExp(r'([٠-٩]+)$'),
  (match) => ' ۝${match.group(1)}',
);

Future<void> _showWordComparison(
  BuildContext context, {
  required QuranRepository quran,
  required QuranReading primaryReading,
  required QuranReading comparisonReading,
  required MushafLayoutWord word,
}) async {
  final parts = word.location.split(':').map(int.tryParse).toList();
  if (parts.length != 3 || parts.any((part) => part == null)) return;
  final surah = parts[0]!;
  final ayah = parts[1]!;
  final wordIndex = parts[2]!;
  final difference = quran.publishedDifferenceForWord(
    baseReading: primaryReading,
    comparisonReading: comparisonReading,
    surah: surah,
    ayah: ayah,
    wordIndex: wordIndex,
  );
  final comparisonAyah = quran.ayahForReading(
    comparisonReading,
    '$surah:$ayah',
  );
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: _paper,
    showDragHandle: true,
    builder: (_) => _WordComparisonSheet(
      primaryReading: primaryReading,
      comparisonReading: comparisonReading,
      word: word,
      difference: difference,
      comparisonAyah: comparisonAyah,
    ),
  );
}

class _WordComparisonSheet extends StatelessWidget {
  const _WordComparisonSheet({
    required this.primaryReading,
    required this.comparisonReading,
    required this.word,
    required this.difference,
    required this.comparisonAyah,
  });

  final QuranReading primaryReading;
  final QuranReading comparisonReading;
  final MushafLayoutWord word;
  final ReadingDifference? difference;
  final Ayah? comparisonAyah;

  @override
  Widget build(BuildContext context) {
    final reviewedDifference = difference;
    final forward = reviewedDifference?.baseReading == primaryReading;
    final primaryText = reviewedDifference == null
        ? word.text
        : (forward == true
              ? reviewedDifference.baseSpan.text
              : reviewedDifference.targetSpan.text);
    final comparisonText = reviewedDifference == null
        ? null
        : (forward == true
              ? reviewedDifference.targetSpan.text
              : reviewedDifference.baseSpan.text);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'موضع ${word.location}',
            textAlign: TextAlign.center,
            style: const TextStyle(color: _green, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          _ReadingWordTile(label: primaryReading.title, text: primaryText),
          const SizedBox(height: 8),
          if (comparisonText != null)
            _ReadingWordTile(
              label: comparisonReading.title,
              text: comparisonText,
              accent: true,
            )
          else ...[
            const Text(
              'لا توجد محاذاة فرق معتمدة لهذه الكلمة في البيانات الحالية.',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            if (comparisonAyah != null) ...[
              const SizedBox(height: 8),
              Text(
                'نص الآية في قراءة ${comparisonReading.shortTitle} للاطلاع فقط (ليس محاذاة كلمة بكلمة):',
                style: const TextStyle(fontSize: 12, color: Color(0xff645f55)),
              ),
              const SizedBox(height: 4),
              Text(
                comparisonAyah!.comparisonText,
                textDirection: TextDirection.rtl,
                style: TextStyle(
                  fontFamily: comparisonReading.fontFamily,
                  fontSize: 18,
                ),
              ),
            ],
          ],
          if (difference?.scholarlyNotes case final notes?)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                notes,
                style: const TextStyle(fontSize: 12, color: Color(0xff555555)),
              ),
            ),
        ],
      ),
    );
  }
}

class _ReadingWordTile extends StatelessWidget {
  const _ReadingWordTile({
    required this.label,
    required this.text,
    this.accent = false,
  });
  final String label;
  final String text;
  final bool accent;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: accent ? const Color(0xffe6f0e4) : Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xffd9dfd5)),
    ),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: _green)),
          const SizedBox(height: 4),
          Text(
            text,
            textDirection: TextDirection.rtl,
            style: const TextStyle(fontFamily: 'NotoSansArabic', fontSize: 20),
          ),
        ],
      ),
    ),
  );
}

class DifferencesDrawer extends StatelessWidget {
  const DifferencesDrawer({
    super.key,
    required this.page,
    required this.baseReading,
    required this.comparisonReading,
    required this.quran,
  });

  final int page;
  final QuranReading baseReading;
  final QuranReading comparisonReading;
  final QuranRepository quran;

  @override
  Widget build(BuildContext context) {
    final riwayah = comparisonReading.differenceSource;
    final differences = baseReading == QuranReading.hafs && riwayah != null
        ? quran.differencesFor(riwayah, quran.page(page))
        : const <MarginDifference>[];
    final hasCandidate = baseReading == QuranReading.hafs && riwayah != null
        ? quran.hasCandidateDifferencesOnPage(riwayah, page)
        : false;

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
              child: Text(
                '${baseReading.shortTitle} × ${comparisonReading.shortTitle}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: _green,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: differences.isNotEmpty
                  ? ListView.separated(
                      padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
                      itemCount: differences.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (_, index) => DifferenceCard(
                        difference: differences[index],
                        riwayah: riwayah!,
                        quran: quran,
                      ),
                    )
                  : hasCandidate
                  ? const _CandidateUnreviewedNotice()
                  : _NoDifferencesNotice(
                      riwayah: riwayah,
                      comparisonReading: comparisonReading,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CandidateUnreviewedNotice extends StatelessWidget {
  const _CandidateUnreviewedNotice();

  @override
  Widget build(BuildContext context) => const Center(
    child: Padding(
      padding: EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: Color(0xfff7f3e8),
              shape: BoxShape.circle,
            ),
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Icon(
                Iconsax.document_filter,
                size: 32,
                color: Color(0xff8c703e),
              ),
            ),
          ),
          SizedBox(height: 16),
          Text(
            'بيانات قيد المراجعة العلمية',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: Color(0xff222222),
            ),
          ),
          SizedBox(height: 8),
          Text(
            'توجد مواضع مقارنة أولية في هذه الصفحة مستخرجة من مصادر مرشحة، وتتطلب مراجعة وتحقيقًا علميًا قبل النشر.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: Color(0xff666666),
              height: 1.5,
            ),
          ),
          SizedBox(height: 12),
          DecoratedBox(
            decoration: BoxDecoration(
              color: Color(0xffeee8da),
              borderRadius: BorderRadius.all(Radius.circular(8)),
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Text(
                'البيانات المرشحة لا تُعرض كفروق منشورة',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Color(0xff6b5832),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _NoDifferencesNotice extends StatelessWidget {
  const _NoDifferencesNotice({this.riwayah, required this.comparisonReading});

  final MarginRiwayah? riwayah;
  final QuranReading comparisonReading;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              color: Color(0xffedf4ee),
              shape: BoxShape.circle,
            ),
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Icon(Iconsax.book_1, size: 32, color: _green),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'لا توجد فروق معتمدة في هذه الصفحة',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: Color(0xff222222),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            riwayah == null
                ? 'لا توجد محاذاة فروق معتمدة لهذا اتجاه المقارنة في هذا الإصدار.'
                : 'لم تُسجَّل فروق مراجعة لرواية ${riwayah!.shortName} في هذه الصفحة ضمن هذا الإصدار، ولا يعني ذلك حصر جميع وجوه الرواية.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xff666666),
              height: 1.5,
            ),
          ),
        ],
      ),
    ),
  );
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
  Widget build(BuildContext context) {
    final diff = difference.difference;

    return Card(
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
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'الآية ${difference.hafs.surah}:${difference.hafs.number}',
                  style: const TextStyle(
                    color: _green,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (diff != null && diff.isOneToMany)
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      color: Color(0xffe8edf5),
                      borderRadius: BorderRadius.all(Radius.circular(6)),
                    ),
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      child: Text(
                        'محاذاة ١:N',
                        style: TextStyle(
                          fontSize: 10.5,
                          color: Color(0xff2d4f7c),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (diff != null)
              _ComparisonRow(
                comparison: quran.comparedDifference(diff),
                riwayah: riwayah,
              )
            else
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
        if (comparison.scholarlyNotes != null &&
            comparison.scholarlyNotes!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              comparison.scholarlyNotes!,
              style: const TextStyle(fontSize: 11, color: Color(0xff555555)),
            ),
          ),
      ],
    ),
  );
}

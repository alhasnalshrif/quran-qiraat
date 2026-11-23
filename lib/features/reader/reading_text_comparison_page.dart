import 'package:flutter/material.dart';

import '../../app/quran_theme.dart';
import '../../data/quran_repository.dart';
import '../../domain/models/margin_riwayah.dart';
import '../../domain/models/reading_alignment.dart';
import '../../domain/services/reading_alignment_engine.dart';

class ReadingTextComparisonPage extends StatelessWidget {
  const ReadingTextComparisonPage({
    super.key,
    required this.quran,
    required this.page,
    required this.baseReading,
    required this.targetReading,
  });

  final QuranRepository quran;
  final int page;
  final QuranReading baseReading;
  final QuranReading targetReading;

  @override
  Widget build(BuildContext context) {
    final result = quran.textDifferencesOnPage(
      baseReading,
      targetReading,
      page,
    );
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        backgroundColor: Colors.transparent,
        flexibleSpace: const QuranGlass(radius: 0, child: SizedBox.expand()),
        title: Text('المقارنة النصية · صفحة $page'),
        actions: [
          IconButton(
            tooltip: 'المصادر وحالة المراجعة',
            icon: const Icon(Icons.info_outline),
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute(
                builder: (_) => ReadingSourcesPage(quran: quran),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Text(
              '${baseReading.shortTitle} × ${targetReading.shortTitle}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: QuranDesign.gap),
            Text(
              'مقارنة نصية غير معتمدة. قد تشمل اختلافات الرسم والضبط والوقف.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (result.changed.isNotEmpty) ...[
              const SizedBox(height: QuranDesign.gutter),
              const Text('عرض النصين والمواضع المقترحة'),
              const Divider(),
            ],
            if (result.changed.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  'لم تظهر اختلافات نصية في الآيات المرتبطة على هذه الصفحة.',
                ),
              ),
            for (final pair in result.changed)
              ReadingTextComparisonTile(pair: pair),
            if (result.unpaired.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  'مواضع في ${baseReading.shortTitle} بلا مقابل متاح: '
                  '${result.unpaired.map((ayah) => ayah.key).join('، ')}',
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class ReadingTextComparisonTile extends StatefulWidget {
  const ReadingTextComparisonTile({
    super.key,
    required this.pair,
    this.compact = false,
    this.initiallyExpanded = false,
  });
  final ExplicitAyahPair pair;
  final bool compact;
  final bool initiallyExpanded;

  @override
  State<ReadingTextComparisonTile> createState() => _ComparisonTileState();
}

class _ComparisonTileState extends State<ReadingTextComparisonTile> {
  Iterable<ProposedWordAlignment>? _changes;

  @override
  void initState() {
    super.initState();
    if (widget.initiallyExpanded) _changes = _compareWords();
  }

  List<ProposedWordAlignment> _compareWords() {
    final pair = widget.pair;
    final comparison = ExplicitAyahPair(
      baseReading: pair.baseReading,
      baseSurah: pair.baseSurah,
      baseAyah: pair.baseAyah,
      baseAyahEnd: pair.baseAyahEnd,
      baseText: QuranRepository.comparableReadingText(pair.baseText),
      targetReading: pair.targetReading,
      targetSurah: pair.targetSurah,
      targetAyah: pair.targetAyah,
      targetAyahEnd: pair.targetAyahEnd,
      targetText: QuranRepository.comparableReadingText(pair.targetText),
    );
    return const ReadingAlignmentEngine()
        .align(comparison)
        .differences
        .toList();
  }

  String _ref(int surah, int first, int? last) =>
      '$surah:$first${last != null && last != first ? '–$last' : ''}';

  @override
  Widget build(BuildContext context) {
    final pair = widget.pair;
    return Column(
      children: [
        ExpansionTile(
          shape: const Border(),
          collapsedShape: const Border(),
          initiallyExpanded: widget.initiallyExpanded,
          tilePadding: widget.compact
              ? const EdgeInsets.symmetric(horizontal: 6)
              : null,
          title: Text(
            '${pair.baseReading.shortTitle} ${_ref(pair.baseSurah, pair.baseAyah, pair.baseAyahEnd)}'
            '\n${pair.targetReading.shortTitle} ${_ref(pair.targetSurah, pair.targetAyah, pair.targetAyahEnd)}',
            style: widget.compact ? const TextStyle(fontSize: 12) : null,
          ),
          onExpansionChanged: (expanded) {
            if (expanded && _changes == null) {
              setState(() => _changes = _compareWords());
            }
          },
          childrenPadding: EdgeInsets.fromLTRB(
            widget.compact ? 6 : 16,
            0,
            widget.compact ? 6 : 16,
            12,
          ),
          expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _TextSample(reading: pair.baseReading, text: pair.baseText),
            _TextSample(reading: pair.targetReading, text: pair.targetText),
            if (_changes case final changes?)
              for (final change in changes) ...[
                const Divider(),
                _TextSample(
                  reading: pair.baseReading,
                  text: change.baseTokens.map((token) => token.text).join(' '),
                ),
                _TextSample(
                  reading: pair.targetReading,
                  text: change.targetTokens
                      .map((token) => token.text)
                      .join(' '),
                ),
              ],
          ],
        ),
        const Divider(height: 1),
      ],
    );
  }
}

class _TextSample extends StatelessWidget {
  const _TextSample({required this.reading, required this.text});
  final QuranReading reading;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          reading.shortTitle,
          style: Theme.of(context).textTheme.labelMedium,
        ),
        Text(
          text.isEmpty ? 'لا نص مقابل في هذا الموضع' : text,
          style: TextStyle(fontSize: 20, fontFamily: reading.unicodeFontFamily),
        ),
      ],
    ),
  );
}

class ReadingSourcesPage extends StatelessWidget {
  const ReadingSourcesPage({super.key, required this.quran});
  final QuranRepository quran;

  @override
  Widget build(BuildContext context) {
    final reviewed = quran.publishedDifferences
        .where((item) => item.isPublished)
        .length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('المصادر وحالة المراجعة'),
        backgroundColor: Colors.transparent,
        flexibleSpace: const QuranGlass(radius: 0, child: SizedBox.expand()),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              reviewed == 0
                  ? 'لا توجد فروق منشورة بمراجعة متخصصة في هذه النسخة.'
                  : 'عدد سجلات الفروق المنشورة: $reviewed',
            ),
            for (final edition in quran.manifest.editions)
              ListTile(
                title: Text(edition.nameAr),
                subtitle: Text(
                  '${edition.source}\n${edition.isPageLayoutCapable ? 'تخطيط صفحات مستقل' : 'نص للمقارنة'} · إصدار ${edition.version}',
                ),
              ),
            if (quran.qiraatVariants case final variants?)
              ListTile(
                title: const Text('فرش القراءات العشر'),
                subtitle: SelectableText(
                  'مصفوفة القراءات في Quran.com (مؤسسة القرآن) عبر Quran Tajweed Engine\n'
                  '${variants.junctures.length} موضع خلاف · نسخة ${variants.revision}',
                ),
              ),
            if (quran.hafsLayout case final layout?)
              ListTile(
                title: const Text('مرجع تخطيط مصحف حفص'),
                subtitle: SelectableText(
                  layout.sourceCommit,
                  textDirection: TextDirection.ltr,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

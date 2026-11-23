part of 'mushaf_reader_page.dart';

/// A margin note: what the chosen riwayah reads at a farsh juncture, or a
/// reviewed published record.
typedef _MarginNote = ({
  String text,
  String hafsText,
  List<String> locations,
  Juncture? juncture,
  ReadingDifference? reviewed,
});

/// Junctures on the page where [riwayah] reads differently from Hafs,
/// according to the farsh. Only words the source places are included.
List<Juncture> _farshDifferencesOnPage(
  QuranRepository quran,
  int page,
  String riwayah,
) {
  final variants = quran.qiraatVariants;
  if (variants == null || riwayah == QiraatVariants.hafs) return const [];
  return [
    for (final juncture in quran.qiraatJuncturesOnPage(page))
      if (juncture.locations.isNotEmpty &&
          variants.differsFromHafs(juncture, riwayah))
        juncture,
  ];
}

Map<int, List<_MarginNote>> _marginNotesByLine(
  QuranRepository quran,
  MushafLayoutPage page,
  String riwayah,
) {
  final variants = quran.qiraatVariants;
  final reviewing = QuranReadingData.fromVariantSlug(riwayah);
  final notes = <_MarginNote>[
    if (reviewing != null)
      for (final difference in quran.publishedDifferencesForPairOnPage(
        QuranReading.hafs,
        reviewing,
        page.number,
      ))
        _reviewedMarginNote(difference),
    if (variants != null)
      for (final juncture in _farshDifferencesOnPage(
        quran,
        page.number,
        riwayah,
      ))
        (
          text: variants.readingFor(juncture, riwayah)!.text,
          hafsText: juncture.word,
          locations: juncture.locations.toList(),
          juncture: juncture,
          reviewed: null,
        ),
  ];
  final notesByLocation = <String, List<_MarginNote>>{};
  for (final note in notes) {
    for (final location in note.locations) {
      (notesByLocation[location] ??= []).add(note);
    }
  }
  return {
    for (final line in page.lines)
      line.number: {
        for (final word in line.words) ...?notesByLocation[word.location],
      }.toList(),
  };
}

_MarginNote _reviewedMarginNote(ReadingDifference difference) {
  final forward = difference.baseReading == QuranReading.hafs;
  final hafs = forward ? difference.baseSpan : difference.targetSpan;
  final variant = forward ? difference.targetSpan : difference.baseSpan;
  return (
    text: variant.text,
    hafsText: hafs.text,
    locations: [
      for (var index = hafs.startWordIndex; index <= hafs.endWordIndex; index++)
        '${hafs.surah}:${hafs.ayah}:$index',
    ],
    juncture: null,
    reviewed: difference,
  );
}

class _MushafMargin extends StatelessWidget {
  const _MushafMargin({
    required this.page,
    required this.riwayah,
    required this.quran,
    required this.metadataHeight,
    required this.lineHeight,
    required this.lineCount,
    required this.footerHeight,
    required this.onRiwayahChanged,
    required this.notesByLine,
    required this.aligned,
  });

  final MushafLayoutPage page;
  final String riwayah;
  final QuranRepository quran;
  final double metadataHeight;
  final double lineHeight;
  final int lineCount;
  final double footerHeight;
  final ValueChanged<String> onRiwayahChanged;
  final Map<int, List<_MarginNote>> notesByLine;
  final bool aligned;

  static const _textComparison = '__text_comparison__';

  ValueKey<String> get marginKey =>
      ValueKey('mushaf-margin-${page.number}-$riwayah');

  String get _riwayahName =>
      quran.qiraatVariants?.riwayah(riwayah)?.name ?? riwayah;

  @override
  Widget build(BuildContext context) {
    final ink = _readingColor(context, _mutedInk, _nightInk);
    if (!aligned) {
      final notes = notesByLine.values.expand((line) => line).toSet().toList();
      return Row(
        key: marginKey,
        children: [
          Expanded(child: _menu(context, ink)),
          if (notes.isNotEmpty)
            Expanded(
              child: Tooltip(
                message: 'عرض الفروق',
                child: TextButton(
                  onPressed: () => _showNotes(context, notes),
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 48),
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                  ),
                  child: Text(
                    MediaQuery.textScalerOf(context).scale(14) > 21
                        ? 'الفروق'
                        : 'عرض الفروق',
                    maxLines: 1,
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ),
            ),
        ],
      );
    }
    return Material(
      key: marginKey,
      color: _readingColor(context, _paper, _nightPaper),
      child: Column(
        children: [
          SizedBox(
            height: metadataHeight,
            width: double.infinity,
            child: _menu(context, ink),
          ),
          SizedBox(
            height: 15 * lineHeight,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var line = 1; line <= lineCount; line++)
                    SizedBox(
                      width: double.infinity,
                      height: lineHeight,
                      child: switch (notesByLine[line]) {
                        final notes? when notes.isNotEmpty => _lineNotes(
                          context,
                          notes,
                          line,
                        ),
                        _ => null,
                      },
                    ),
                ],
              ),
            ),
          ),
          SizedBox(height: footerHeight),
        ],
      ),
    );
  }

  Widget _menu(BuildContext context, Color ink) {
    final variants = quran.qiraatVariants;
    final textTarget = QuranReadingData.fromVariantSlug(riwayah);
    return PopupMenuButton<String>(
      tooltip: 'اختر رواية الهامش',
      onSelected: (value) {
        if (value != _textComparison) {
          onRiwayahChanged(value);
          return;
        }
        Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (_) => ReadingTextComparisonPage(
              quran: quran,
              page: page.number,
              baseReading: QuranReading.hafs,
              targetReading: textTarget!,
            ),
          ),
        );
      },
      itemBuilder: (_) => [
        if (textTarget != null && textTarget != QuranReading.hafs) ...[
          const PopupMenuItem(
            value: _textComparison,
            child: Text('المقارنة النصية'),
          ),
          const PopupMenuDivider(),
        ],
        if (variants != null)
          for (final transmitter in variants.riwayat)
            if (transmitter.riwayah != QiraatVariants.hafs)
              CheckedPopupMenuItem(
                value: transmitter.riwayah,
                checked: transmitter.riwayah == riwayah,
                child: Text(
                  '${transmitter.name} · ${variants.readers[transmitter.reader]?.name ?? ''}',
                ),
              ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                aligned ? _riwayahName : 'هامش $_riwayahName',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: ink,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Icon(Icons.arrow_drop_down, size: 14, color: ink),
          ],
        ),
      ),
    );
  }

  TextStyle _wordStyle(BuildContext context) => TextStyle(
    color: _readingColor(context, _differenceRed, _differenceNightRed),
    fontFamily: QuranReading.hafs.unicodeFontFamily,
    fontSize: 21,
    height: 1.45,
  );

  Widget _lineNotes(BuildContext context, List<_MarginNote> notes, int line) =>
      InkWell(
        key: ValueKey('mushaf-margin-line-${page.number}-$line'),
        onTap: () => _showNotes(context, notes),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              children: [
                Container(
                  width: 7,
                  height: 1,
                  color: _readingColor(context, _rule, _nightRule),
                ),
                const SizedBox(width: 4),
                Text(notes.first.text, style: _wordStyle(context)),
                if (notes.length > 1)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(start: 4),
                    child: Text(
                      '+${notes.length - 1}',
                      textDirection: TextDirection.ltr,
                      style: const TextStyle(fontSize: 10),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );

  void _showNotes(BuildContext context, List<_MarginNote> notes) {
    final variants = quran.qiraatVariants;
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => QuranGlassSheet(
        child: SafeArea(
          top: false,
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'فروق $_riwayahName',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: 'إغلاق الهامش',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              for (final note in notes) ...[
                if (note.reviewed case final reviewed?)
                  _ReviewedDifferenceCard(
                    difference: reviewed,
                    primaryReading: QuranReading.hafs,
                  )
                else if ((note.juncture, variants) case (
                  final juncture?,
                  final variants?,
                ))
                  _JunctureCard(
                    juncture: juncture,
                    variants: variants,
                    riwayah: riwayah,
                  ),
                const SizedBox(height: 10),
              ],
              if (notes.any((note) => note.juncture != null))
                const _FarshSourceNote(),
            ],
          ),
        ),
      ),
    );
  }
}

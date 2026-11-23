part of 'mushaf_reader_page.dart';

final _trailingQuranMarks = RegExp(r'\s+[ۖ-۞٠-٩]');

class _WordGestureScope extends StatefulWidget {
  const _WordGestureScope({
    required this.child,
    this.onWordSelected,
    this.longPressOnly = false,
    this.selectedLocation,
    this.differenceWordLocations = const {},
  });
  final Widget child;
  final ValueChanged<MushafLayoutWord>? onWordSelected;
  final bool longPressOnly;
  final ReaderLocation? selectedLocation;
  final Set<String> differenceWordLocations;

  @override
  State<_WordGestureScope> createState() => _WordGestureScopeState();
}

class _WordGestureScopeState extends State<_WordGestureScope> {
  final _recognizers = <String, GestureRecognizer>{};

  GestureRecognizer recognizer(String key, bool tap, VoidCallback open) {
    final recognizer = _recognizers.putIfAbsent(
      '$key:$tap',
      () => tap ? TapGestureRecognizer() : LongPressGestureRecognizer(),
    );
    if (recognizer is TapGestureRecognizer) recognizer.onTap = open;
    if (recognizer is LongPressGestureRecognizer) recognizer.onLongPress = open;
    return recognizer;
  }

  @override
  void dispose() {
    for (final recognizer in _recognizers.values) {
      recognizer.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

TextSpan _interactiveWordSpan(
  BuildContext context, {
  required QuranRepository quran,
  required QuranReading primaryReading,
  required QuranReading comparisonReading,
  required MushafLayoutWord word,
  String? displayText,
  String suffix = '',
  VoidCallback? onOpen,
  TextStyle? style,
}) {
  final parts = word.location.split(':').map(int.tryParse).toList();
  final highlighted = context
      .findAncestorStateOfType<_WordGestureScopeState>()!
      .widget
      .differenceWordLocations
      .contains(word.location);
  final wordStyle = highlighted
      ? (style ?? const TextStyle()).copyWith(
          color: _readingColor(context, _differenceRed, _differenceNightRed),
        )
      : style;
  final hasLocation = parts.length == 3 && !parts.any((part) => part == null);
  final isMarked =
      hasLocation &&
      (quran.publishedDifferenceForWord(
                baseReading: primaryReading,
                comparisonReading: comparisonReading,
                surah: parts[0]!,
                ayah: parts[1]!,
                wordIndex: parts[2]!,
              ) !=
              null ||
          (primaryReading == QuranReading.hafs &&
              (quran.qiraatVariants?.forWord(word.location).isNotEmpty ??
                  false)));
  void openSheet() {
    if (onOpen != null) {
      onOpen();
      return;
    }
    _showWordComparison(
      context,
      quran: quran,
      primaryReading: primaryReading,
      comparisonReading: comparisonReading,
      word: word,
    );
  }

  final onWordSelected = context
      .findAncestorStateOfType<_WordGestureScopeState>()
      ?.widget
      .onWordSelected;

  // Tap opens the comparison for marked words. Long press only saves the
  // reading position when the reader tracks it, and offers the comparison
  // from a short message instead of covering the page with a sheet.
  void open() {
    onWordSelected?.call(word);
    openSheet();
  }

  void remember() {
    if (onWordSelected == null) {
      openSheet();
      return;
    }
    HapticFeedback.selectionClick();
    onWordSelected(word);
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: const Text('حُفظ موضع القراءة'),
          duration: const Duration(seconds: 4),
          action: SnackBarAction(
            label: 'المقارنة والتلاوة',
            onPressed: openSheet,
          ),
        ),
      );
  }

  final text = displayText ?? word.text;
  final selected = _isSelectedWord(context, word, primaryReading);
  final renderedStyle = selected
      ? (wordStyle ?? const TextStyle()).copyWith(
          backgroundColor: _readingColor(
            context,
            const Color(0x333f7a48),
            const Color(0x6680c79a),
          ),
        )
      : wordStyle;
  final gestures = context.findAncestorStateOfType<_WordGestureScopeState>()!;
  final tap = isMarked && !gestures.widget.longPressOnly;
  final recognizer = gestures.recognizer(
    '${primaryReading.name}:${comparisonReading.name}:${word.location}',
    tap,
    tap ? open : remember,
  );
  final markStart = highlighted
      ? _trailingQuranMarks.firstMatch(text)?.start
      : null;
  if (markStart != null) {
    return TextSpan(
      children: [
        TextSpan(
          text: text.substring(0, markStart),
          style: renderedStyle,
          recognizer: recognizer,
        ),
        TextSpan(text: '${text.substring(markStart)}$suffix', style: style),
      ],
    );
  }
  return TextSpan(
    text: '$text$suffix',
    style: renderedStyle,
    recognizer: recognizer,
  );
}

bool _isSelectedWord(
  BuildContext context,
  MushafLayoutWord word,
  QuranReading reading,
) {
  final selected = context
      .findAncestorStateOfType<_WordGestureScopeState>()
      ?.widget
      .selectedLocation;
  if (selected == null || selected.reading != reading) return false;
  final key = '${selected.surah}:${selected.ayah}';
  return selected.word == null
      ? word.location.startsWith('$key:')
      : word.location == '$key:${selected.word}';
}

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
  final junctures = primaryReading == QuranReading.hafs
      ? quran.qiraatVariants?.forWord(word.location) ?? const <Juncture>[]
      : const <Juncture>[];
  final riwayah = context
      .findAncestorStateOfType<_MushafReaderPageState>()
      ?._marginRiwayah;
  final comparisonAyahs = quran.ayahsCorrespondingTo(
    targetReading: comparisonReading,
    surah: surah,
    ayah: ayah,
    sourceReading: primaryReading,
  );
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => QuranGlassSheet(
      child: _WordComparisonSheet(
        primaryReading: primaryReading,
        comparisonReading: comparisonReading,
        word: word,
        difference: difference,
        junctures: junctures,
        riwayah: riwayah ?? comparisonReading.variantSlug,
        comparisonAyahs: comparisonAyahs,
        quran: quran,
      ),
    ),
  );
}

class _WordComparisonSheet extends StatelessWidget {
  const _WordComparisonSheet({
    required this.primaryReading,
    required this.comparisonReading,
    required this.word,
    required this.difference,
    required this.junctures,
    required this.riwayah,
    required this.comparisonAyahs,
    this.quran,
  });

  final QuranRepository? quran;

  final QuranReading primaryReading;
  final QuranReading comparisonReading;
  final MushafLayoutWord word;
  final ReadingDifference? difference;
  final List<Juncture> junctures;
  final String riwayah;
  final List<Ayah> comparisonAyahs;

  String? _ayahText() {
    final parts = word.location.split(':');
    if (parts.length < 2) return null;
    final key = '${parts[0]}:${parts[1]}';
    final ayah = primaryReading == QuranReading.hafs
        ? quran?.hafsByKey[key]
        : quran?.ayahForReading(primaryReading, key);
    if (ayah == null) return null;
    final reference = '${ayah.surahName} ${ayah.number}';
    final text = primaryReading == QuranReading.hafs
        ? quran?.hafsLayoutAyahText(key) ?? ayah.comparisonText
        : ayah.comparisonText;
    return '${text.trim()}\n﴿$reference · ${primaryReading.title}﴾';
  }

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
    final characterEdits = comparisonText == null
        ? const <CharacterEdit>[]
        : const ReadingAlignmentEngine().compareCharacters(
            primaryText,
            comparisonText,
          );
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'موضع ${word.location}',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              children: [
                if (primaryReading == QuranReading.hafs)
                  TextButton.icon(
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (_) => HafsAyahAudioDialog(
                        surah: int.parse(word.location.split(':')[0]),
                        ayah: int.parse(word.location.split(':')[1]),
                        hasAyah: quran == null
                            ? null
                            : (surah, ayah) =>
                                  quran!.hafsByKey.containsKey('$surah:$ayah'),
                      ),
                    ),
                    icon: const Icon(Icons.play_circle_outline),
                    label: const Text('استمع للآية · حفص'),
                  ),
                if (_ayahText() case final text?)
                  TextButton.icon(
                    onPressed: () async {
                      final messenger = ScaffoldMessenger.maybeOf(context);
                      await Clipboard.setData(ClipboardData(text: text));
                      messenger?.showSnackBar(
                        const SnackBar(content: Text('نُسخت الآية')),
                      );
                    },
                    icon: const Icon(Icons.copy_rounded),
                    label: const Text('نسخ الآية'),
                  ),
              ],
            ),
            _ReadingWordTile(
              reading: primaryReading,
              label: primaryReading.title,
              text: primaryText,
              characterEdits: characterEdits,
              showBaseEdits: true,
            ),
            const SizedBox(height: 8),
            if (junctures.isNotEmpty && quran?.qiraatVariants != null) ...[
              Text(
                'القراءات في هذا الموضع',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              for (final juncture in junctures) ...[
                _JunctureCard(
                  juncture: juncture,
                  variants: quran!.qiraatVariants!,
                  riwayah: riwayah,
                ),
                const SizedBox(height: 8),
              ],
              const _FarshSourceNote(),
              const SizedBox(height: 12),
            ],
            if (comparisonText != null)
              _ReadingWordTile(
                reading: comparisonReading,
                label: comparisonReading.title,
                text: comparisonText,
                accent: true,
                characterEdits: characterEdits,
              )
            else ...[
              if (junctures.isEmpty)
                Text(
                  primaryReading == QuranReading.hafs
                      ? 'لا يذكر الفرش خلافًا في هذه الكلمة.'
                      : 'الفرش مرتبط بكلمات مصحف حفص؛ اعرض حفص لرؤية القراءات.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              if (comparisonAyahs.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'نص الآية في قراءة ${comparisonReading.shortTitle} للاطلاع فقط (ليس محاذاة كلمة بكلمة):',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 4),
                for (final comparisonAyah in comparisonAyahs)
                  Text(
                    '${comparisonAyah.surah}:${comparisonAyah.number}  ${comparisonAyah.comparisonText}',
                    textDirection: TextDirection.rtl,
                    style: TextStyle(
                      fontFamily: comparisonReading.unicodeFontFamily,
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
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ReadingWordTile extends StatelessWidget {
  const _ReadingWordTile({
    required this.reading,
    required this.label,
    required this.text,
    this.accent = false,
    this.characterEdits = const [],
    this.showBaseEdits = false,
  });
  final QuranReading reading;
  final String label;
  final String text;
  final bool accent;
  final List<CharacterEdit> characterEdits;
  final bool showBaseEdits;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: accent
          ? Theme.of(context).colorScheme.primaryContainer
          : Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
    ),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 4),
          Text.rich(
            characterEdits.isEmpty
                ? TextSpan(text: text)
                : TextSpan(
                    children: [
                      for (final edit in characterEdits)
                        if ((showBaseEdits ? edit.baseText : edit.targetText)
                            case final value?)
                          TextSpan(
                            text: value,
                            style: edit.kind == CharacterEditKind.keep
                                ? null
                                : TextStyle(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onErrorContainer,
                                    backgroundColor: Theme.of(context)
                                        .colorScheme
                                        .errorContainer,
                                  ),
                          ),
                    ],
                  ),
            textDirection: TextDirection.rtl,
            style: TextStyle(
              fontFamily: reading.unicodeFontFamily,
              fontSize: 26,
            ),
          ),
        ],
      ),
    ),
  );
}

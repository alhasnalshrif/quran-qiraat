part of 'mushaf_reader_page.dart';

const _farshSourceNote =
    'المصدر: مصفوفة القراءات في Quran.com (مؤسسة القرآن) عبر Quran Tajweed Engine.';

/// One farsh juncture as the source gives it: every form with who reads it.
/// Hafs' form and the selected riwayah's form are labelled, nothing else is
/// inferred.
class _JunctureCard extends StatelessWidget {
  const _JunctureCard({
    required this.juncture,
    required this.variants,
    this.riwayah,
    this.compact = false,
  });

  final Juncture juncture;
  final QiraatVariants variants;
  final String? riwayah;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final hafsReading = variants.readingFor(juncture, QiraatVariants.hafs);
    final selected = riwayah == null
        ? null
        : variants.readingFor(juncture, riwayah!);
    final selectedName = riwayah == null
        ? null
        : variants.riwayah(riwayah!)?.name;
    final place = juncture.segments.map((segment) => segment.ayah).join('، ');
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Padding(
        padding: EdgeInsets.all(compact ? 8 : 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'الآية $place',
              style: theme.textTheme.labelMedium?.copyWith(
                color: colors.primary,
              ),
            ),
            if (juncture.editionNote case final note?)
              Text(note, style: theme.textTheme.bodySmall),
            const SizedBox(height: 6),
            for (final reading in juncture.readings)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color:
                        identical(reading, selected) &&
                            !identical(reading, hafsReading)
                        ? colors.primaryContainer
                        : null,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          reading.text,
                          textDirection: TextDirection.rtl,
                          style: TextStyle(
                            fontFamily: QuranReading.hafs.unicodeFontFamily,
                            fontSize: compact ? 20 : 24,
                            height: 1.6,
                          ),
                        ),
                        Text(
                          [
                            variants.attribution(reading),
                            if (identical(reading, hafsReading)) '· قراءة حفص',
                            if (selectedName != null &&
                                identical(reading, selected) &&
                                !identical(reading, hafsReading))
                              '· قراءة $selectedName',
                          ].join(' '),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _FarshSourceNote extends StatelessWidget {
  const _FarshSourceNote();

  @override
  Widget build(BuildContext context) => Text(
    _farshSourceNote,
    style: Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
  );
}

class _EditionSourceNote extends StatelessWidget {
  const _EditionSourceNote();

  @override
  Widget build(BuildContext context) => Text(
    'المصدر: علامات طبعة شعبة في Quran Tajweed Engine.',
    style: Theme.of(context).textTheme.bodySmall,
  );
}

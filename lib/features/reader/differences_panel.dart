part of 'mushaf_reader_page.dart';

class DifferencesDrawer extends StatelessWidget {
  const DifferencesDrawer({
    super.key,
    required this.page,
    required this.baseReading,
    required this.comparisonReading,
    required this.quran,
    this.onPlacementChanged,
  });

  final int page;
  final QuranReading baseReading;
  final QuranReading comparisonReading;
  final QuranRepository quran;
  final ValueChanged<DifferencesPlacement>? onPlacementChanged;

  @override
  Widget build(BuildContext context) => Drawer(
    width: math.min(MediaQuery.sizeOf(context).width * .9, 420),
    backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
    child: SafeArea(
      child: DifferencesPanel(
        page: page,
        baseReading: baseReading,
        comparisonReading: comparisonReading,
        quran: quran,
        onClose: () => Navigator.pop(context),
        onPlacementChanged: onPlacementChanged,
      ),
    ),
  );
}

class DifferencesPanel extends StatelessWidget {
  const DifferencesPanel({
    super.key,
    required this.page,
    required this.baseReading,
    required this.comparisonReading,
    required this.quran,
    required this.onClose,
    this.onPlacementChanged,
    this.placement = DifferencesPlacement.hidden,
    this.compact = false,
    this.narrow = false,
  });

  final int page;
  final QuranReading baseReading;
  final QuranReading comparisonReading;
  final QuranRepository quran;
  final VoidCallback onClose;
  final ValueChanged<DifferencesPlacement>? onPlacementChanged;
  final DifferencesPlacement placement;
  final bool compact;
  final bool narrow;

  @override
  Widget build(BuildContext context) {
    final riwayah = baseReading == QuranReading.hafs
        ? comparisonReading.variantSlug
        : baseReading.variantSlug;
    final variants = quran.qiraatVariants;
    final junctures = quran.qiraatJuncturesOnPage(page);
    final differing = variants == null
        ? const <Juncture>[]
        : [
            for (final juncture in junctures)
              if (variants.differsFromHafs(juncture, riwayah)) juncture,
          ];
    final others = [
      for (final juncture in junctures)
        if (juncture.editionNote == null && !differing.contains(juncture))
          juncture,
    ];
    final riwayahName = variants?.riwayah(riwayah)?.name ?? riwayah;
    final differences = quran.publishedDifferencesForPairOnPage(
      baseReading,
      comparisonReading,
      page,
    );
    final compareButton = TextButton(
      onPressed: () => Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => ReadingTextComparisonPage(
            quran: quran,
            page: page,
            baseReading: baseReading,
            targetReading: comparisonReading,
          ),
        ),
      ),
      child: const Text('قارن نصوص الآيات', textAlign: TextAlign.center),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: compact
              ? EdgeInsets.fromLTRB(narrow ? 4 : 12, 4, 4, 4)
              : const EdgeInsets.fromLTRB(18, 14, 18, 12),
          child: narrow
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'اختلافات الصفحة $page',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      '${baseReading.shortTitle} × ${comparisonReading.shortTitle}',
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          tooltip: 'إغلاق الاختلافات',
                          onPressed: onClose,
                          icon: const Icon(Iconsax.close_circle),
                        ),
                        if (onPlacementChanged != null) _placementMenu(),
                      ],
                    ),
                  ],
                )
              : Row(
                  children: [
                    IconButton(
                      tooltip: 'إغلاق الاختلافات',
                      onPressed: onClose,
                      icon: const Icon(Iconsax.close_circle),
                    ),
                    SizedBox(width: compact ? 0 : 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'اختلافات الصفحة $page',
                            style: TextStyle(
                              fontSize: compact ? 15 : 20,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (compact)
                            Text(
                              '${baseReading.shortTitle} × ${comparisonReading.shortTitle}',
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (compact && onPlacementChanged != null) _placementMenu(),
                  ],
                ),
        ),
        if (!compact)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Text(
              '${baseReading.shortTitle} × ${comparisonReading.shortTitle}',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        if (!compact) const SizedBox(height: 12),
        if (!compact && onPlacementChanged != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Wrap(
              spacing: 8,
              children: [
                TextButton.icon(
                  onPressed: () =>
                      onPlacementChanged!(DifferencesPlacement.side),
                  icon: const Icon(Iconsax.sidebar_right),
                  label: const Text('على الجانب'),
                ),
                TextButton.icon(
                  onPressed: () =>
                      onPlacementChanged!(DifferencesPlacement.bottom),
                  icon: const Icon(Iconsax.sidebar_bottom),
                  label: const Text('أسفل الصفحة'),
                ),
                if (baseReading == QuranReading.hafs)
                  TextButton.icon(
                    onPressed: () =>
                        onPlacementChanged!(DifferencesPlacement.margin),
                    icon: const Icon(Icons.vertical_split_outlined),
                    label: const Text('في الهامش'),
                  ),
              ],
            ),
          ),
        Expanded(
          child: ListView(
            key: ValueKey(
              'differences-list-$page-${baseReading.name}-${comparisonReading.name}',
            ),
            padding: EdgeInsets.fromLTRB(
              narrow ? 6 : 18,
              4,
              narrow ? 6 : 18,
              24,
            ),
            children: [
              if (differing.isNotEmpty) ...[
                _DifferenceSectionTitle(
                  title: 'ما يخالف فيه $riwayahName حفصًا',
                  color: _green,
                ),
                for (final juncture in differing) ...[
                  _JunctureCard(
                    juncture: juncture,
                    variants: variants!,
                    riwayah: riwayah,
                    compact: narrow,
                  ),
                  const SizedBox(height: 10),
                ],
              ],
              if (others.isNotEmpty) ...[
                const _DifferenceSectionTitle(
                  title: 'خلاف بقية القراء في الصفحة',
                  color: _green,
                ),
                for (final juncture in others) ...[
                  _JunctureCard(
                    juncture: juncture,
                    variants: variants!,
                    riwayah: riwayah,
                    compact: narrow,
                  ),
                  const SizedBox(height: 10),
                ],
              ],
              if (differing.isEmpty && others.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'لا يذكر الفرش مواضع خلاف في هذه الصفحة.',
                    textAlign: TextAlign.center,
                  ),
                ),
              if (differing.any((juncture) => juncture.editionNote != null))
                const _EditionSourceNote(),
              if ([
                ...differing,
                ...others,
              ].any((juncture) => juncture.editionNote == null))
                const _FarshSourceNote(),
              if (differences.isNotEmpty) ...[
                const _DifferenceSectionTitle(
                  title: 'فروق معتمدة',
                  color: _green,
                ),
                for (final difference in differences) ...[
                  _ReviewedDifferenceCard(
                    difference: difference,
                    primaryReading: baseReading,
                    compact: narrow,
                  ),
                  const SizedBox(height: 10),
                ],
              ],
              const SizedBox(height: 8),
              compareButton,
            ],
          ),
        ),
      ],
    );
  }

  Widget _placementMenu() => PopupMenuButton<DifferencesPlacement>(
    key: const ValueKey('differences-placement-menu'),
    tooltip: 'موضع الاختلافات',
    initialValue: placement,
    onSelected: onPlacementChanged,
    icon: const Icon(Iconsax.setting_4),
    itemBuilder: (_) => const [
      PopupMenuItem(
        value: DifferencesPlacement.side,
        child: Text('على الجانب'),
      ),
      PopupMenuItem(
        value: DifferencesPlacement.bottom,
        child: Text('أسفل الصفحة'),
      ),
    ],
  );
}

class _DifferenceSectionTitle extends StatelessWidget {
  const _DifferenceSectionTitle({required this.title, required this.color});

  final String title;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      title,
      style: TextStyle(
        color: _readingColor(
          context,
          color,
          Theme.of(context).colorScheme.primary,
        ),
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

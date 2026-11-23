part of 'mushaf_reader_page.dart';

class ReaderTopBar extends StatelessWidget {
  const ReaderTopBar({
    super.key,
    required this.onOpenLibrary,
    required this.onSettings,
    required this.onZoom,
    this.onBookmark,
    this.selectedLocationLabel,
  });

  final VoidCallback onOpenLibrary;
  final VoidCallback onSettings;
  final VoidCallback onZoom;
  final VoidCallback? onBookmark;
  final String? selectedLocationLabel;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      QuranGlass(
        native: true,
        floating: true,
        child: IconButton(
          tooltip: 'الفهرس والبحث والعلامات',
          onPressed: onOpenLibrary,
          icon: const Icon(Icons.format_list_bulleted_rounded),
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: selectedLocationLabel == null
            ? const SizedBox.shrink()
            : Center(
                child: QuranGlass(
                  native: true,
                  floating: true,
                  child: Tooltip(
                    message: 'العلامات والملاحظات',
                    child: TextButton(
                      onPressed: onBookmark,
                      style: TextButton.styleFrom(
                        minimumSize: const Size(0, QuranDesign.control),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                      ),
                      child: Text(
                        selectedLocationLabel!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ),
              ),
      ),
      const SizedBox(width: 8),
      QuranGlass(
        native: true,
        floating: true,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'تكبير صفحة القراءة',
              onPressed: onZoom,
              icon: const Icon(Icons.zoom_in_rounded),
            ),
            IconButton(
              tooltip: 'إعدادات القراءة',
              onPressed: onSettings,
              icon: const Icon(Icons.settings_outlined),
            ),
          ],
        ),
      ),
    ],
  );
}

class _ReaderSettings extends StatefulWidget {
  const _ReaderSettings({
    required this.appearance,
    required this.onAppearanceChanged,
    required this.onMargin,
    this.keepAwake = false,
    this.onKeepAwakeChanged,
    this.flowFontSize = 27,
    this.onFlowFontSizeChanged,
  });

  final ThemeMode appearance;
  final ValueChanged<ThemeMode> onAppearanceChanged;
  final VoidCallback onMargin;
  final bool keepAwake;
  final ValueChanged<bool>? onKeepAwakeChanged;
  final double flowFontSize;
  final ValueChanged<double>? onFlowFontSizeChanged;

  @override
  State<_ReaderSettings> createState() => _ReaderSettingsState();
}

class _ReaderSettingsState extends State<_ReaderSettings> {
  late ThemeMode _appearance = widget.appearance;
  late bool _keepAwake = widget.keepAwake;
  late double _flowFontSize = widget.flowFontSize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'إعدادات القراءة',
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: 'إغلاق الإعدادات',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('المظهر', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            QuranChoiceGroup(
              options: const [
                (ThemeMode.light, 'نهاري'),
                (ThemeMode.dark, 'ليلي'),
                (ThemeMode.system, 'حسب الجهاز'),
              ],
              selected: _appearance,
              onSelected: (mode) {
                setState(() => _appearance = mode);
                widget.onAppearanceChanged(mode);
              },
            ),
            const SizedBox(height: 16),
            const Divider(height: 1),
            if (widget.onKeepAwakeChanged case final onChanged?)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: const Icon(Icons.light_mode_outlined),
                title: const Text('إبقاء الشاشة مضاءة أثناء القراءة'),
                value: _keepAwake,
                onChanged: (value) {
                  setState(() => _keepAwake = value);
                  onChanged(value);
                },
              ),
            if (widget.onFlowFontSizeChanged case final onChanged?) ...[
              const SizedBox(height: 8),
              Text('حجم نص شعبة وقالون', style: theme.textTheme.titleMedium),
              Text(
                'صفحة حفص تلتزم بتخطيط الأسطر؛ استخدم التكبير لتكبيرها.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              Slider(
                value: _flowFontSize,
                min: 20,
                max: 40,
                divisions: 10,
                label: _flowFontSize.round().toString(),
                onChanged: (value) {
                  setState(() => _flowFontSize = value);
                  onChanged(value);
                },
              ),
              const Divider(height: 1),
            ],
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.vertical_split_outlined),
              title: const Text('مصحف بالهامش'),
              trailing: const Icon(Icons.chevron_left_rounded),
              onTap: widget.onMargin,
            ),
          ],
        ),
      ),
    );
  }
}

class _PageZoom extends StatefulWidget {
  const _PageZoom({
    required this.page,
    required this.night,
    required this.child,
  });
  final int page;
  final bool night;
  final Widget child;

  @override
  State<_PageZoom> createState() => _PageZoomState();
}

class _PageZoomState extends State<_PageZoom> {
  final _controller = TransformationController();

  Size _viewport = Size.zero;

  // Zoom around the middle of the screen so the visible passage stays put.
  void _zoom(double delta) {
    final current = _controller.value.getMaxScaleOnAxis();
    final next = (current + delta).clamp(1.0, 4.0);
    if (next == current) return;
    final focal = _viewport.center(Offset.zero);
    final scene = _controller.toScene(focal);
    final matrix = Matrix4.identity()
      ..translateByDouble(focal.dx, focal.dy, 0, 1)
      ..scaleByDouble(next, next, 1, 1)
      ..translateByDouble(-scene.dx, -scene.dy, 0, 1);
    if (next == 1) matrix.setIdentity();
    _controller.value = matrix;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: widget.night ? _nightPaper : _paper,
    appBar: AppBar(
      backgroundColor: widget.night ? _nightPaper : _paper,
      foregroundColor: widget.night ? _nightInk : _ink,
      systemOverlayStyle: widget.night
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
      title: Text('تكبير صفحة ${widget.page}'),
      actions: [
        IconButton(
          tooltip: 'تصغير',
          onPressed: () => _zoom(-.5),
          icon: const Icon(Icons.remove),
        ),
        IconButton(
          tooltip: 'تكبير',
          onPressed: () => _zoom(.5),
          icon: const Icon(Icons.add),
        ),
      ],
    ),
    body: SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          _viewport = constraints.biggest;
          return InteractiveViewer(
            transformationController: _controller,
            maxScale: 4,
            child: widget.child,
          );
        },
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
    this.differencesVisible = false,
    this.restoresMargin = false,
  });

  final int page;
  final QuranReading primaryReading;
  final QuranReading comparisonReading;
  final VoidCallback onOpenDifferences;
  final VoidCallback onSelectReading;
  final VoidCallback onGoToPage;
  final bool differencesVisible;
  final bool restoresMargin;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final pair =
        '${primaryReading.shortTitle} × ${comparisonReading.shortTitle}';
    final showSideLabels = MediaQuery.textScalerOf(context).scale(12) <= 18;
    return QuranGlass(
      native: true,
      floating: true,
      radius: 29,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
        child: Row(
          children: [
            Expanded(
              child: _ControlButton(
                icon: Icons.compare_arrows_rounded,
                label: differencesVisible
                    ? 'إخفاء الفروق'
                    : restoresMargin
                    ? 'إظهار الهامش'
                    : 'الفروق',
                tooltip: differencesVisible
                    ? 'إخفاء الفروق'
                    : restoresMargin
                    ? 'إظهار الهامش'
                    : 'فروق الصفحة',
                color: differencesVisible ? colors.primary : colors.onSurface,
                showLabel: showSideLabels,
                onPressed: onOpenDifferences,
              ),
            ),
            Expanded(
              flex: 2,
              child: TextButton(
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, QuranDesign.control),
                  foregroundColor: colors.onSurface,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 6,
                  ),
                ),
                onPressed: onSelectReading,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('القراءتان', style: TextStyle(fontSize: 12)),
                    Text(
                      pair,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: _ControlButton(
                icon: Icons.auto_stories_outlined,
                label: 'صفحة $page',
                tooltip: 'انتقل إلى صفحة',
                color: colors.onSurface,
                showLabel: showSideLabels,
                onPressed: onGoToPage,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.color,
    required this.showLabel,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final String tooltip;
  final Color color;
  final bool showLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: color,
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20),
          if (showLabel)
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12),
            ),
        ],
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final options = [
      for (final reading in QuranReading.values) (reading, reading.title),
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              QuranDesign.gutter,
              0,
              QuranDesign.gutter,
              QuranDesign.section,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'اختر قراءتين للمقارنة',
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: QuranDesign.section),
                Text('النص المعروض', style: theme.textTheme.titleMedium),
                const SizedBox(height: QuranDesign.gap),
                QuranChoiceGroup(
                  options: options,
                  selected: _primary,
                  onSelected: _setPrimary,
                ),
                const SizedBox(height: QuranDesign.gap),
                Text(
                  _primary == QuranReading.hafs
                      ? 'تخطيط صفحات المصحف'
                      : 'عرض نصي بحسب مواضع حفص',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: QuranDesign.section),
                Text('رواية المقارنة', style: theme.textTheme.titleMedium),
                const SizedBox(height: QuranDesign.gap),
                QuranChoiceGroup(
                  options: options,
                  selected: _comparison,
                  onSelected: _setComparison,
                ),
              ],
            ),
          ),
        ),
        SafeArea(
          top: false,
          minimum: const EdgeInsets.fromLTRB(
            QuranDesign.gutter,
            0,
            QuranDesign.gutter,
            QuranDesign.gutter,
          ),
          child: FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, QuranDesign.control),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(QuranDesign.controlRadius),
              ),
            ),
            onPressed: () => Navigator.pop(
              context,
              _ReadingPair(primary: _primary, comparison: _comparison),
            ),
            child: const Text('تأكيد المقارنة'),
          ),
        ),
      ],
    );
  }
}

import 'dart:math' as math;

import 'package:flutter/gestures.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:quran_qiraat/domain/models/ayah.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../app/quran_theme.dart';
import '../../data/quran_repository.dart';
import '../../domain/models/reading_alignment.dart';
import '../../domain/models/margin_riwayah.dart';
import '../../domain/models/qiraat_variants.dart';
import '../../domain/models/mushaf_layout.dart';
import '../../domain/services/reading_alignment_engine.dart';
import '../../domain/models/reading_difference.dart';
import 'page_input.dart';
import 'reader_library.dart';
import 'reading_text_comparison_page.dart';
import 'hafs_ayah_audio.dart';
import 'riwayah_picker.dart';

part 'reviewed_difference_card.dart';
part 'reader_controls.dart';
part 'word_comparison.dart';
part 'differences_panel.dart';
part 'mushaf_margin.dart';
part 'juncture_card.dart';

const _green = Color(0xff2e624b);
const _rule = Color(0xffddd7c8);
const _mutedInk = Color(0xff665e50);
const _differenceRed = Color(0xffad2626);
const _differenceNightRed = Color(0xffff8a80);
const _paper = Color(0xfffcfaf3);
const _ink = Color(0xff191814);
const _nightPaper = Colors.black;
const _nightRule = Color(0xff686868);
const _nightInk = Color(0xffcdcac2);
const readerAppearancePreference = 'reader_appearance';

ThemeMode readerThemeMode(SharedPreferences preferences) {
  return switch (preferences.getString(readerAppearancePreference)) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    'system' => ThemeMode.system,
    _ => switch (preferences.getBool('night_reading')) {
      true => ThemeMode.dark,
      false => ThemeMode.light,
      null => ThemeMode.system,
    },
  };
}

String _readerDigits(int number) => number
    .toString()
    .split('')
    .map((digit) => '٠١٢٣٤٥٦٧٨٩'[int.parse(digit)])
    .join();

Color _readingColor(BuildContext context, Color day, Color night) =>
    Theme.of(context).brightness == Brightness.dark ? night : day;

enum DifferencesPlacement { hidden, side, bottom, margin }

class MushafReaderPage extends StatefulWidget {
  const MushafReaderPage({
    super.key,
    required this.preferences,
    required this.quran,
    this.onAppearanceChanged,
  });

  final SharedPreferences preferences;
  final QuranRepository quran;
  final ValueChanged<ThemeMode>? onAppearanceChanged;

  @override
  State<MushafReaderPage> createState() => _MushafReaderPageState();
}

class _MushafReaderPageState extends State<MushafReaderPage> {
  static const _pageCount = 604;
  static const _lastPageKey = 'last_page';
  static const _primaryReadingKey = 'primary_reading';
  static const _comparisonReadingKey = 'comparison_reading';
  static const _differencesPlacementKey = 'differences_placement';
  static const _restoreMarginKey = 'restore_margin_on_open';
  static const _keepAwakeKey = 'keep_screen_awake';
  static const _flowFontSizeKey = 'flow_font_size';
  static const _hintSeenKey = 'reader_hint_seen';
  static const _marginRiwayahKey = 'margin_riwayah';

  final _scaffoldKey = GlobalKey<ScaffoldState>();
  late final PageController _pageController;
  late int _page;
  late QuranReading _primaryReading;
  late QuranReading _comparisonReading;
  late DifferencesPlacement _differencesPlacement;
  late bool _restoreMargin;
  bool _chromeVisible = false;
  late bool _keepAwake;
  late double _flowFontSize;
  late bool _showHint;
  late String _marginRiwayah;
  late ThemeMode _appearance;

  bool get _nightReading => switch (_appearance) {
    ThemeMode.dark => true,
    ThemeMode.light => false,
    ThemeMode.system =>
      MediaQuery.platformBrightnessOf(context) == Brightness.dark,
  };
  late final QuranNavigationIndex _navigation;
  late final ReaderLibraryStore _library;
  ReaderLocation? _selectedLocation;
  List<Ayah> _hizbStarts = const [];

  int? _hizbForPage(int page) {
    final first = widget.quran.page(page).firstOrNull;
    if (first == null || _hizbStarts.isEmpty) return null;
    var hizb = 0;
    for (final start in _hizbStarts) {
      if (start.surah < first.surah ||
          (start.surah == first.surah && start.number <= first.number)) {
        hizb++;
      }
    }
    return hizb == 0 ? null : hizb;
  }

  @override
  void initState() {
    super.initState();
    _page = (widget.preferences.getInt(_lastPageKey) ?? 1).clamp(1, _pageCount);
    _primaryReading = _savedReading(
      widget.preferences.getString(_primaryReadingKey),
    );
    _differencesPlacement = DifferencesPlacement.values.firstWhere(
      (placement) =>
          placement.name ==
          widget.preferences.getString(_differencesPlacementKey),
      orElse: () => _primaryReading == QuranReading.hafs
          ? DifferencesPlacement.margin
          : DifferencesPlacement.hidden,
    );
    _restoreMargin = widget.preferences.getBool(_restoreMarginKey) ?? false;
    _keepAwake = widget.preferences.getBool(_keepAwakeKey) ?? false;
    _flowFontSize = (widget.preferences.getDouble(_flowFontSizeKey) ?? 27)
        .clamp(20, 40)
        .toDouble();
    _showHint = !(widget.preferences.getBool(_hintSeenKey) ?? false);
    if (_keepAwake) _applyWakelock(true);
    _comparisonReading = _savedReading(
      widget.preferences.getString(_comparisonReadingKey),
    );
    if (_differencesPlacement == DifferencesPlacement.margin) {
      _primaryReading = QuranReading.hafs;
    }
    if (_comparisonReading == _primaryReading) {
      _comparisonReading = _primaryReading == QuranReading.hafs
          ? QuranReading.shubah
          : QuranReading.hafs;
    }
    final savedRiwayah = widget.preferences.getString(_marginRiwayahKey);
    _marginRiwayah =
        savedRiwayah != null &&
            widget.quran.qiraatVariants?.riwayah(savedRiwayah) != null &&
            savedRiwayah != QiraatVariants.hafs
        ? savedRiwayah
        : (_comparisonReading == QuranReading.hafs
                  ? QuranReading.shubah
                  : _comparisonReading)
              .variantSlug;
    _pageController = PageController(initialPage: _page - 1);
    _navigation = QuranNavigationIndex(widget.quran);
    _library = ReaderLibraryStore(widget.preferences);
    _appearance = readerThemeMode(widget.preferences);
    _navigation.hizbs().then((starts) {
      if (mounted) setState(() => _hizbStarts = starts);
    }, onError: (_) {});
    final saved = _library.resume;
    if (saved != null &&
        saved.page == _page &&
        _primaryReading == saved.reading &&
        _navigation.valid(saved)) {
      _selectedLocation = saved;
    }
  }

  QuranReading _savedReading(String? value) => QuranReading.values.firstWhere(
    (reading) => reading.name == value,
    orElse: () => QuranReading.hafs,
  );

  static Future<void> _applyWakelock(bool enabled) async {
    try {
      await WakelockPlus.toggle(enable: enabled);
    } catch (_) {
      // Platforms without a wakelock implementation simply keep their default.
    }
  }

  void _setKeepAwake(bool value) {
    setState(() => _keepAwake = value);
    widget.preferences.setBool(_keepAwakeKey, value);
    _applyWakelock(value);
  }

  void _setFlowFontSize(double value) {
    setState(() => _flowFontSize = value);
    widget.preferences.setDouble(_flowFontSizeKey, value);
  }

  @override
  void dispose() {
    if (_keepAwake) _applyWakelock(false);
    _library.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _onPageChanged(int index) {
    setState(() {
      _page = index + 1;
      if (_selectedLocation?.page != _page) _selectedLocation = null;
    });
    widget.preferences.setInt(_lastPageKey, _page);
  }

  Future<void> _remember(ReaderLocation location) async {
    setState(() => _selectedLocation = location);
    try {
      await _library.setResume(location);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('تعذر حفظ موضع القراءة')));
      }
    }
  }

  void _selectWord(MushafLayoutWord word) {
    if (_primaryReading != QuranReading.hafs) return;
    final parts = word.location.split(':').map(int.parse).toList();
    final location = _navigation.locate(parts[0], parts[1], word: parts[2]);
    if (location != null) _remember(location);
  }

  Future<void> _openLibrary({bool bookmarks = false}) async {
    final firstInReading = widget.quran
        .pageForReading(_primaryReading, _page)
        .firstOrNull;
    final current =
        _selectedLocation ??
        (firstInReading == null
            ? null
            : _navigation.locateInReading(_primaryReading, firstInReading)) ??
        _navigation.firstOnPage(_page);
    if (current == null) return;
    final location = await Navigator.of(context).push<ReaderLocation>(
      MaterialPageRoute(
        builder: (_) => ReaderLibraryPage(
          index: _navigation,
          store: _library,
          current: current,
          searchReading: _primaryReading,
          initialTab: bookmarks ? 2 : 0,
        ),
      ),
    );
    if (!mounted || location == null) return;
    if (location.reading != QuranReading.hafs &&
        _differencesPlacement == DifferencesPlacement.margin) {
      _setDifferencesPlacement(DifferencesPlacement.hidden);
    }
    setState(() {
      _primaryReading = location.reading;
      if (_comparisonReading == _primaryReading) {
        _comparisonReading = _primaryReading == QuranReading.hafs
            ? QuranReading.shubah
            : QuranReading.hafs;
      }
    });
    await widget.preferences.setString(
      _primaryReadingKey,
      _primaryReading.name,
    );
    await widget.preferences.setString(
      _comparisonReadingKey,
      _comparisonReading.name,
    );
    if (!mounted) return;
    _pageController.jumpToPage(location.page - 1);
    await _remember(location);
  }

  void _toggleChrome() {
    setState(() {
      _chromeVisible = !_chromeVisible;
      _showHint = false;
    });
    widget.preferences.setBool(_hintSeenKey, true);
  }

  void _setAppearance(ThemeMode mode) {
    setState(() => _appearance = mode);
    widget.onAppearanceChanged?.call(mode);
    widget.preferences.setString(readerAppearancePreference, mode.name);
  }

  Future<void> _openSettings() => showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => QuranGlassSheet(
      child: _ReaderSettings(
        appearance: _appearance,
        onAppearanceChanged: _setAppearance,
        keepAwake: _keepAwake,
        onKeepAwakeChanged: _setKeepAwake,
        flowFontSize: _flowFontSize,
        onFlowFontSizeChanged: _setFlowFontSize,
        onMargin: () {
          Navigator.of(sheetContext).pop();
          _setDifferencesPlacement(DifferencesPlacement.margin);
        },
      ),
    ),
  );

  void _openZoom() {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => _PageZoom(
          page: _page,
          night: _nightReading,
          child: QuranTextPage(
            page: _page,
            hizb: _hizbForPage(_page),
            flowFontSize: _flowFontSize,
            reading: _primaryReading,
            comparisonReading: _comparisonReading,
            quran: widget.quran,
            night: _nightReading,
            selectedLocation: _selectedLocation,
            differenceWordLocations: _marginHighlights(_page),
            marginRiwayah: _marginRiwayah,
          ),
        ),
      ),
    );
  }

  Set<String> _marginHighlights(int page) {
    if (_differencesPlacement != DifferencesPlacement.margin) return const {};
    // Words are colored only from published sources: the farsh of the ten
    // readers, and any reviewed record in the published package.
    final quran = widget.quran;
    final reviewing = QuranReadingData.fromVariantSlug(_marginRiwayah);
    return {
      for (final juncture in _farshDifferencesOnPage(
        quran,
        page,
        _marginRiwayah,
      ))
        ...juncture.locations,
      if (reviewing != null)
        for (final difference in quran.publishedDifferencesForPairOnPage(
          QuranReading.hafs,
          reviewing,
          page,
        ))
          for (final span in [difference.baseSpan, difference.targetSpan])
            if (span.reading == QuranReading.hafs)
              for (
                var index = span.startWordIndex;
                index <= span.endWordIndex;
                index++
              )
                '${span.surah}:${span.ayah}:$index',
    };
  }

  void _setDifferencesPlacement(DifferencesPlacement placement) {
    _scaffoldKey.currentState?.closeDrawer();
    if (placement == DifferencesPlacement.margin) {
      _setMarginRiwayah(_marginRiwayah);
      return;
    }
    setState(() => _differencesPlacement = placement);
    widget.preferences.setString(_differencesPlacementKey, placement.name);
  }

  void _setMarginRiwayah(String riwayah) {
    final reading = QuranReadingData.fromVariantSlug(riwayah);
    setState(() {
      _primaryReading = QuranReading.hafs;
      _marginRiwayah = riwayah;
      if (reading != null && reading != QuranReading.hafs) {
        _comparisonReading = reading;
      }
      _differencesPlacement = DifferencesPlacement.margin;
    });
    widget.preferences.setString(_primaryReadingKey, QuranReading.hafs.name);
    widget.preferences.setString(_marginRiwayahKey, riwayah);
    widget.preferences.setString(
      _comparisonReadingKey,
      _comparisonReading.name,
    );
    widget.preferences.setString(
      _differencesPlacementKey,
      DifferencesPlacement.margin.name,
    );
  }

  void _openDifferences() {
    if (_differencesPlacement != DifferencesPlacement.hidden) {
      _restoreMargin = _differencesPlacement == DifferencesPlacement.margin;
      widget.preferences.setBool(_restoreMarginKey, _restoreMargin);
      _setDifferencesPlacement(DifferencesPlacement.hidden);
    } else if (_restoreMargin && _primaryReading == QuranReading.hafs) {
      _setDifferencesPlacement(DifferencesPlacement.margin);
    } else {
      _scaffoldKey.currentState?.openDrawer();
    }
  }

  Widget _buildReadingArea(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final reader = Semantics(
        onTap: _toggleChrome,
        expanded: _chromeVisible,
        hint: _chromeVisible ? 'إخفاء أدوات القراءة' : 'إظهار أدوات القراءة',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          excludeFromSemantics: true,
          onTap: _toggleChrome,
          child: PageView.builder(
            key: const PageStorageKey('mushaf-page-view'),
            controller: _pageController,
            itemCount: _pageCount,
            reverse: false,
            onPageChanged: _onPageChanged,
            itemBuilder: (_, index) => QuranTextPage(
              key: ValueKey('reader-page-${index + 1}'),
              night: _nightReading,
              page: index + 1,
              hizb: _hizbForPage(index + 1),
              flowFontSize: _flowFontSize,
              reading: _primaryReading,
              comparisonReading: _comparisonReading,
              quran: widget.quran,
              differenceWordLocations: _marginHighlights(index + 1),
              marginRiwayah: _marginRiwayah,
              onMarginRiwayahChanged:
                  _differencesPlacement == DifferencesPlacement.margin
                  ? _setMarginRiwayah
                  : null,
              onWordSelected: _selectWord,
              selectedLocation: _selectedLocation?.page == index + 1
                  ? _selectedLocation
                  : null,
            ),
          ),
        ),
      );
      if (_differencesPlacement == DifferencesPlacement.hidden ||
          _differencesPlacement == DifferencesPlacement.margin) {
        return reader;
      }

      final colors = Theme.of(context).colorScheme;
      final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
      final side =
          _differencesPlacement == DifferencesPlacement.side &&
          constraints.maxWidth >= 640 &&
          textScale <= 1.6;
      final sideWidth = math.min(340.0, constraints.maxWidth * .34);
      final panel = Material(
        key: ValueKey(
          side ? 'differences-side-panel' : 'differences-bottom-panel',
        ),
        color: colors.surfaceContainerLow,
        child: DifferencesPanel(
          page: _page,
          baseReading: _primaryReading,
          comparisonReading: _comparisonReading,
          quran: widget.quran,
          compact: true,
          narrow: side && sideWidth < 280,
          placement: side
              ? DifferencesPlacement.side
              : DifferencesPlacement.bottom,
          onPlacementChanged: _setDifferencesPlacement,
          onClose: () => _setDifferencesPlacement(DifferencesPlacement.hidden),
        ),
      );
      if (side) {
        return Row(
          children: [
            SizedBox(width: sideWidth, child: panel),
            VerticalDivider(width: 1, color: colors.outlineVariant),
            Expanded(child: reader),
          ],
        );
      }
      return Column(
        children: [
          Expanded(child: reader),
          Divider(height: 1, color: colors.outlineVariant),
          SizedBox(
            height: math.min(
              320,
              constraints.maxHeight *
                  (.38 +
                      .12 *
                          (MediaQuery.textScalerOf(context).scale(14) / 14 - 1)
                              .clamp(0, 1)),
            ),
            child: panel,
          ),
        ],
      );
    },
  );

  Future<void> _selectReadings() async {
    final selected = await showModalBottomSheet<_ReadingPair>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => QuranGlassSheet(
        child: _ReadingPairSheet(
          primary: _primaryReading,
          comparison: _comparisonReading,
        ),
      ),
    );
    if (!mounted || selected == null) return;
    if (selected.primary != QuranReading.hafs &&
        _differencesPlacement == DifferencesPlacement.margin) {
      _setDifferencesPlacement(DifferencesPlacement.hidden);
    }
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
    if (MediaQuery.disableAnimationsOf(context)) {
      _pageController.jumpToPage(result - 1);
      return;
    }
    await _pageController.animateToPage(
      result - 1,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selectedLocation;
    final selectedLabel =
        selected == null || selected.reading != _primaryReading
        ? null
        : '${_navigation.name(selected.surah)} • آية ${selected.ayah}${selected.word == null ? '' : ' • كلمة ${selected.word}'}';
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: _nightReading
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
      child: Scaffold(
        key: _scaffoldKey,
        drawer: DifferencesDrawer(
          page: _page,
          baseReading: _primaryReading,
          comparisonReading: _comparisonReading,
          quran: widget.quran,
          onPlacementChanged: _setDifferencesPlacement,
        ),
        backgroundColor: _nightReading ? _nightPaper : _paper,
        drawerEnableOpenDragGesture: false,
        body: SafeArea(
          child: Stack(
            fit: StackFit.expand,
            children: [
              _buildReadingArea(context),
              if (_showHint && !_chromeVisible)
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                    child: IgnorePointer(
                      child: QuranGlass(
                        floating: true,
                        radius: QuranDesign.controlRadius,
                        child: Padding(
                          key: const ValueKey('reader-first-hint'),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          child: Text(
                            'انقر على الصفحة لإظهار الأدوات، واضغط مطولًا على كلمة لحفظ موضعك',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              AnimatedSwitcher(
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 180),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                layoutBuilder: (current, previous) => Stack(
                  fit: StackFit.expand,
                  children: [
                    for (final child in previous)
                      IgnorePointer(child: ExcludeSemantics(child: child)),
                    ?current,
                  ],
                ),
                child: !_chromeVisible
                    ? const SizedBox.expand()
                    : Stack(
                        key: const ValueKey('reader-overlay'),
                        children: [
                          Align(
                            alignment: Alignment.topCenter,
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 456,
                                ),
                                child: ReaderTopBar(
                                  key: const ValueKey('reader-top-chrome'),
                                  onOpenLibrary: _openLibrary,
                                  onSettings: _openSettings,
                                  onZoom: _openZoom,
                                  selectedLocationLabel: selectedLabel,
                                  onBookmark: selectedLabel == null
                                      ? null
                                      : () => _openLibrary(bookmarks: true),
                                ),
                              ),
                            ),
                          ),
                          Align(
                            alignment: Alignment.bottomCenter,
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 456,
                                ),
                                child: ReaderControls(
                                  key: const ValueKey('reader-bottom-chrome'),
                                  page: _page,
                                  differencesVisible:
                                      _differencesPlacement !=
                                      DifferencesPlacement.hidden,
                                  primaryReading: _primaryReading,
                                  comparisonReading: _comparisonReading,
                                  restoresMargin:
                                      _restoreMargin &&
                                      _primaryReading == QuranReading.hafs,
                                  onOpenDifferences: _openDifferences,
                                  onSelectReading: _selectReadings,
                                  onGoToPage: _goToPage,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GoToPageDialog extends StatefulWidget {
  const _GoToPageDialog({required this.initialPage});

  final int initialPage;

  @override
  State<_GoToPageDialog> createState() => _GoToPageDialogState();
}

class _GoToPageDialogState extends State<_GoToPageDialog> {
  late final TextEditingController _controller;
  String? _error;

  void _submit() {
    final page = parseMushafPage(_controller.text);
    if (page == null) {
      setState(() => _error = 'أدخل رقم صفحة من 1 إلى 604');
      return;
    }
    Navigator.pop(context, page);
  }

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
      onSubmitted: (_) => _submit(),
      onChanged: (_) {
        if (_error != null) setState(() => _error = null);
      },
      decoration: InputDecoration(hintText: 'من 1 إلى 604', errorText: _error),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('إلغاء'),
      ),
      FilledButton(onPressed: _submit, child: const Text('انتقال')),
    ],
  );
}

class QuranTextPage extends StatelessWidget {
  const QuranTextPage({
    super.key,
    required this.page,
    required this.reading,
    required this.comparisonReading,
    required this.quran,
    this.onWordSelected,
    this.wordLongPressOnly = false,
    this.selectedLocation,
    this.night = false,
    this.differenceWordLocations = const {},
    this.onMarginRiwayahChanged,
    this.marginRiwayah = 'shubah',
    this.hizb,
    this.flowFontSize = 27,
  });

  final int page;
  final int? hizb;
  final double flowFontSize;
  final QuranReading reading;
  final QuranReading comparisonReading;
  final QuranRepository quran;
  final ValueChanged<MushafLayoutWord>? onWordSelected;
  final bool wordLongPressOnly;
  final ReaderLocation? selectedLocation;
  final bool night;
  final Set<String> differenceWordLocations;
  final ValueChanged<String>? onMarginRiwayahChanged;
  final String marginRiwayah;

  @override
  Widget build(BuildContext context) {
    final content = _WordGestureScope(
      onWordSelected: onWordSelected,
      longPressOnly: wordLongPressOnly,
      selectedLocation: selectedLocation,
      differenceWordLocations: differenceWordLocations,
      child: Builder(builder: _buildPage),
    );
    return night && Theme.of(context).brightness != Brightness.dark
        ? Theme(data: quranTheme(night: true), child: content)
        : content;
  }

  Widget _buildPage(BuildContext context) {
    if (reading == QuranReading.hafs) {
      final layoutPage = quran.hafsLayout?.page(page);
      if (layoutPage == null) {
        return const _LayoutUnavailablePage();
      }
      final ayahs = quran.page(page);
      return _HafsLineLayoutPage(
        page: layoutPage,
        juz: ayahs.firstOrNull?.juz,
        hizb: hizb,
        surahNames: ayahs
            .map((ayah) => ayah.surahName)
            .where((name) => name.isNotEmpty)
            .toSet()
            .join(' • '),
        primaryReading: reading,
        comparisonReading: comparisonReading,
        quran: quran,
        onMarginRiwayahChanged: onMarginRiwayahChanged,
        marginRiwayah: marginRiwayah,
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
            child: ColoredBox(
              color: _readingColor(context, _paper, _nightPaper),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        Text(
                          'صفحة $page',
                          style: TextStyle(
                            color: _readingColor(context, _green, _nightInk),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          surahNames,
                          style: const TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          reading.shortTitle,
                          style: TextStyle(
                            color: _readingColor(context, _green, _nightInk),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 24),
                    if (reading != QuranReading.hafs) ...[
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerLow,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: Theme.of(context).colorScheme.outlineVariant,
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Iconsax.info_circle,
                                size: 18,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'عرض مقارنة نصية لآيات صفحة حفص؛ لا يطابق تخطيط صفحات مصحف ${reading.shortTitle} الأصلي حتى توفر حزمة التخطيط.',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (verses.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 28),
                        child: Text(
                          'لا توجد محاذاة آيات موثقة لهذه الصفحة في البيانات الحالية.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      )
                    else
                      for (final ayah in verses)
                        _TappableFlowAyah(
                          fontSize: flowFontSize,
                          ayah: ayah,
                          primaryReading: reading,
                          comparisonReading: comparisonReading,
                          quran: quran,
                        ),
                    const SizedBox(height: 18),
                    Text(
                      '$page',
                      style: TextStyle(
                        fontSize: 13,
                        color: _readingColor(
                          context,
                          const Color(0xff685f51),
                          _nightInk,
                        ),
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
    this.fontSize = 27,
    required this.ayah,
    required this.primaryReading,
    required this.comparisonReading,
    required this.quran,
  });

  final Ayah ayah;
  final double fontSize;
  final QuranReading primaryReading;
  final QuranReading comparisonReading;
  final QuranRepository quran;

  static final _ayahNumber = RegExp(r'^[٠-٩0-9]+$');

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
            if (_ayahNumber.hasMatch(words[index]))
              TextSpan(
                text: '﴿${words[index]}﴾ ',
                style: TextStyle(
                  fontFamily: 'NotoSansArabic',
                  fontSize: fontSize * .62,
                  color: _readingColor(context, _green, _nightInk),
                  fontWeight: FontWeight.w700,
                ),
              )
            else
              _interactiveWordSpan(
                context,
                quran: quran,
                primaryReading: primaryReading,
                comparisonReading: comparisonReading,
                word: MushafLayoutWord(
                  location: '${ayah.surah}:${ayah.number}:${index + 1}',
                  text: words[index],
                ),
                suffix: ' ',
              ),
        ],
      ),
      textDirection: TextDirection.rtl,
      textAlign: TextAlign.justify,
      style: TextStyle(
        fontFamily: primaryReading.unicodeFontFamily,
        fontSize: fontSize,
        height: 1.8,
        color: _readingColor(context, const Color(0xff151515), _nightInk),
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
    required this.surahNames,
    required this.juz,
    this.hizb,
    required this.primaryReading,
    required this.comparisonReading,
    required this.quran,
    required this.onMarginRiwayahChanged,
    required this.marginRiwayah,
  });

  final MushafLayoutPage page;
  final String surahNames;
  final int? juz;
  final int? hizb;
  final QuranReading primaryReading;
  final QuranReading comparisonReading;
  final QuranRepository quran;
  final ValueChanged<String>? onMarginRiwayahChanged;
  final String marginRiwayah;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: _readingColor(context, _paper, _nightPaper),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final pageWidth = math.min(constraints.maxWidth, 760.0);
        final onMarginChanged = onMarginRiwayahChanged;
        final notes = onMarginChanged == null
            ? const <int, List<_MarginNote>>{}
            : _marginNotesByLine(quran, page, marginRiwayah);
        final scaler = MediaQuery.textScalerOf(context);
        final inlineMargin =
            pageWidth >= 360 &&
            scaler.scale(14) <= 21 &&
            notes.values.any((entries) => entries.isNotEmpty);
        final marginWidth = inlineMargin
            ? (pageWidth * .15).clamp(52.0, 112.0)
            : 0.0;
        // Without aligned notes the margin's menu sits in the footer, beside
        // the page number, instead of taking a row of its own.
        final footerMargin = onMarginChanged != null && !inlineMargin;
        final horizontalPadding = (pageWidth * .03).clamp(10.0, 20.0);
        final metadataHeight = math.max(52.0, scaler.scale(18) * 1.8);
        final pageNumberHeight = math.max(
          footerMargin ? 48.0 : 38.0,
          scaler.scale(14) * 1.8,
        );
        final minimumLineHeight = ((pageWidth - marginWidth) * .107).clamp(
          30.0,
          52.0,
        );
        final lineHeight = math.max(
          minimumLineHeight,
          (constraints.maxHeight - metadataHeight - pageNumberHeight) / 15,
        );
        final opening =
            page.number <= 2 &&
            page.lines.firstOrNull?.type == MushafLayoutLineType.surahHeader;
        final lineCount = opening ? page.lines.last.number.clamp(1, 15) : 15;
        final linesByNumber = {
          for (final line in page.lines) line.number: line,
        };
        final margin = onMarginChanged == null
            ? null
            : _MushafMargin(
                page: page,
                riwayah: marginRiwayah,
                quran: quran,
                metadataHeight: metadataHeight,
                lineHeight: lineHeight,
                lineCount: lineCount,
                footerHeight: pageNumberHeight,
                onRiwayahChanged: onMarginChanged,
                notesByLine: notes,
                aligned: inlineMargin,
              );
        // One type size per page: each line may only shrink below the page
        // size when it cannot fit, so neighbouring lines stay consistent.
        final lineWidth =
            pageWidth -
            marginWidth -
            2 * horizontalPadding -
            4 -
            2 * _TappableMushafLine._inkInset;
        final fits = [
          for (final line in page.lines)
            if (line.type != MushafLayoutLineType.surahHeader &&
                line.type != MushafLayoutLineType.basmala &&
                (line.words.isNotEmpty || line.displayText.trim().isNotEmpty))
              _TappableMushafLine.fitFontSize(
                context,
                _TappableMushafLine.plainText(line.words, line.displayText),
                lineWidth,
                lineHeight,
              ),
        ]..sort();
        final pageFontSize = fits.isEmpty
            ? _TappableMushafLine._maximumFontSize
            : math.max(fits.first, fits[fits.length ~/ 2] * .92);
        final ink = _readingColor(context, _ink, _nightInk);
        final muted = _readingColor(context, _mutedInk, _nightInk);
        final rule = BorderSide(
          color: _readingColor(context, _ink, _nightRule),
          width: 1,
        );
        final content = Center(
          child: SizedBox(
            width: pageWidth,
            child: Stack(
              children: [
                Positioned(
                  top: metadataHeight,
                  left: horizontalPadding + marginWidth,
                  right: horizontalPadding,
                  bottom: pageNumberHeight,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(border: Border(top: rule)),
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.only(
                    left: horizontalPadding + marginWidth,
                    right: horizontalPadding,
                  ),
                  child: Column(
                    children: [
                      SizedBox(
                        height: metadataHeight,
                        child: Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: Text(
                                opening || surahNames.isEmpty
                                    ? 'مصحف المدينة'
                                    : surahNames,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: ink,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            if (juz case final number?)
                              Expanded(
                                flex: 2,
                                child: Text(
                                  pageWidth < 360
                                      ? 'صفحة ${_readerDigits(page.number)}'
                                      : [
                                          'الجزء ${_readerDigits(number)}',
                                          if (hizb case final value?)
                                            'الحزب ${_readerDigits(value)}',
                                        ].join(' · '),
                                  textAlign: TextAlign.end,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: muted, fontSize: 12),
                                ),
                              ),
                          ],
                        ),
                      ),
                      SizedBox(
                        height: 15 * lineHeight,
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (var row = 1; row <= lineCount; row++)
                                SizedBox(
                                  height: lineHeight,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 2,
                                    ),
                                    child: linesByNumber[row] == null
                                        ? null
                                        : _MushafLine(
                                            page: page.number,
                                            line: linesByNumber[row]!,
                                            lineHeight: lineHeight,
                                            fontCeiling: pageFontSize,
                                            primaryReading: primaryReading,
                                            comparisonReading:
                                                comparisonReading,
                                            quran: quran,
                                          ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(
                        height: pageNumberHeight,
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                'حفص عن عاصم',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: muted, fontSize: 11),
                              ),
                            ),
                            Text(
                              _readerDigits(page.number),
                              style: TextStyle(
                                color: ink,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Expanded(
                              child: footerMargin && margin != null
                                  ? margin
                                  : const SizedBox.shrink(),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (margin != null && inlineMargin)
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    width: marginWidth,
                    child: margin,
                  ),
              ],
            ),
          ),
        );
        final reading =
            constraints.maxHeight <
                metadataHeight + 15 * minimumLineHeight + pageNumberHeight
            ? SingleChildScrollView(child: content)
            : content;
        return reading;
      },
    ),
  );
}

class _MushafLine extends StatelessWidget {
  const _MushafLine({
    required this.page,
    required this.line,
    required this.lineHeight,
    required this.primaryReading,
    required this.comparisonReading,
    required this.quran,
    this.fontCeiling = _TappableMushafLine._maximumFontSize,
  });

  final int page;
  final MushafLayoutLine line;
  final double lineHeight;
  final double fontCeiling;
  final QuranReading primaryReading;
  final QuranReading comparisonReading;
  final QuranRepository quran;

  @override
  Widget build(BuildContext context) {
    final text = line.displayText;
    if (line.type == MushafLayoutLineType.surahHeader) {
      final frame = _readingColor(context, _green, _nightRule);
      return Padding(
        key: ValueKey('mushaf-line-$page-${line.number}'),
        padding: EdgeInsets.symmetric(
          horizontal: _TappableMushafLine._inkInset,
          vertical: lineHeight * .08,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(lineHeight * .18),
            border: Border.all(color: frame, width: 1.2),
            color: _readingColor(
              context,
              const Color(0xfff1eddf),
              const Color(0xff111412),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(2.5),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(lineHeight * .14),
                border: Border.all(
                  color: frame.withValues(alpha: .45),
                  width: .8,
                ),
              ),
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    text,
                    textDirection: TextDirection.rtl,
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    style: TextStyle(
                      fontFamily: primaryReading.unicodeFontFamily,
                      color: _readingColor(context, _ink, _nightInk),
                      fontSize: math.min(26, lineHeight * .5),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }
    if (line.type == MushafLayoutLineType.basmala) {
      return Align(
        key: ValueKey('mushaf-line-$page-${line.number}'),
        alignment: Alignment.center,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: _TappableMushafLine._inkInset,
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              text.isEmpty ? 'بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ' : text,
              textDirection: TextDirection.rtl,
              textAlign: TextAlign.right,
              maxLines: 1,
              style: TextStyle(
                fontFamily: primaryReading.unicodeFontFamily,
                fontSize: math.min(20, lineHeight * .46),
              ),
            ),
          ),
        ),
      );
    }
    return SizedBox.expand(
      key: ValueKey('mushaf-line-$page-${line.number}'),
      child: LayoutBuilder(
        builder: (context, constraints) => _TappableMushafLine(
          words: line.words,
          fallbackText: text,
          maxWidth: constraints.maxWidth,
          lineHeight: lineHeight,
          fontCeiling: fontCeiling,
          justify: page > 2,
          quran: quran,
          primaryReading: primaryReading,
          comparisonReading: comparisonReading,
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

class _TappableMushafLine extends StatelessWidget {
  const _TappableMushafLine({
    required this.words,
    required this.fallbackText,
    required this.maxWidth,
    required this.lineHeight,
    required this.onWordTap,
    required this.quran,
    required this.primaryReading,
    required this.comparisonReading,
    this.fontCeiling = _maximumFontSize,
    this.justify = true,
  });

  final List<MushafLayoutWord> words;
  final bool justify;
  final String fallbackText;
  final double maxWidth;
  final double lineHeight;
  final double fontCeiling;
  final ValueChanged<MushafLayoutWord> onWordTap;
  final QuranRepository quran;
  final QuranReading primaryReading;
  final QuranReading comparisonReading;

  TextStyle _baseStyle(BuildContext context) => TextStyle(
    fontFamily: primaryReading.unicodeFontFamily,
    color: _readingColor(context, _ink, _nightInk),
  );
  static const double _maximumFontSize = 36;
  static const double _inkInset = 4;
  static final _verseNumbers = RegExp(r'(^|\s)([٠-٩]+)(?=\s|$)');

  static String _displayText(String text) => text.replaceAllMapped(
    _verseNumbers,
    // A non-breaking space keeps the verse ornament on its word's line.
    (match) => '${match[1]!.isEmpty ? '' : '\u00a0'}۝${match[2]}',
  );

  static String plainText(List<MushafLayoutWord> words, String fallback) =>
      words.isEmpty
      ? _displayText(fallback.trim())
      : words.map((word) => _displayText(word.text)).join(' ');

  static TextStyle _style(BuildContext context, QuranReading reading) =>
      DefaultTextStyle.of(context).style
          .merge(TextStyle(fontFamily: reading.unicodeFontFamily));

  /// Largest size (up to [_maximumFontSize]) at which [text] fits one line.
  static double fitFontSize(
    BuildContext context,
    String text,
    double width,
    double lineHeight, {
    QuranReading reading = QuranReading.hafs,
    double ceiling = _maximumFontSize,
  }) {
    if (text.isEmpty || width <= 0) return ceiling;
    final style = _style(context, reading);
    final painter = TextPainter(
      textDirection: TextDirection.rtl,
      textScaler: MediaQuery.textScalerOf(context),
      locale: Localizations.maybeLocaleOf(context),
      maxLines: 1,
    );
    var low = 0.0;
    var high = ceiling;
    for (var iteration = 0; iteration < 12; iteration++) {
      final middle = (low + high) / 2;
      painter
        ..text = TextSpan(
          text: text,
          style: style.copyWith(fontSize: middle),
        )
        ..layout();
      if (painter.width <= width && painter.height <= lineHeight) {
        low = middle;
      } else {
        high = middle;
      }
    }
    painter.dispose();
    return low;
  }

  @override
  Widget build(BuildContext context) {
    final displayWords = words
        .map((word) => _displayText(word.text))
        .toList(growable: false);
    final plain = words.isEmpty
        ? _displayText(fallbackText.trim())
        : displayWords.join(' ');
    final span = TextSpan(text: plain);
    final style = _fitLine(context, span, plain);
    if (words.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: _inkInset),
        child: Align(
          alignment: justify ? Alignment.centerRight : Alignment.center,
          child: Text(
            plain,
            textDirection: TextDirection.rtl,
            maxLines: 1,
            softWrap: false,
            style: style,
          ),
        ),
      );
    }
    // Each word is laid out on its own and the line shares the free space
    // between them, so a line always starts and ends with the same words as
    // the printed page. Stretching one paragraph with word spacing let the
    // text engine push the last word onto a hidden second line.
    final pieces = [
      for (var index = 0; index < words.length; index++)
        Text.rich(
          TextSpan(
            children: [
              _interactiveWordSpan(
                context,
                quran: quran,
                primaryReading: primaryReading,
                comparisonReading: comparisonReading,
                word: words[index],
                displayText: displayWords[index],
                onOpen: () => onWordTap(words[index]),
              ),
            ],
          ),
          textDirection: TextDirection.rtl,
          // Left alignment keeps the engine from laying the word out a second
          // time at its rounded intrinsic width, which could wrap it.
          textAlign: TextAlign.left,
          maxLines: 1,
          softWrap: false,
          style: style,
        ),
    ];
    final row = Row(
      textDirection: TextDirection.rtl,
      mainAxisSize: justify ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: justify
          ? MainAxisAlignment.spaceBetween
          : MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      spacing: justify ? 0 : (style.fontSize ?? 20) * .28,
      children: pieces,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: _inkInset),
      child: Center(child: row),
    );
  }

  TextStyle _fitLine(BuildContext context, TextSpan span, String text) {
    final style = DefaultTextStyle.of(context).style.merge(_baseStyle(context));
    final availableWidth = math.max(0.0, maxWidth - 2 * _inkInset);
    if (text.isEmpty || availableWidth == 0) {
      return style.copyWith(fontSize: _maximumFontSize);
    }
    final scaler = MediaQuery.textScalerOf(context);
    final painter = TextPainter(
      textDirection: TextDirection.rtl,
      textScaler: scaler,
      locale: Localizations.maybeLocaleOf(context),
      maxLines: 1,
    );
    void measure(double fontSize) {
      painter.text = TextSpan(
        children: [span],
        style: style.copyWith(fontSize: fontSize),
      );
      painter.layout();
    }

    var low = 0.0;
    var high = math.min(_maximumFontSize, fontCeiling);
    for (var iteration = 0; iteration < 12; iteration++) {
      final middle = (low + high) / 2;
      measure(middle);
      if (painter.width <= availableWidth && painter.height <= lineHeight) {
        low = middle;
      } else {
        high = middle;
      }
    }

    painter.dispose();
    return style.copyWith(fontSize: low);
  }
}

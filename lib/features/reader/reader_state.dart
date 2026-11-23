import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/models/ayah.dart';
import '../../domain/models/margin_riwayah.dart';
import '../../domain/models/qiraat_variants.dart';
import '../../updates/providers.dart';
import 'mushaf_reader_page.dart' show DifferencesPlacement, readerThemeMode;
import 'quran_navigation_index.dart';

/// The reader state that is shared, persisted and must survive a rebuild
/// (A-12): page, both readings, the margin riwayah, differences placement,
/// appearance, and the reader's own preferences.
///
/// Purely local UI state — whether the chrome is visible, a validation error,
/// a one-time hint — stays in the widget, because nothing else reads it and
/// it must not be persisted.
class ReaderState {
  const ReaderState({
    required this.page,
    required this.primaryReading,
    required this.comparisonReading,
    required this.marginRiwayah,
    required this.placement,
    required this.appearance,
    required this.keepAwake,
    required this.flowFontSize,
  });

  final int page;
  final QuranReading primaryReading;
  final QuranReading comparisonReading;
  final String marginRiwayah;
  final DifferencesPlacement placement;
  final ThemeMode appearance;
  final bool keepAwake;
  final double flowFontSize;

  bool get nightReading => switch (appearance) {
    ThemeMode.dark => true,
    ThemeMode.light => false,
    ThemeMode.system => false,
  };

  ReaderState copyWith({
    int? page,
    QuranReading? primaryReading,
    QuranReading? comparisonReading,
    String? marginRiwayah,
    DifferencesPlacement? placement,
    ThemeMode? appearance,
    bool? keepAwake,
    double? flowFontSize,
  }) => ReaderState(
    page: page ?? this.page,
    primaryReading: primaryReading ?? this.primaryReading,
    comparisonReading: comparisonReading ?? this.comparisonReading,
    marginRiwayah: marginRiwayah ?? this.marginRiwayah,
    placement: placement ?? this.placement,
    appearance: appearance ?? this.appearance,
    keepAwake: keepAwake ?? this.keepAwake,
    flowFontSize: flowFontSize ?? this.flowFontSize,
  );
}

/// Preference keys, in one place so the notifier and the widget agree.
abstract final class ReaderKeys {
  static const lastPage = 'last_page';
  static const primaryReading = 'primary_reading';
  static const comparisonReading = 'comparison_reading';
  static const differencesPlacement = 'differences_placement';
  static const marginRiwayah = 'margin_riwayah';
  static const keepAwake = 'keep_screen_awake';
  static const flowFontSize = 'flow_font_size';
  static const restoreMargin = 'restore_margin_on_open';
  static const appearance = 'reader_appearance';
  static const hintSeen = 'reader_hint_seen';
}

const int readerPageCount = 604;

/// Every riwayah slug the bundled data carries, from assets/qiraat/variants.json.
/// Hafs is included because it is a valid stored value, just never a margin.
const Set<String> knownRiwayahSlugs = {
  'abu-harith', 'buzzi', 'duri', 'duri-kisai', 'hafs', 'hisham', 'ibn-dhakwan',
  'ibn-jammaz', 'ibn-wardan', 'idris', 'ishaq', 'khalaf', 'khallad', 'qaloon',
  'qunbul', 'rawh', 'ruways', 'shubah', 'susi', 'warsh',
};

/// The reader's shared, persisted state (A-12, D16).
final readerStateProvider = NotifierProvider<ReaderStateNotifier, ReaderState>(
  ReaderStateNotifier.new,
);

class ReaderStateNotifier extends Notifier<ReaderState> {
  @override
  ReaderState build() {
    final preferences = ref.watch(sharedPreferencesProvider);
    return _restore(preferences);
  }

  SharedPreferences get _preferences => ref.read(sharedPreferencesProvider);

  QuranReading _savedReading(String? value) => QuranReading.values.firstWhere(
    (reading) => reading.name == value,
    orElse: () => QuranReading.hafs,
  );

  /// Reads the stored state, applying the same rules the widget used to.
  ReaderState _restore(SharedPreferences preferences) {
    final page = (preferences.getInt(ReaderKeys.lastPage) ?? 1).clamp(1, readerPageCount);
    var primary = _savedReading(preferences.getString(ReaderKeys.primaryReading));
    var comparison = _savedReading(
      preferences.getString(ReaderKeys.comparisonReading),
    );

    final placement = DifferencesPlacement.values.firstWhere(
      (candidate) =>
          candidate.name == preferences.getString(ReaderKeys.differencesPlacement),
      orElse: () => primary == QuranReading.hafs
          ? DifferencesPlacement.margin
          : DifferencesPlacement.hidden,
    );

    // The margin shows alongside Hafs, so that pairing forces Hafs in the body.
    if (placement == DifferencesPlacement.margin) primary = QuranReading.hafs;
    if (comparison == primary) {
      comparison = primary == QuranReading.hafs
          ? QuranReading.shubah
          : QuranReading.hafs;
    }

    return ReaderState(
      page: page,
      primaryReading: primary,
      comparisonReading: comparison,
      marginRiwayah: _marginRiwayah(preferences, comparison),
      placement: placement,
      appearance: readerThemeMode(preferences),
      keepAwake: preferences.getBool(ReaderKeys.keepAwake) ?? false,
      flowFontSize:
          (preferences.getDouble(ReaderKeys.flowFontSize) ?? 27).clamp(20, 40).toDouble(),
    );
  }

  /// A saved riwayah wins only when it is a known slug and not Hafs.
  ///
  /// Validating against the bundled slug list (not the repository) keeps this
  /// notifier readable before the data loads and in tests.
  String _marginRiwayah(SharedPreferences preferences, QuranReading comparison) {
    final saved = preferences.getString(ReaderKeys.marginRiwayah);
    if (saved != null && saved != QiraatVariants.hafs && knownRiwayahSlugs.contains(saved)) {
      return saved;
    }
    return (comparison == QuranReading.hafs ? QuranReading.shubah : comparison)
        .variantSlug;
  }

  Future<void> setPage(int page) async {
    final clamped = page.clamp(1, readerPageCount);
    if (clamped == state.page) return;
    state = state.copyWith(page: clamped);
    await _preferences.setInt(ReaderKeys.lastPage, clamped);
  }

  /// Changing the comparison reading may require a new default margin riwayah.
  Future<void> setComparisonReading(QuranReading reading) async {
    if (reading == state.primaryReading) return;
    final saved = _preferences.getString(ReaderKeys.marginRiwayah);
    final followsComparison = saved == null || saved == state.comparisonReading.variantSlug;
    state = state.copyWith(
      comparisonReading: reading,
      marginRiwayah: followsComparison ? reading.variantSlug : state.marginRiwayah,
    );
    await _preferences.setString(ReaderKeys.comparisonReading, reading.name);
    if (followsComparison && reading.variantSlug != QiraatVariants.hafs) {
      await _preferences.setString(ReaderKeys.marginRiwayah, reading.variantSlug);
    }
  }

  Future<void> setMarginRiwayah(String riwayah) async {
    if (riwayah == state.marginRiwayah) return;
    state = state.copyWith(marginRiwayah: riwayah);
    await _preferences.setString(ReaderKeys.marginRiwayah, riwayah);
    // The margin reads alongside Hafs; selecting another riwayah implies it.
    if (state.primaryReading != QuranReading.hafs) {
      state = state.copyWith(primaryReading: QuranReading.hafs);
      await _preferences.setString(ReaderKeys.primaryReading, QuranReading.hafs.name);
    }
  }

  Future<void> setPlacement(DifferencesPlacement placement) async {
    if (placement == state.placement) return;
    state = state.copyWith(
      placement: placement,
      primaryReading: placement == DifferencesPlacement.margin
          ? QuranReading.hafs
          : state.primaryReading,
    );
    await _preferences.setString(ReaderKeys.differencesPlacement, placement.name);
    if (placement == DifferencesPlacement.margin) {
      await _preferences.setString(ReaderKeys.primaryReading, QuranReading.hafs.name);
    }
    await _preferences.setBool(
      ReaderKeys.restoreMargin,
      placement == DifferencesPlacement.margin,
    );
  }

  Future<void> setAppearance(ThemeMode mode) async {
    if (mode == state.appearance) return;
    state = state.copyWith(appearance: mode);
    await _preferences.setString(ReaderKeys.appearance, mode.name);
  }

  Future<void> setKeepAwake(bool value) async {
    if (value == state.keepAwake) return;
    state = state.copyWith(keepAwake: value);
    await _preferences.setBool(ReaderKeys.keepAwake, value);
  }

  Future<void> setFlowFontSize(double value) async {
    final clamped = value.clamp(20, 40).toDouble();
    if (clamped == state.flowFontSize) return;
    state = state.copyWith(flowFontSize: clamped);
    await _preferences.setDouble(ReaderKeys.flowFontSize, clamped);
  }
}

/// The hizb starts, loaded once from the pack data (A-12).
final hizbStartsProvider = FutureProvider<List<Ayah>>((ref) async {
  final quran = ref.watch(quranRepositoryProvider);
  return QuranNavigationIndex(quran).hizbs();
});

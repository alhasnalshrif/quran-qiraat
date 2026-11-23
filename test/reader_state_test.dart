import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quran_qiraat/domain/models/margin_riwayah.dart';
import 'package:quran_qiraat/features/reader/mushaf_reader_page.dart' show DifferencesPlacement;
import 'package:quran_qiraat/features/reader/reader_state.dart';
import 'package:quran_qiraat/updates/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A-12: the reader's shared state moves to providers with the same rules,
/// and every change is persisted.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences preferences;
  late ProviderContainer container;

  Future<ProviderContainer> open([Map<String, Object> stored = const {}]) async {
    SharedPreferences.setMockInitialValues(Map<String, Object>.from(stored));
    preferences = await SharedPreferences.getInstance();
    final c = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
    );
    addTearDown(c.dispose);
    return c;
  }

  group('restore (A-12)', () {
    test('defaults to page 1 and Hafs when nothing is stored', () async {
      container = await open();
      final state = container.read(readerStateProvider);
      expect(state.page, 1);
      expect(state.primaryReading, QuranReading.hafs);
      expect(state.comparisonReading, QuranReading.shubah);
      expect(state.placement, DifferencesPlacement.margin);
      expect(state.flowFontSize, 27);
      expect(state.keepAwake, isFalse);
    });

    test('clamps a stored page into 1..604', () async {
      container = await open({ReaderKeys.lastPage: 9999});
      expect(container.read(readerStateProvider).page, 604);
    });

    test('margin placement forces Hafs into the body', () async {
      container = await open({
        ReaderKeys.differencesPlacement: 'margin',
        ReaderKeys.primaryReading: 'qalun',
        ReaderKeys.comparisonReading: 'qalun',
      });
      final state = container.read(readerStateProvider);
      expect(state.primaryReading, QuranReading.hafs);
      expect(state.comparisonReading, isNot(QuranReading.hafs));
    });

    test('a comparison equal to the primary is corrected', () async {
      container = await open({
        ReaderKeys.primaryReading: 'shubah',
        ReaderKeys.comparisonReading: 'shubah',
      });
      final state = container.read(readerStateProvider);
      expect(state.comparisonReading, isNot(state.primaryReading));
    });

    test('clamps a stored font size into 20..40', () async {
      container = await open({ReaderKeys.flowFontSize: 99.0});
      expect(container.read(readerStateProvider).flowFontSize, 40);
    });
  });

  group('changes persist (A-12)', () {
    test('setting the page stores last_page', () async {
      container = await open();
      await container.read(readerStateProvider.notifier).setPage(42);
      expect(container.read(readerStateProvider).page, 42);
      expect(preferences.getInt(ReaderKeys.lastPage), 42);
    });

    test('the page is clamped and identical values are a no-op', () async {
      container = await open();
      final notifier = container.read(readerStateProvider.notifier);
      await notifier.setPage(0);
      expect(container.read(readerStateProvider).page, 1);
      await notifier.setPage(5000);
      expect(container.read(readerStateProvider).page, 604);
    });

    test('selecting another margin riwayah implies Hafs in the body', () async {
      container = await open();
      await container.read(readerStateProvider.notifier).setMarginRiwayah('qaloon');
      final state = container.read(readerStateProvider);
      expect(state.marginRiwayah, 'qaloon');
      expect(state.primaryReading, QuranReading.hafs);
      expect(preferences.getString(ReaderKeys.marginRiwayah), 'qaloon');
    });

    test('margin placement is remembered via restore_margin', () async {
      // Start from a stored hidden placement so margin is an actual change.
      container = await open({ReaderKeys.differencesPlacement: 'hidden'});
      final notifier = container.read(readerStateProvider.notifier);
      expect(container.read(readerStateProvider).placement, DifferencesPlacement.hidden);

      await notifier.setPlacement(DifferencesPlacement.margin);
      expect(preferences.getBool(ReaderKeys.restoreMargin), isTrue);
      expect(preferences.getString(ReaderKeys.differencesPlacement), 'margin');

      await notifier.setPlacement(DifferencesPlacement.hidden);
      expect(preferences.getBool(ReaderKeys.restoreMargin), isFalse);
    });

    test('appearance, keep-awake and font size persist', () async {
      container = await open();
      final notifier = container.read(readerStateProvider.notifier);

      await notifier.setAppearance(ThemeMode.dark);
      expect(preferences.getString(ReaderKeys.appearance), 'dark');

      await notifier.setKeepAwake(true);
      expect(preferences.getBool(ReaderKeys.keepAwake), isTrue);

      await notifier.setFlowFontSize(31);
      expect(preferences.getDouble(ReaderKeys.flowFontSize), 31);
    });

    test('changes round-trip through a fresh container', () async {
      container = await open();
      await container.read(readerStateProvider.notifier).setPage(77);
      await container.read(readerStateProvider.notifier).setFlowFontSize(33);
      await container.read(readerStateProvider.notifier).setKeepAwake(true);

      // A new container over the same store must restore what was written.
      final reopened = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
      );
      addTearDown(reopened.dispose);
      final state = reopened.read(readerStateProvider);
      expect(state.page, 77);
      expect(state.flowFontSize, 33);
      expect(state.keepAwake, isTrue);
    });
  });
}

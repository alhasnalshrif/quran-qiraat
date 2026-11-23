import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:quran_qiraat/app/deep_link_actions.dart';
import 'package:quran_qiraat/app/deep_links.dart';

/// N-03: a parsed link resolves to a real destination, or to nothing.
void main() {
  // A tiny stand-in for the loaded Hafs layout.
  final pages = <int, List<String>>{
    1: ['1:1', '1:2', '1:3'],
    3: ['2:6', '2:7'],
    42: ['2:255'],
  };

  LinkAction? resolve(String raw, {bool hasAnnouncement = true}) => actionForLink(
    parseDeepLink(raw),
    ayahKeysByPage: pages,
    hasAnnouncement: (_) => hasAnnouncement,
  );

  group('page links (N-03)', () {
    test('resolves to the page', () {
      expect((resolve('quranqiraat://page/3') as OpenPage).page, 3);
    });
  });

  group('ayah links (N-03)', () {
    test('resolves a verse that exists in the layout', () {
      final action = resolve('quranqiraat://ayah/2/255') as OpenAyah;
      expect(action.surah, 2);
      expect(action.ayah, 255);
    });

    test('ignores a verse the layout does not contain', () {
      expect(resolve('quranqiraat://ayah/9/999'), isNull);
    });
  });

  group('updates and announcements (N-03)', () {
    test('resolves the updates link', () {
      expect(resolve('quranqiraat://updates'), isA<OpenUpdates>());
    });

    test('resolves a known announcement and ignores an unknown one', () {
      expect(resolve('quranqiraat://announcement/a-1'), isA<OpenAnnouncement>());
      expect(resolve('quranqiraat://announcement/a-1', hasAnnouncement: false), isNull);
    });
  });

  group('unresolvable input (N-03)', () {
    test('an invalid or unknown link does nothing', () {
      expect(resolve('not-a-link'), isNull);
      expect(resolve('quranqiraat://nope'), isNull);
      expect(
        actionForLink(null, ayahKeysByPage: pages, hasAnnouncement: (_) => true),
        isNull,
      );
    });
  });

  group('preparePageTarget (N-03)', () {
    test('clamps to the real page range and stores the target', () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();

      await preparePageTarget(preferences, 0);
      expect(preferences.getInt(lastPagePreference), 1);

      await preparePageTarget(preferences, 9999);
      expect(preferences.getInt(lastPagePreference), 604);

      await preparePageTarget(preferences, 42);
      expect(preferences.getInt(lastPagePreference), 42);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:quran_qiraat/app/deep_links.dart';

/// N-03: every link in 03 §12 parses, and a bad link is ignored, not fatal.
void main() {
  group('page links (N-03)', () {
    test('parses a page in range', () {
      expect((parseDeepLink('quranqiraat://page/3') as PageLink).page, 3);
      expect((parseDeepLink('quranqiraat://page/604') as PageLink).page, 604);
    });

    test('rejects a page outside 1-604', () {
      expect(parseDeepLink('quranqiraat://page/0'), isNull);
      expect(parseDeepLink('quranqiraat://page/605'), isNull);
      expect(parseDeepLink('quranqiraat://page/abc'), isNull);
    });
  });

  group('ayah links (N-03)', () {
    test('parses a surah and ayah', () {
      final link = parseDeepLink('quranqiraat://ayah/2/255') as AyahLink;
      expect(link.surah, 2);
      expect(link.ayah, 255);
    });

    test('rejects an out-of-range surah or ayah', () {
      expect(parseDeepLink('quranqiraat://ayah/115/1'), isNull);
      expect(parseDeepLink('quranqiraat://ayah/1/0'), isNull);
      expect(parseDeepLink('quranqiraat://ayah/1'), isNull);
    });
  });

  group('other links (N-03)', () {
    test('parses the updates link', () {
      expect(parseDeepLink('quranqiraat://updates'), isA<UpdatesLink>());
    });

    test('parses an announcement id', () {
      final link = parseDeepLink('quranqiraat://announcement/a-2026-1') as AnnouncementLink;
      expect(link.id, 'a-2026-1');
    });

    test('rejects an announcement with no id', () {
      expect(parseDeepLink('quranqiraat://announcement/'), isNull);
    });
  });

  group('invalid input (N-03)', () {
    test('ignores anything that is not one of our links', () {
      expect(parseDeepLink(null), isNull);
      expect(parseDeepLink(''), isNull);
      expect(parseDeepLink('https://example.com'), isNull);
      expect(parseDeepLink('quranqiraat://'), isNull);
      expect(parseDeepLink('quranqiraat://unknown/1'), isNull);
      expect(parseDeepLink('quranqiraat://page/3/extra'), isNull);
    });

    test('tolerates extra whitespace and a trailing slash', () {
      expect((parseDeepLink('  quranqiraat://page/3/  ') as PageLink).page, 3);
    });
  });
}

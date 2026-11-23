import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quran_qiraat/updates/pack_validators.dart';

/// A-06: the Dart validators must accept the bundled packs and reject the same
/// breakage the TypeScript suite in `packages/contracts` rejects.
Object? _asset(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Object?;

Map<String, dynamic> _clone(Map<String, dynamic> value) =>
    jsonDecode(jsonEncode(value)) as Map<String, dynamic>;

void main() {
  final hafs = _asset('assets/quran_hafs.json')! as List;
  final hafsAyahKeys = {
    for (final ayah in hafs)
      '${(ayah as Map<String, dynamic>)['sura_no']}:${ayah['aya_no']}',
  };
  final layout = _asset('assets/mushaf/layout/hafs_madani_604.json')!
      as Map<String, dynamic>;
  final hafsWordLocations = {
    for (final page in layout['pages'] as List)
      for (final line in (page as Map<String, dynamic>)['lines'] as List)
        for (final word in ((line as Map<String, dynamic>)['words'] as List?) ??
            const [])
          (word as Map<String, dynamic>)['location'] as String,
  };

  group('kfgqpc-ayahs@1 (A-06)', () {
    test('accepts the bundled Hafs text with the manifest count', () {
      expect(validateKfgqpcAyahs(hafs, totalAyahs: 6236).errors, isEmpty);
    });

    test('accepts the bundled Qalun text with its own count', () {
      expect(
        validateKfgqpcAyahs(_asset('assets/quran_qalun.json'), totalAyahs: 6214).ok,
        isTrue,
      );
    });

    test('rejects an empty ayah text', () {
      final broken = jsonDecode(jsonEncode(hafs)) as List;
      (broken.first as Map<String, dynamic>)['aya_text'] = '   ';
      expect(validateKfgqpcAyahs(broken).ok, isFalse);
    });

    test('rejects a duplicate ayah', () {
      final broken = jsonDecode(jsonEncode(hafs)) as List;
      broken.add(jsonDecode(jsonEncode(hafs.first)));
      final result = validateKfgqpcAyahs(broken);
      expect(result.ok, isFalse);
      expect(result.errors.join(' '), contains('duplicate ayah'));
    });

    test('rejects a count that disagrees with totalAyahs', () {
      expect(validateKfgqpcAyahs(hafs, totalAyahs: 6000).ok, isFalse);
    });

    test('rejects an out-of-range surah', () {
      final broken = jsonDecode(jsonEncode(hafs)) as List;
      (broken.first as Map<String, dynamic>)['sura_no'] = 115;
      expect(validateKfgqpcAyahs(broken).ok, isFalse);
    });
  });

  group('mushaf-layout@1 (A-06)', () {
    test('accepts the bundled 604-page layout', () {
      expect(validateMushafLayout(layout).errors, isEmpty);
    });

    test('rejects a page count other than 604', () {
      final broken = _clone(layout);
      (broken['pages'] as List).removeLast();
      expect(validateMushafLayout(broken).ok, isFalse);
    });

    test('rejects an invalid word location', () {
      final broken = _clone(layout);
      final line = (broken['pages'] as List)
          .cast<Map<String, dynamic>>()
          .expand((page) => (page['lines'] as List).cast<Map<String, dynamic>>())
          .firstWhere((line) => line['words'] != null);
      ((line['words'] as List).first as Map<String, dynamic>)['location'] =
          '2-6-1';
      expect(validateMushafLayout(broken).ok, isFalse);
    });

    test('rejects a text line with no words', () {
      final broken = _clone(layout);
      final line = (broken['pages'] as List)
          .cast<Map<String, dynamic>>()
          .expand((page) => (page['lines'] as List).cast<Map<String, dynamic>>())
          .firstWhere((line) => line['words'] != null);
      line['words'] = <dynamic>[];
      expect(validateMushafLayout(broken).ok, isFalse);
    });

    test('rejects a non-monotonic line number', () {
      final broken = _clone(layout);
      final lines = ((broken['pages'] as List).first
          as Map<String, dynamic>)['lines'] as List;
      (lines[1] as Map<String, dynamic>)['number'] =
          (lines[0] as Map<String, dynamic>)['number'];
      expect(validateMushafLayout(broken).ok, isFalse);
    });
  });

  group('qiraat-variants@1 (A-06)', () {
    final variants = _asset('assets/qiraat/variants.json')!
        as Map<String, dynamic>;

    test('accepts the bundled variants against Hafs and the layout', () {
      final result = validateQiraatVariants(
        variants,
        hafsAyahKeys: hafsAyahKeys,
        hafsWordLocations: hafsWordLocations,
      );
      expect(result.errors, isEmpty);
    });

    test('rejects a reader count other than ten', () {
      final broken = _clone(variants);
      (broken['readers'] as Map<String, dynamic>).remove('10');
      expect(validateQiraatVariants(broken).ok, isFalse);
    });

    test('rejects a transmitter count other than twenty', () {
      final broken = _clone(variants);
      (broken['transmitters'] as Map<String, dynamic>).remove('20');
      expect(validateQiraatVariants(broken).ok, isFalse);
    });

    test('rejects a segment ayah missing from Hafs', () {
      final broken = _clone(variants);
      final segment = (((broken['junctures'] as List).first
              as Map<String, dynamic>)['segments'] as List)
          .first as Map<String, dynamic>;
      segment['ayah'] = '999:1';
      expect(
        validateQiraatVariants(broken, hafsAyahKeys: hafsAyahKeys).ok,
        isFalse,
      );
    });

    test('rejects a word range pointing at a missing layout word', () {
      final broken = _clone(variants);
      Map<String, dynamic>? withWords;
      for (final juncture in (broken['junctures'] as List)) {
        for (final segment
            in ((juncture as Map<String, dynamic>)['segments'] as List)) {
          if ((segment as Map<String, dynamic>)['words'] != null) {
            withWords = segment;
            break;
          }
        }
        if (withWords != null) break;
      }
      withWords!['words'] = [900, 901];
      expect(
        validateQiraatVariants(broken, hafsWordLocations: hafsWordLocations).ok,
        isFalse,
      );
    });
  });

  group('ayah-map@1 (A-06)', () {
    final map = _asset('assets/mappings/hafs_to_qalun.json')!
        as Map<String, dynamic>;

    test('accepts the bundled Hafs-to-Qalun map', () {
      expect(validateAyahMap(map).errors, isEmpty);
    });

    test('rejects an unsupported version', () {
      final broken = _clone(map)..['_version'] = '9.9.9';
      expect(validateAyahMap(broken).ok, isFalse);
    });
  });

  group('hizb-starts@1 (A-06)', () {
    final hizbs = _asset('assets/navigation/hafs_hizbs.json')!
        as Map<String, dynamic>;

    test('accepts the bundled 60 hizb starts against Hafs', () {
      expect(validateHizbStarts(hizbs, hafsAyahKeys: hafsAyahKeys).errors, isEmpty);
    });

    test('rejects a wrong start count', () {
      final broken = _clone(hizbs);
      (broken['hizb_starts'] as List).removeLast();
      expect(validateHizbStarts(broken).ok, isFalse);
    });

    test('rejects a start missing from Hafs', () {
      final broken = _clone(hizbs);
      (broken['hizb_starts'] as List)[0] = '999:1';
      expect(validateHizbStarts(broken, hafsAyahKeys: hafsAyahKeys).ok, isFalse);
    });
  });

  group('editions-manifest@1 (A-06)', () {
    final manifest = _asset('assets/editions_manifest.json')!
        as Map<String, dynamic>;

    test('accepts the bundled editions manifest', () {
      expect(validateEditionsManifest(manifest).errors, isEmpty);
    });

    test('rejects an empty editions list', () {
      final broken = _clone(manifest)..['editions'] = <dynamic>[];
      expect(validateEditionsManifest(broken).ok, isFalse);
    });

    test('rejects a duplicate edition id', () {
      final broken = _clone(manifest);
      (broken['editions'] as List).add(
        jsonDecode(jsonEncode((broken['editions'] as List).first)),
      );
      expect(validateEditionsManifest(broken).ok, isFalse);
    });
  });

  group('published-differences@1 (A-06)', () {
    final published = _asset('assets/published_differences.json')!
        as Map<String, dynamic>;

    test('accepts the bundled published differences', () {
      expect(validatePublishedDifferences(published).errors, isEmpty);
    });

    test('rejects an unsupported schema version', () {
      final broken = _clone(published)..['schema_version'] = '2.0.0';
      expect(validatePublishedDifferences(broken).ok, isFalse);
    });

    test('rejects an unreviewed record', () {
      final broken = {
        'schema_version': '1.0.0',
        'records': [
          {
            'id': 'x-1',
            'review_status': 'candidate',
            'base_span': {
              'reading': 'hafs',
              'ayah': '1:1',
              'start_word': 1,
              'end_word': 1,
              'text': 'أ',
            },
            'target_span': {
              'reading': 'qalun',
              'ayah': '1:1',
              'start_word': 1,
              'end_word': 1,
              'text': 'ب',
            },
          },
        ],
      };
      final result = validatePublishedDifferences(broken);
      expect(result.ok, isFalse);
      expect(result.errors.join(' '), contains('not reviewed'));
    });
  });

  group('format dispatch (A-06)', () {
    test('routes every known format', () {
      expect(isKnownFormat('qiraat-variants@1'), isTrue);
      expect(isKnownFormat('qiraat-variants@2'), isFalse);
      expect(validateFormat('unknown@1', {}).ok, isFalse);
    });

    test('reports invalid JSON as a validation failure', () {
      final result = validateFormatJson('editions-manifest@1', '{not json');
      expect(result.ok, isFalse);
      expect(result.errors.first, contains('invalid JSON'));
    });
  });
}

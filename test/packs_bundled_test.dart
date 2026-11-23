import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Bundled Packs (A-03 / Protocol §1.1 & §1.3)', () {
    const bundledPacks = <String, String>{
      'editions-manifest': 'assets/editions_manifest.json',
      'hafs-text': 'assets/quran_hafs.json',
      'riwayah-shubah-text': 'assets/quran_shubah.json',
      'riwayah-qalun-text': 'assets/quran_qalun.json',
      'hafs-layout-1405': 'assets/mushaf/layout/hafs_madani_604.json',
      'mapping-hafs-qalun': 'assets/mappings/hafs_to_qalun.json',
      'qiraat-farsh': 'assets/qiraat/variants.json',
      'published-differences': 'assets/published_differences.json',
      'navigation-hizbs': 'assets/navigation/hafs_hizbs.json',
    };

    test('packs_bundled.json exists, is valid JSON, and matches protocol 1', () {
      final file = File('assets/packs_bundled.json');
      expect(file.existsSync(), isTrue, reason: 'assets/packs_bundled.json must exist');

      final content = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      expect(content['protocol'], 1);
      expect(content['packs'], isA<Map<String, dynamic>>());

      final packs = content['packs'] as Map<String, dynamic>;
      for (final packId in bundledPacks.keys) {
        expect(packs.containsKey(packId), isTrue, reason: '$packId must be in packs_bundled.json');
        expect(packs[packId], isA<int>());
        expect(packs[packId], greaterThanOrEqualTo(1));
      }
    });

    test('every pack in table 1.1 has its bundledPath existing on disk', () {
      for (final entry in bundledPacks.entries) {
        final path = entry.value;
        final file = File(path);
        expect(file.existsSync(), isTrue, reason: 'Path $path for pack ${entry.key} must exist');
      }
    });

    test('assets/packs_bundled.json is registered in pubspec.yaml', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(
        pubspec.contains('assets/packs_bundled.json'),
        isTrue,
        reason: 'assets/packs_bundled.json must be listed under assets in pubspec.yaml',
      );
    });
  });
}

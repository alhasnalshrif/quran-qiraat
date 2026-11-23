import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quran_qiraat/domain/models/qiraat_variants.dart';
import 'package:quran_qiraat/features/reader/riwayah_picker.dart';

/// R-07: the margin list groups the twenty riwayat under the ten imams and
/// supports search over both names.
void main() {
  final variants = QiraatVariants.parse(
    File('assets/qiraat/variants.json').readAsStringSync(),
  );

  group('grouping (R-07)', () {
    test('produces ten imam groups', () {
      final groups = groupRiwayat(variants);
      expect(groups, hasLength(10));
    });

    test('groups exactly nineteen riwayat, excluding Hafs', () {
      final groups = groupRiwayat(variants);
      final total = groups.fold<int>(0, (sum, group) => sum + group.riwayat.length);
      expect(total, 19);
      expect(
        groups.expand((g) => g.riwayat).any((t) => t.riwayah == 'hafs'),
        isFalse,
      );
    });

    test('orders the imams by their canonical position', () {
      final groups = groupRiwayat(variants);
      final positions = [
        for (final group in groups) variants.readers[group.readerId]!.position,
      ];
      expect(positions, [...positions]..sort());
    });

    test('every transmitter sits under the imam it belongs to', () {
      for (final group in groupRiwayat(variants)) {
        for (final transmitter in group.riwayat) {
          expect(transmitter.reader, group.readerId);
        }
      }
    });

    test('every group has a non-empty imam name', () {
      for (final group in groupRiwayat(variants)) {
        expect(group.readerName.trim(), isNotEmpty);
      }
    });
  });

  group('search (R-07)', () {
    final groups = groupRiwayat(variants);

    test('an empty query returns everything', () {
      expect(filterRiwayat(groups, ''), hasLength(10));
      expect(filterRiwayat(groups, '   '), hasLength(10));
    });

    test('matches an imam name and keeps that whole group', () {
      final imam = groups.first.readerName;
      final filtered = filterRiwayat(groups, imam);
      expect(filtered, isNotEmpty);
      expect(
        filtered.any((g) => g.readerName == imam),
        isTrue,
        reason: 'searching $imam should keep the group',
      );
    });

    test('matches a transmitter name and narrows to it', () {
      final transmitter = groups.first.riwayat.first;
      final filtered = filterRiwayat(groups, transmitter.name);
      final hits = filtered.expand((g) => g.riwayat).toList();
      expect(hits, isNotEmpty);
      expect(hits.every((t) => t.name.contains(transmitter.name)), isTrue);
    });

    test('matches the slug as well as the display name', () {
      final filtered = filterRiwayat(groups, 'qaloon');
      final slugs = filtered.expand((g) => g.riwayat).map((t) => t.riwayah);
      expect(slugs, contains('qaloon'));
    });

    test('a query with no match returns nothing', () {
      expect(filterRiwayat(groups, 'zzzz-no-such-reader'), isEmpty);
    });
  });

  group('dataset sanity (R-07)', () {
    test('the bundled variants really do carry twenty transmitters', () {
      expect(variants.transmitters, hasLength(20));
      expect(variants.readers, hasLength(10));
    });
  });
}

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quran_qiraat/updates/protocol.dart';
import 'package:quran_qiraat/updates/remote_config.dart';

/// A-02: the Dart protocol types must agree with the contract fixtures in
/// `packages/contracts/fixtures/`, the same files the TypeScript suite reads.
Map<String, dynamic> _fixture(String name) =>
    jsonDecode(File('packages/contracts/fixtures/$name').readAsStringSync())
        as Map<String, dynamic>;

void main() {
  group('protocol types (A-02)', () {
    test('parses the 01 §2.2 example payload', () {
      final manifest = Manifest.fromJson(_fixture('manifest-payload.json'));

      expect(manifest.channel, 'stable');
      expect(manifest.app.latestBuild, 9);
      expect(manifest.app.minSupportedBuild, 5);
      expect(manifest.app.message?.ar, contains('نسخة جديدة'));
      expect(manifest.packs, hasLength(1));

      final pack = manifest.release('qiraat-farsh')!;
      expect(pack.version, 2);
      expect(pack.format, 'qiraat-variants@1');
      expect(pack.source?.name, 'Quran Tajweed Engine');
      expect(pack.notes?.ar, contains('البقرة'));
      expect(pack.files, hasLength(2));
      expect(pack.file('variants.json')?.size, 426472);
      expect(pack.file('missing.json'), isNull);

      expect(manifest.isRevoked('qiraat-farsh', 1), isTrue);
      expect(manifest.isRevoked('qiraat-farsh', 2), isFalse);
      expect(manifest.release('hafs-text'), isNull);
      expect(manifest.announcements.single.id, 'a-2026-11-23-1');
    });

    test('decodes the signed envelope into the same manifest', () {
      final envelope = SignedManifest.fromJson(_fixture('manifest-envelope.json'));
      expect(envelope.keyId, 'test');
      expect(envelope.signatureBytes, hasLength(64));
      expect(envelope.decodePayload().packs.single.packId, 'qiraat-farsh');
    });

    test('rejects a payload with another protocol version', () {
      final json = _fixture('manifest-payload.json')..['protocol'] = 2;
      expect(() => Manifest.fromJson(json), throwsFormatException);
    });

    test('rejects a pack file path that escapes the pack', () {
      final json = _fixture('manifest-payload.json');
      final packs = json['packs'] as List<dynamic>;
      final files = (packs.first as Map<String, dynamic>)['files'] as List<dynamic>;
      (files.first as Map<String, dynamic>)['path'] = '../secrets.json';
      expect(() => Manifest.fromJson(json), throwsFormatException);
    });

    test('rejects a non-hex sha256', () {
      final json = _fixture('manifest-payload.json');
      final packs = json['packs'] as List<dynamic>;
      final files = (packs.first as Map<String, dynamic>)['files'] as List<dynamic>;
      (files.first as Map<String, dynamic>)['sha256'] = 'not-a-hash';
      expect(() => Manifest.fromJson(json), throwsFormatException);
    });

    test('requires Arabic in localized text', () {
      final json = _fixture('manifest-payload.json');
      final app = json['app'] as Map<String, dynamic>;
      app['message'] = {'en': 'Update available'};
      expect(() => Manifest.fromJson(json), throwsFormatException);
    });

    test('rejects a signed manifest with no signature', () {
      final json = _fixture('manifest-envelope.json')..['signature'] = '';
      expect(() => SignedManifest.fromJson(json), throwsFormatException);
    });

    test('expiry and active announcements follow the payload times', () {
      final manifest = Manifest.fromJson(_fixture('manifest-payload.json'));
      expect(manifest.isExpiredAt(DateTime.utc(2026, 11, 29)), isFalse);
      expect(manifest.isExpiredAt(DateTime.utc(2026, 12, 1)), isTrue);

      expect(
        manifest.activeAnnouncements(DateTime.utc(2026, 11, 24)),
        hasLength(1),
      );
      expect(
        manifest.activeAnnouncements(DateTime.utc(2026, 12, 2)),
        isEmpty,
      );
    });
  });

  group('remote config (A-02)', () {
    test('applies plan defaults when the manifest sends nothing', () {
      final config = RemoteConfig(const {});
      expect(config.checkIntervalHours, 6);
      expect(config.checkInterval, const Duration(hours: 6));
      expect(config.wifiOnlyDefault, isTrue);
      expect(config.audioEnabled, isTrue);
      expect(config.announcementsEnabled, isTrue);
      expect(config.audioReciters, isNull);
    });

    test('reads the approved keys from a manifest', () {
      final config = RemoteConfig({
        'updates.checkIntervalHours': 12,
        'updates.wifiOnlyDefault': false,
        'features.audio': false,
        'features.announcements': false,
        'audio.reciters': ['hafs'],
      });
      expect(config.checkIntervalHours, 12);
      expect(config.wifiOnlyDefault, isFalse);
      expect(config.audioEnabled, isFalse);
      expect(config.announcementsEnabled, isFalse);
      expect(config.audioReciters, ['hafs']);
    });

    test('ignores unknown keys and mistyped values', () {
      final config = RemoteConfig({
        'unknown.key': true,
        'updates.checkIntervalHours': 0,
        'features.audio': 'yes',
        'audio.reciters': 'hafs',
      });
      expect(config.values, isEmpty);
      expect(config.checkIntervalHours, 6);
      expect(config.audioEnabled, isTrue);
      expect(config.audioReciters, isNull);
    });

    test('rejects an out-of-range interval', () {
      expect(RemoteConfig({'updates.checkIntervalHours': 169}).checkIntervalHours, 6);
      expect(RemoteConfig({'updates.checkIntervalHours': 168}).checkIntervalHours, 168);
      expect(RemoteConfig({'updates.checkIntervalHours': 1}).checkIntervalHours, 1);
    });

    test('the approved key list matches the contract', () {
      expect(configKeys, [
        'updates.checkIntervalHours',
        'updates.wifiOnlyDefault',
        'features.audio',
        'features.announcements',
        'audio.reciters',
      ]);
    });
  });
}

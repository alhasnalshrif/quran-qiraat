import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quran_qiraat/updates/data_source.dart';
import 'package:quran_qiraat/updates/pack_store.dart';
import 'package:quran_qiraat/updates/protocol.dart';

/// A-07: PackStore download, verification, activation, withdrawal and
/// fallback, plus PackedDataSource (03 §4–§5, §9).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  late PackStore store;
  late Map<String, List<int>> files;

  final validPayload = jsonEncode({
    'schema_version': '1.0.0',
    'editions': [
      {
        'id': 'hafs_kfgqpc',
        'reading': 'hafs',
        'name_ar': 'حفص',
        'total_ayahs': 6236,
      },
    ],
  });

  PackRelease release({
    String packId = 'editions-manifest',
    int version = 2,
    String format = 'editions-manifest@1',
    String? content,
    int? sizeOverride,
    String? shaOverride,
  }) {
    final body = content ?? validPayload;
    final bytes = utf8.encode(body);
    files['editions_manifest.json'] = bytes;
    return PackRelease(
      packId: packId,
      version: version,
      format: format,
      files: [
        PackFile(
          path: 'editions_manifest.json',
          url: Uri.parse('https://cdn.example.com/packs/$packId/$version/editions_manifest.json'),
          sha256: shaOverride ?? sha256.convert(bytes).toString(),
          size: sizeOverride ?? bytes.length,
        ),
      ],
    );
  }

  PackStore newStore() => PackStore(
    root: temp,
    fetchFile: (file) async => files[file.path]!,
  );

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('pack_store_test');
    files = {};
    store = newStore();
    await store.load();
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  group('download (A-07)', () {
    test('downloads, verifies sha256 and validates the format', () async {
      final downloaded = await store.download(release());
      expect(downloaded, isNotNull);
      expect(
        File('${downloaded!.directory.path}/editions_manifest.json').existsSync(),
        isTrue,
      );
      expect(store.state.lastError, isNull);
    });

    test('rejects a size mismatch and removes the staging directory', () async {
      final downloaded = await store.download(release(sizeOverride: 3));
      expect(downloaded, isNull);
      expect(store.state.lastError, contains('size mismatch'));
      expect(store.incoming.listSync(), isEmpty);
    });

    test('rejects a bad sha256', () async {
      final downloaded = await store.download(
        release(shaOverride: 'a' * 64),
      );
      expect(downloaded, isNull);
      expect(store.state.lastError, contains('sha256 mismatch'));
    });

    test('rejects a document the format validator refuses', () async {
      final downloaded = await store.download(
        release(content: jsonEncode({'schema_version': '9.0.0', 'editions': []})),
      );
      expect(downloaded, isNull);
      expect(store.state.lastError, contains('validator rejected'));
    });
  });

  group('stage and activate (A-07)', () {
    test('stages a download as pending without activating it', () async {
      final downloaded = await store.download(release());
      await store.stage(downloaded!);

      expect(store.state.pending['editions-manifest'], 2);
      expect(store.activeVersion('editions-manifest'), isNull);
      expect(
        store.versionDirectory('editions-manifest', 2).existsSync(),
        isTrue,
      );
    });

    test('activate moves pending to active and records the previous', () async {
      final v2 = await store.download(release(version: 2));
      await store.stage(v2!);
      await store.activate('editions-manifest');

      expect(store.activeVersion('editions-manifest'), 2);
      expect(store.state.pending, isEmpty);

      final v3 = await store.download(release(version: 3));
      await store.stage(v3!);
      await store.activate('editions-manifest');

      expect(store.activeVersion('editions-manifest'), 3);
      expect(store.previousVersion('editions-manifest'), 2);
    });

    test('keeps at most two versions per pack', () async {
      for (final version in [2, 3, 4]) {
        final download = await store.download(release(version: version));
        await store.stage(download!);
        await store.activate('editions-manifest');
      }

      final directories = store
          .versionDirectory('editions-manifest', 0)
          .parent
          .listSync()
          .whereType<Directory>()
          .map((dir) => dir.path.split(Platform.pathSeparator).last)
          .toSet();
      expect(directories, {'3', '4'});
    });

    test('activatePending activates every staged pack (D8)', () async {
      final v2 = await store.download(release(version: 2));
      await store.stage(v2!);
      await store.activatePending();
      expect(store.activeVersion('editions-manifest'), 2);
    });
  });

  group('withdraw and fallback (A-07)', () {
    test('withdraw returns to the previous version', () async {
      for (final version in [2, 3]) {
        final download = await store.download(release(version: version));
        await store.stage(download!);
        await store.activate('editions-manifest');
      }

      await store.withdraw('editions-manifest');
      expect(store.activeVersion('editions-manifest'), 2);
      expect(store.previousVersion('editions-manifest'), isNull);
    });

    test('withdraw with no previous version returns to bundled', () async {
      final v2 = await store.download(release(version: 2));
      await store.stage(v2!);
      await store.activate('editions-manifest');

      await store.withdraw('editions-manifest');
      expect(store.activeVersion('editions-manifest'), isNull);
    });

    test('markBroken disables the active version and reports a reload', () async {
      final v2 = await store.download(release(version: 2));
      await store.stage(v2!);
      await store.activate('editions-manifest');

      expect(await store.markBroken('editions-manifest'), isTrue);
      expect(store.activeVersion('editions-manifest'), isNull);
      expect(store.state.lastError, contains('failed to load'));
      expect(
        store.versionDirectory('editions-manifest', 2).existsSync(),
        isFalse,
      );
    });

    test('markBroken on a bundled pack reports no reload', () async {
      expect(await store.markBroken('hafs-text'), isFalse);
    });

    test('resetAll disables every downloaded pack', () async {
      final v2 = await store.download(release(version: 2));
      await store.stage(v2!);
      await store.activate('editions-manifest');

      await store.resetAll();
      expect(store.state.active, isEmpty);
      expect(
        store.versionDirectory('editions-manifest', 2).existsSync(),
        isFalse,
      );
    });
  });

  group('state.json (A-07)', () {
    test('is written atomically and reloads', () async {
      final v2 = await store.download(release(version: 2));
      await store.stage(v2!);
      await store.activate('editions-manifest');

      final reloaded = newStore();
      await reloaded.load();
      expect(reloaded.activeVersion('editions-manifest'), 2);
      expect(
        File('${temp.path}/state.json.tmp').existsSync(),
        isFalse,
      );
    });

    test('recovers from a corrupt file instead of crashing', () async {
      await File('${temp.path}/state.json').writeAsString('{not json');
      final reloaded = newStore();
      await reloaded.load();
      expect(reloaded.state.active, isEmpty);
    });

    test('wipes a leftover .incoming directory on start', () async {
      await Directory('${temp.path}/.incoming/partial').create(recursive: true);
      final reloaded = newStore();
      await reloaded.load();
      expect(Directory('${temp.path}/.incoming').existsSync(), isFalse);
    });
  });

  group('PackedDataSource (A-07)', () {
    test('falls back to bundled for every pack without an active version', () async {
      final source = PackedDataSource(store: store);
      final text = await source.loadString('editions-manifest', 'editions_manifest.json');
      expect(text, contains('hafs_kfgqpc'));
      expect(
        source.states['editions-manifest']?.sourceKind,
        PackSourceKind.bundled,
      );
    });

    test('serves the active version once activated', () async {
      final v2 = await store.download(release(version: 2));
      await store.stage(v2!);
      await store.activate('editions-manifest');

      final source = PackedDataSource(store: store);
      final text = await source.loadString('editions-manifest', 'editions_manifest.json');
      expect(text, validPayload);
      expect(source.states['editions-manifest'], const PackState(
        packId: 'editions-manifest',
        version: 2,
        sourceKind: PackSourceKind.downloaded,
      ));

      final bytes = await source.load('editions-manifest', 'editions_manifest.json');
      expect(bytes.lengthInBytes, greaterThan(0));
    });

    test('readActive returns null for a missing file', () async {
      final v2 = await store.download(release(version: 2));
      await store.stage(v2!);
      await store.activate('editions-manifest');
      expect(await store.readActive('editions-manifest', 'missing.json'), isNull);
    });
  });
}

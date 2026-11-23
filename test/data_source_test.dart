import 'package:flutter_test/flutter_test.dart';
import 'package:quran_qiraat/data/quran_repository.dart';
import 'package:quran_qiraat/updates/data_source.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('QuranDataSource and BundledDataSource (A-04)', () {
    const dataSource = BundledDataSource();

    test('BundledDataSource states has 9 packs with version 1', () {
      final states = dataSource.states;
      expect(states.length, 9);
      expect(states['hafs-text']?.version, 1);
      expect(states['hafs-text']?.sourceKind, PackSourceKind.bundled);
      expect(states['qiraat-farsh']?.version, 1);
      expect(states['qiraat-farsh']?.sourceKind, PackSourceKind.bundled);
    });

    test('BundledDataSource loads pack files correctly', () async {
      final manifestJson = await dataSource.loadString(
        'editions-manifest',
        'editions_manifest.json',
      );
      expect(manifestJson, isNotEmpty);
      expect(manifestJson.contains('editions'), isTrue);

      final hafsText = await dataSource.loadString(
        'hafs-text',
        'quran_hafs.json',
      );
      expect(hafsText, isNotEmpty);

      final variantsBytes = await dataSource.load(
        'qiraat-farsh',
        'variants.json',
      );
      expect(variantsBytes.lengthInBytes, greaterThan(0));
    });

    test('throws ArgumentError for unknown packId', () async {
      expect(
        () => dataSource.loadString('unknown-pack', 'test.json'),
        throwsArgumentError,
      );
    });

    test('QuranRepository.load works seamlessly with BundledDataSource', () async {
      final repo = await QuranRepository.load(source: dataSource);
      expect(repo.page(1), isNotEmpty);
      expect(repo.page(604), isNotEmpty);
    });
  });
}

/// Validators for the pack formats in `docs/plan/01-update-protocol.md` §1.2.
///
/// These mirror `packages/contracts/src/formats/*` exactly: the server runs the
/// TypeScript validators on upload, and the app runs these after download and
/// before activation. Each returns the list of problems found; empty means the
/// document is valid.
library;

import 'dart:convert';

const int mushafPageCount = 604;
const int surahCount = 114;

const Set<String> _validLineTypes = {'surah-header', 'basmala', 'text'};
final RegExp _wordLocation = RegExp(r'^\d+:\d+:\d+$');
final RegExp _ayahKey = RegExp(r'^\d+:\d+$');

/// The result of validating one pack document.
class ValidationResult {
  const ValidationResult(this.errors);

  static const ValidationResult valid = ValidationResult([]);

  final List<String> errors;

  bool get ok => errors.isEmpty;
}

ValidationResult _ok() => ValidationResult.valid;

ValidationResult _fail(Iterable<String> errors) =>
    ValidationResult(List.unmodifiable(errors));

/// Decodes [source] as JSON; a decode error is itself a validation failure.
ValidationResult validateFormatJson(String format, String source) {
  final Object? document;
  try {
    document = jsonDecode(source);
  } on FormatException catch (error) {
    return _fail(['invalid JSON: ${error.message}']);
  }
  return validateFormat(format, document);
}

/// Runs the validator for [format]; unknown formats are rejected.
ValidationResult validateFormat(String format, Object? document) {
  switch (format) {
    case 'kfgqpc-ayahs@1':
      return validateKfgqpcAyahs(document);
    case 'mushaf-layout@1':
      return validateMushafLayout(document);
    case 'qiraat-variants@1':
      return validateQiraatVariants(document);
    case 'published-differences@1':
      return validatePublishedDifferences(document);
    case 'ayah-map@1':
      return validateAyahMap(document);
    case 'hizb-starts@1':
      return validateHizbStarts(document);
    case 'editions-manifest@1':
      return validateEditionsManifest(document);
    default:
      return _fail(['unknown format $format']);
  }
}

bool isKnownFormat(String format) => const {
  'kfgqpc-ayahs@1',
  'mushaf-layout@1',
  'qiraat-variants@1',
  'published-differences@1',
  'ayah-map@1',
  'hizb-starts@1',
  'editions-manifest@1',
}.contains(format);

/// `kfgqpc-ayahs@1`: an array of ayahs; each has sura_no 1–114, aya_no ≥ 1 and
/// non-empty aya_text; no duplicated (surah, ayah); the count must match
/// [totalAyahs] when supplied.
ValidationResult validateKfgqpcAyahs(Object? document, {int? totalAyahs}) {
  if (document is! List) return _fail(['expected an array of ayahs']);
  if (document.isEmpty) return _fail(['ayah list is empty']);

  final errors = <String>[];
  final seen = <String>{};

  for (var index = 0; index < document.length; index++) {
    final raw = document[index];
    if (raw is! Map<String, dynamic>) {
      errors.add('ayah ${index + 1} is not an object');
      continue;
    }
    final sura = raw['sura_no'];
    final aya = raw['aya_no'];
    final text = raw['aya_text'];

    if (sura is! int || sura < 1 || sura > surahCount) {
      errors.add('ayah ${index + 1} has an invalid sura_no');
    }
    if (aya is! int || aya < 1) {
      errors.add('ayah ${index + 1} has an invalid aya_no');
    }
    if (text is! String || text.trim().isEmpty) {
      errors.add('ayah ${index + 1} has an empty aya_text');
    }
    if (sura is int && aya is int) {
      final key = '$sura:$aya';
      if (!seen.add(key)) errors.add('duplicate ayah $key');
    }
  }

  if (totalAyahs != null && document.length != totalAyahs) {
    errors.add('expected $totalAyahs ayahs, found ${document.length}');
  }

  return errors.isEmpty ? _ok() : _fail(errors);
}

/// `mushaf-layout@1`: 604 pages, every word location is `s:a:w`, plus the same
/// checks as `tool/import_mushaf_layout.mjs --check`.
ValidationResult validateMushafLayout(Object? document) {
  if (document is! Map<String, dynamic>) {
    return _fail(['expected a layout object']);
  }
  if (document['schemaVersion'] != '1.0.0') {
    return _fail(['unsupported layout schemaVersion']);
  }
  final pages = document['pages'];
  if (pages is! List) return _fail(['pages must be an array']);
  if (pages.length != mushafPageCount) {
    return _fail(['expected $mushafPageCount pages, found ${pages.length}']);
  }

  final errors = <String>[];

  for (var index = 0; index < pages.length; index++) {
    final expectedNumber = index + 1;
    final page = pages[index];
    if (page is! Map<String, dynamic>) {
      errors.add('page $expectedNumber is not an object');
      continue;
    }
    if (page['number'] != expectedNumber) {
      errors.add('expected page $expectedNumber, found ${page['number']}');
    }
    final lines = page['lines'];
    if (lines is! List || lines.isEmpty) {
      errors.add('page $expectedNumber has no lines');
      continue;
    }

    var previousLine = 0;
    final seenLines = <int>{};
    for (var lineIndex = 0; lineIndex < lines.length; lineIndex++) {
      final line = lines[lineIndex];
      if (line is! Map<String, dynamic>) {
        errors.add('page $expectedNumber, entry ${lineIndex + 1} is invalid');
        continue;
      }
      final number = line['number'];
      if (number is! int || number <= previousLine) {
        errors.add(
          'page $expectedNumber, entry ${lineIndex + 1} has a non-monotonic line number',
        );
      } else {
        previousLine = number;
        if (!seenLines.add(number)) {
          errors.add('page $expectedNumber has duplicate line $number');
        }
      }

      final type = line['type'];
      if (type is! String || !_validLineTypes.contains(type)) {
        errors.add('page $expectedNumber, line $number has an invalid type');
        continue;
      }
      if (type == 'text' &&
          (line['text'] is! String || (line['text'] as String).trim().isEmpty)) {
        errors.add('page $expectedNumber, text line $number has empty text');
      }
      if (type != 'text' &&
          line['text'] is! String &&
          line['qpcV1'] is! String &&
          line['qpcV2'] is! String) {
        errors.add(
          'page $expectedNumber, structural line $number has no display data',
        );
      }

      if (type != 'text') continue;
      final words = line['words'];
      if (words is! List || words.isEmpty) {
        errors.add('page $expectedNumber, text line $number has no words');
        continue;
      }
      for (var wordIndex = 0; wordIndex < words.length; wordIndex++) {
        final word = words[wordIndex];
        if (word is! Map<String, dynamic>) {
          errors.add(
            'page $expectedNumber, line $number, word ${wordIndex + 1} is invalid',
          );
          continue;
        }
        final location = word['location'];
        final wordText = word['text'] ?? word['word'];
        if (location is! String || !_wordLocation.hasMatch(location)) {
          errors.add(
            'page $expectedNumber, line $number, word ${wordIndex + 1} has an invalid location',
          );
        } else {
          final surah = int.parse(location.split(':').first);
          if (surah < 1 || surah > surahCount) {
            errors.add(
              'page $expectedNumber, line $number, word ${wordIndex + 1} has an invalid surah',
            );
          }
        }
        if (wordText is! String || wordText.trim().isEmpty) {
          errors.add(
            'page $expectedNumber, line $number, word ${wordIndex + 1} has empty text',
          );
        }
      }
    }
  }

  return errors.isEmpty ? _ok() : _fail(errors);
}

/// `qiraat-variants@1`: ten readers, twenty transmitters, every
/// `junctures[].segments[].ayah` exists in Hafs, and `words` is either null or
/// `[start, end]` with word numbers that exist in the layout.
ValidationResult validateQiraatVariants(
  Object? document, {
  Set<String>? hafsAyahKeys,
  Set<String>? hafsWordLocations,
}) {
  if (document is! Map<String, dynamic>) {
    return _fail(['expected a variants object']);
  }

  final errors = <String>[];

  final readers = document['readers'];
  if (readers is! Map<String, dynamic>) {
    errors.add('readers must be an object');
  } else if (readers.length != 10) {
    errors.add('expected 10 readers, found ${readers.length}');
  } else {
    for (final entry in readers.entries) {
      final reader = entry.value;
      if (reader is! Map<String, dynamic>) {
        errors.add('reader ${entry.key} is not an object');
        continue;
      }
      if (reader['name'] is! String ||
          (reader['name'] as String).trim().isEmpty) {
        errors.add('reader ${entry.key} has no name');
      }
      if (reader['position'] is! int) {
        errors.add('reader ${entry.key} has an invalid position');
      }
    }
  }

  final readerIds = {
    if (readers is Map<String, dynamic>)
      for (final key in readers.keys) int.tryParse(key) ?? -1,
  };

  final transmitters = document['transmitters'];
  if (transmitters is! Map<String, dynamic>) {
    errors.add('transmitters must be an object');
  } else if (transmitters.length != 20) {
    errors.add('expected 20 transmitters, found ${transmitters.length}');
  } else {
    for (final entry in transmitters.entries) {
      final transmitter = entry.value;
      if (transmitter is! Map<String, dynamic>) {
        errors.add('transmitter ${entry.key} is not an object');
        continue;
      }
      if (transmitter['name'] is! String ||
          (transmitter['name'] as String).trim().isEmpty) {
        errors.add('transmitter ${entry.key} has no name');
      }
      if (transmitter['riwayah'] is! String ||
          (transmitter['riwayah'] as String).trim().isEmpty) {
        errors.add('transmitter ${entry.key} has no riwayah');
      }
      final readerId = transmitter['reader'];
      if (readerId is! int || !readerIds.contains(readerId)) {
        errors.add('transmitter ${entry.key} references an unknown reader');
      }
    }
  }

  final junctures = document['junctures'];
  if (junctures is! List) {
    errors.add('junctures must be an array');
    return _fail(errors);
  }
  if (junctures.isEmpty) errors.add('junctures is empty');

  for (var index = 0; index < junctures.length; index++) {
    final juncture = junctures[index];
    if (juncture is! Map<String, dynamic>) {
      errors.add('juncture ${index + 1} is not an object');
      continue;
    }

    final segments = juncture['segments'];
    if (segments is! List || segments.isEmpty) {
      errors.add('juncture ${index + 1} has no segments');
      continue;
    }
    for (var segmentIndex = 0; segmentIndex < segments.length; segmentIndex++) {
      final segment = segments[segmentIndex];
      if (segment is! Map<String, dynamic>) {
        errors.add(
          'juncture ${index + 1} segment ${segmentIndex + 1} is not an object',
        );
        continue;
      }
      final ayah = segment['ayah'];
      if (ayah is! String || !_ayahKey.hasMatch(ayah)) {
        errors.add(
          'juncture ${index + 1} segment ${segmentIndex + 1} has an invalid ayah',
        );
        continue;
      }
      if (hafsAyahKeys != null && !hafsAyahKeys.contains(ayah)) {
        errors.add(
          'juncture ${index + 1} segment ${segmentIndex + 1} references a missing Hafs ayah $ayah',
        );
      }

      final words = segment['words'];
      if (words == null) continue;
      if (words is! List ||
          words.length != 2 ||
          words[0] is! int ||
          words[1] is! int ||
          (words[0] as int) < 1 ||
          (words[1] as int) < (words[0] as int)) {
        errors.add(
          'juncture ${index + 1} segment ${segmentIndex + 1} has invalid words',
        );
        continue;
      }
      if (hafsWordLocations != null) {
        for (var word = words[0] as int; word <= (words[1] as int); word++) {
          if (!hafsWordLocations.contains('$ayah:$word')) {
            errors.add(
              'juncture ${index + 1} segment ${segmentIndex + 1} references a missing layout word $ayah:$word',
            );
          }
        }
      }
    }

    final readings = juncture['readings'];
    if (readings is! List || readings.isEmpty) {
      errors.add('juncture ${index + 1} has no readings');
      continue;
    }
    for (var readingIndex = 0; readingIndex < readings.length; readingIndex++) {
      final reading = readings[readingIndex];
      if (reading is! Map<String, dynamic>) {
        errors.add(
          'juncture ${index + 1} reading ${readingIndex + 1} is not an object',
        );
        continue;
      }
      if (reading['text'] is! String ||
          (reading['text'] as String).trim().isEmpty) {
        errors.add(
          'juncture ${index + 1} reading ${readingIndex + 1} has no text',
        );
      }
      for (final field in ['readers', 'transmitters']) {
        final list = reading[field];
        if (list is! List || list.any((id) => id is! int)) {
          errors.add(
            'juncture ${index + 1} reading ${readingIndex + 1} has an invalid $field list',
          );
        }
      }
    }
  }

  return errors.isEmpty ? _ok() : _fail(errors);
}

/// `published-differences@1`: schema 1.0.0, unique ids, and every record
/// marked reviewed before it may ship in the bundle.
ValidationResult validatePublishedDifferences(Object? document) {
  if (document is! Map<String, dynamic>) {
    return _fail(['expected a published-differences object']);
  }
  if (document['schema_version'] != '1.0.0') {
    return _fail(['unsupported published differences schema']);
  }
  final records = document['records'];
  if (records is! List) return _fail(['records must be an array']);
  if (records.isEmpty) return _ok();

  final errors = <String>[];
  final ids = <String>{};

  for (var index = 0; index < records.length; index++) {
    final record = records[index];
    if (record is! Map<String, dynamic>) {
      errors.add('record ${index + 1} is not an object');
      continue;
    }
    final id = record['id'];
    if (id is! String || id.trim().isEmpty) {
      errors.add('record ${index + 1} has no id');
    } else if (!ids.add(id)) {
      errors.add('duplicate record id $id');
    }

    final status =
        record['review_status'] ?? record['status'] ?? record['is_published'];
    final published =
        status == 'published' ||
        status == 'approved' ||
        status == 'reviewed' ||
        status == true;
    if (!published) {
      errors.add('record ${id ?? index + 1} is not reviewed for publishing');
    }

    for (final field in ['base_span', 'target_span']) {
      final span = record[field];
      if (span is! Map<String, dynamic>) {
        errors.add('record ${id ?? index + 1} has no $field');
        continue;
      }
      for (final key in ['reading', 'ayah', 'start_word', 'end_word', 'text']) {
        if (span[key] == null) {
          errors.add('record ${id ?? index + 1} $field is missing $key');
        }
      }
      final start = span['start_word'];
      final end = span['end_word'];
      if (start is! int || end is! int || start < 1 || end < start) {
        errors.add('record ${id ?? index + 1} $field has an invalid word span');
      }
      if (span['text'] is! String || (span['text'] as String).trim().isEmpty) {
        errors.add('record ${id ?? index + 1} $field has empty text');
      }
    }
  }

  return errors.isEmpty ? _ok() : _fail(errors);
}

/// `ayah-map@1`: version 0.1.0, kufi source, qalun target, and 114 surahs whose
/// ayah entries point at existing target ayahs.
ValidationResult validateAyahMap(Object? document) {
  if (document is! Map<String, dynamic>) {
    return _fail(['expected an ayah-map object']);
  }
  if (document['_version'] != '0.1.0') {
    return _fail(['unsupported ayah map version']);
  }
  if (document['_source'] != 'kufi') return _fail(['unsupported ayah map source']);
  if (document['_rawi'] != 'qalun') return _fail(['unsupported ayah map rawi']);

  final surahs = document['surahs'];
  if (surahs is! Map<String, dynamic>) return _fail(['surahs must be an object']);

  final errors = <String>[];
  if (surahs.length != surahCount) {
    errors.add('expected $surahCount surahs, found ${surahs.length}');
  }

  for (final surahEntry in surahs.entries) {
    final surahNumber = int.tryParse(surahEntry.key);
    if (surahNumber == null || surahNumber < 1 || surahNumber > surahCount) {
      errors.add('invalid surah number ${surahEntry.key}');
      continue;
    }
    final surah = surahEntry.value;
    if (surah is! Map<String, dynamic>) {
      errors.add('surah ${surahEntry.key} is not an object');
      continue;
    }
    final ayahs = surah['ayahs'];
    if (ayahs is! Map<String, dynamic>) {
      errors.add('surah ${surahEntry.key} has no ayahs');
      continue;
    }
    if (ayahs.isEmpty) {
      errors.add('surah ${surahEntry.key} has no ayah entries');
    }
    for (final ayahEntry in ayahs.entries) {
      final ayahNumber = int.tryParse(ayahEntry.key);
      if (ayahNumber == null || ayahNumber < 1) {
        errors.add(
          'surah ${surahEntry.key} has an invalid ayah number ${ayahEntry.key}',
        );
        continue;
      }
      final mapping = ayahEntry.value;
      if (mapping is! Map<String, dynamic>) {
        errors.add(
          'surah ${surahEntry.key} ayah ${ayahEntry.key} is not an object',
        );
        continue;
      }
      final targets = mapping['splits_into'];
      if (targets != null) {
        if (targets is! List ||
            targets.isEmpty ||
            targets.any((value) => value is! int || value < 1)) {
          errors.add(
            'surah ${surahEntry.key} ayah ${ayahEntry.key} has invalid splits_into',
          );
        }
        continue;
      }
      final target = mapping['target_ayah'];
      if (target is! int || target < 1) {
        errors.add(
          'surah ${surahEntry.key} ayah ${ayahEntry.key} has no valid target_ayah',
        );
      }
    }
  }

  return errors.isEmpty ? _ok() : _fail(errors);
}

/// `hizb-starts@1`: exactly 60 distinct hizb starts, each an ayah in Hafs.
ValidationResult validateHizbStarts(
  Object? document, {
  Set<String>? hafsAyahKeys,
}) {
  if (document is! Map<String, dynamic>) {
    return _fail(['expected a hizb-starts object']);
  }
  final starts = document['hizb_starts'];
  if (starts is! List) return _fail(['hizb_starts must be an array']);

  final errors = <String>[];
  if (starts.length != 60) {
    errors.add('expected 60 hizb starts, found ${starts.length}');
  }
  final seen = <String>{};
  for (final raw in starts) {
    if (raw is! String || !_ayahKey.hasMatch(raw)) {
      errors.add('invalid hizb start $raw');
      continue;
    }
    if (!seen.add(raw)) errors.add('duplicate hizb start $raw');
    if (hafsAyahKeys != null && !hafsAyahKeys.contains(raw)) {
      errors.add('hizb start $raw is missing from Hafs');
    }
  }

  return errors.isEmpty ? _ok() : _fail(errors);
}

/// `editions-manifest@1`: schema 1.0.0 with the expected editions and counts.
ValidationResult validateEditionsManifest(Object? document) {
  if (document is! Map<String, dynamic>) {
    return _fail(['expected an editions-manifest object']);
  }
  if (document['schema_version'] != '1.0.0') {
    return _fail(['unsupported editions manifest schema']);
  }
  final editions = document['editions'];
  if (editions is! List || editions.isEmpty) {
    return _fail(['editions must be a non-empty array']);
  }

  final errors = <String>[];
  final ids = <String>{};

  for (var index = 0; index < editions.length; index++) {
    final edition = editions[index];
    if (edition is! Map<String, dynamic>) {
      errors.add('edition ${index + 1} is not an object');
      continue;
    }
    final id = edition['id'];
    if (id is! String || id.trim().isEmpty) {
      errors.add('edition ${index + 1} has no id');
    } else if (!ids.add(id)) {
      errors.add('duplicate edition id $id');
    }
    if (edition['reading'] is! String ||
        (edition['reading'] as String).trim().isEmpty) {
      errors.add('edition ${id ?? index + 1} has no reading');
    }
    if (edition['name_ar'] is! String ||
        (edition['name_ar'] as String).trim().isEmpty) {
      errors.add('edition ${id ?? index + 1} has no name_ar');
    }
    final totalAyahs = edition['total_ayahs'];
    if (totalAyahs is! int || totalAyahs < 1) {
      errors.add('edition ${id ?? index + 1} has an invalid total_ayahs');
    }
  }

  return errors.isEmpty ? _ok() : _fail(errors);
}

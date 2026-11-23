import 'dart:convert';

/// The farsh of the ten readers, as published by Quran Tajweed Engine from the
/// Quran.com (Quran Foundation) qiraat matrix. The app shows it as given: it
/// does not infer, align or reclassify any reading.
class QiraatVariants {
  QiraatVariants({
    required this.readers,
    required this.transmitters,
    required this.junctures,
    required this.revision,
  }) {
    for (final juncture in junctures) {
      for (final segment in juncture.segments) {
        (_byAyah[segment.ayah] ??= []).add(juncture);
        final words = segment.words;
        if (words == null) continue;
        for (var word = words.$1; word <= words.$2; word++) {
          (_byWord['${segment.ayah}:$word'] ??= []).add(juncture);
        }
      }
    }
  }

  factory QiraatVariants.parse(String source) {
    final json = jsonDecode(source) as Map<String, dynamic>;
    final readers = {
      for (final entry in (json['readers'] as Map<String, dynamic>).entries)
        int.parse(entry.key): VariantReader(
          id: int.parse(entry.key),
          name: entry.value['name'] as String,
          position: entry.value['position'] as int,
        ),
    };
    final transmitters = {
      for (final entry
          in (json['transmitters'] as Map<String, dynamic>).entries)
        int.parse(entry.key): VariantTransmitter(
          id: int.parse(entry.key),
          name: entry.value['name'] as String,
          reader: entry.value['reader'] as int,
          riwayah: entry.value['riwayah'] as String,
        ),
    };
    return QiraatVariants(
      readers: readers,
      transmitters: transmitters,
      revision: json['revision'] as String? ?? '',
      junctures: [
        for (final raw in json['junctures'] as List)
          Juncture.fromJson(raw as Map<String, dynamic>),
      ],
    );
  }

  final Map<int, VariantReader> readers;
  final Map<int, VariantTransmitter> transmitters;
  final List<Juncture> junctures;
  final String revision;
  final _byAyah = <String, List<Juncture>>{};
  final _byWord = <String, List<Juncture>>{};

  static const hafs = 'hafs';

  List<Juncture> forAyah(String ayahKey) => _byAyah[ayahKey] ?? const [];

  /// Junctures whose Hafs words include [location] (`surah:ayah:word`).
  List<Juncture> forWord(String location) => _byWord[location] ?? const [];

  /// The twenty riwayat, grouped by imam in canonical order.
  List<VariantTransmitter> get riwayat {
    final list = transmitters.values.toList()
      ..sort((a, b) {
        final byReader =
            (readers[a.reader]?.position ?? 99) -
            (readers[b.reader]?.position ?? 99);
        return byReader != 0 ? byReader : a.id - b.id;
      });
    return list;
  }

  VariantTransmitter? riwayah(String slug) {
    for (final transmitter in transmitters.values) {
      if (transmitter.riwayah == slug) return transmitter;
    }
    return null;
  }

  /// What one riwayah reads at a juncture: a reading naming the transmitter
  /// wins over one naming the whole imam (same rule as the engine).
  VariantReading? readingFor(Juncture juncture, String riwayah) {
    for (final reading in juncture.readings) {
      for (final id in reading.transmitters) {
        if (transmitters[id]?.riwayah == riwayah) return reading;
      }
    }
    for (final reading in juncture.readings) {
      for (final readerId in reading.readers) {
        for (final transmitter in transmitters.values) {
          if (transmitter.reader == readerId &&
              transmitter.riwayah == riwayah) {
            return reading;
          }
        }
      }
    }
    return null;
  }

  /// Whether [riwayah] reads this juncture differently from Hafs.
  bool differsFromHafs(Juncture juncture, String riwayah) {
    final own = readingFor(juncture, riwayah);
    final base = readingFor(juncture, hafs);
    return own != null && base != null && !identical(own, base);
  }

  /// Who reads a form: imams in canonical order, then lone transmitters with
  /// their imam in parentheses.
  String attribution(VariantReading reading) {
    final imams = [for (final id in reading.readers) ?readers[id]]
      ..sort((a, b) => a.position - b.position);
    final lone = [for (final id in reading.transmitters) ?transmitters[id]]
      ..sort((a, b) {
        final byReader =
            (readers[a.reader]?.position ?? 99) -
            (readers[b.reader]?.position ?? 99);
        return byReader != 0 ? byReader : a.id - b.id;
      });
    return [
      ...imams.map((imam) => imam.name),
      ...lone.map(
        (transmitter) =>
            '${transmitter.name} (${readers[transmitter.reader]?.name ?? ''})',
      ),
    ].join('، ');
  }
}

class VariantReader {
  const VariantReader({
    required this.id,
    required this.name,
    required this.position,
  });

  final int id;
  final String name;
  final int position;
}

class VariantTransmitter {
  const VariantTransmitter({
    required this.id,
    required this.name,
    required this.reader,
    required this.riwayah,
  });

  final int id;
  final String name;
  final int reader;

  /// Engine slug, e.g. `shubah`, `qaloon`, `warsh`.
  final String riwayah;
}

class Juncture {
  const Juncture({
    required this.word,
    required this.segments,
    required this.readings,
  });

  factory Juncture.fromJson(Map<String, dynamic> json) => Juncture(
    word: json['word'] as String,
    segments: [
      for (final raw in json['segments'] as List)
        JunctureSegment(
          ayah: (raw as Map<String, dynamic>)['ayah'] as String,
          words: switch (raw['words']) {
            [final int start, final int end] => (start, end),
            _ => null,
          },
        ),
    ],
    readings: [
      for (final raw in json['readings'] as List)
        VariantReading(
          text: (raw as Map<String, dynamic>)['text'] as String,
          readers: List<int>.from(raw['readers'] as List),
          transmitters: List<int>.from(raw['transmitters'] as List),
        ),
    ],
  );

  /// The Hafs words at issue.
  final String word;
  final List<JunctureSegment> segments;
  final List<VariantReading> readings;

  /// Layout word locations (`surah:ayah:word`) covered by this juncture.
  Iterable<String> get locations sync* {
    for (final segment in segments) {
      final words = segment.words;
      if (words == null) continue;
      for (var word = words.$1; word <= words.$2; word++) {
        yield '${segment.ayah}:$word';
      }
    }
  }
}

class JunctureSegment {
  const JunctureSegment({required this.ayah, required this.words});

  final String ayah;

  /// First and last layout word numbers, or null when the source could not
  /// place the word (then it is shown at ayah level, untinted).
  final (int, int)? words;
}

class VariantReading {
  const VariantReading({
    required this.text,
    required this.readers,
    required this.transmitters,
  });

  final String text;
  final List<int> readers;
  final List<int> transmitters;
}

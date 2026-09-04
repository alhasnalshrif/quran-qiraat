import 'dart:convert';

enum MushafLayoutLineType { surahHeader, basmala, text }

class MushafLayoutWord {
  const MushafLayoutWord({
    required this.location,
    required this.text,
    this.qpcV1,
    this.qpcV2,
  });

  final String location;
  final String text;
  final String? qpcV1;
  final String? qpcV2;

  factory MushafLayoutWord.fromJson(Map<String, dynamic> json) =>
      MushafLayoutWord(
        location: json['location'] as String,
        text: json['text'] as String,
        qpcV1: json['qpcV1'] as String?,
        qpcV2: json['qpcV2'] as String?,
      );
}

class MushafLayoutLine {
  const MushafLayoutLine({
    required this.number,
    required this.type,
    this.text,
    this.verseRange,
    this.surah,
    this.qpcV1,
    this.qpcV2,
    this.words = const [],
  });

  final int number;
  final MushafLayoutLineType type;
  final String? text;
  final String? verseRange;
  final Object? surah;
  final String? qpcV1;
  final String? qpcV2;
  final List<MushafLayoutWord> words;

  String get displayText => text ?? '';

  factory MushafLayoutLine.fromJson(Map<String, dynamic> json) {
    final type = switch (json['type']) {
      'surah-header' => MushafLayoutLineType.surahHeader,
      'basmala' => MushafLayoutLineType.basmala,
      'text' => MushafLayoutLineType.text,
      final value => throw FormatException('Unknown Mushaf line type: $value'),
    };
    final text = json['text'] as String?;
    final words = [
      for (final word in (json['words'] as List<dynamic>? ?? []))
        MushafLayoutWord.fromJson(word as Map<String, dynamic>),
    ];
    if (type == MushafLayoutLineType.text &&
        (text == null || text.isEmpty || words.isEmpty)) {
      throw const FormatException(
        'A text line must include text and source words.',
      );
    }
    if (type != MushafLayoutLineType.text &&
        text == null &&
        json['qpcV1'] == null &&
        json['qpcV2'] == null) {
      throw const FormatException(
        'A structural line must include display data.',
      );
    }
    return MushafLayoutLine(
      number: json['number'] as int,
      type: type,
      text: text,
      verseRange: json['verseRange'] as String?,
      surah: json['surah'],
      qpcV1: json['qpcV1'] as String?,
      qpcV2: json['qpcV2'] as String?,
      words: words,
    );
  }
}

class MushafLayoutPage {
  const MushafLayoutPage({required this.number, required this.lines});

  final int number;
  final List<MushafLayoutLine> lines;

  factory MushafLayoutPage.fromJson(Map<String, dynamic> json) {
    final lines = [
      for (final line in json['lines'] as List<dynamic>)
        MushafLayoutLine.fromJson(line as Map<String, dynamic>),
    ];
    if (lines.isEmpty) {
      throw const FormatException('A Mushaf page cannot be empty.');
    }
    var previous = 0;
    for (final line in lines) {
      if (line.number <= previous) {
        throw const FormatException('Mushaf line numbers must increase.');
      }
      previous = line.number;
    }
    return MushafLayoutPage(number: json['number'] as int, lines: lines);
  }
}

class MushafLayout {
  const MushafLayout({
    required this.editionId,
    required this.pages,
    required this.sourceCommit,
  });

  final String editionId;
  final List<MushafLayoutPage> pages;
  final String sourceCommit;

  MushafLayoutPage? page(int number) =>
      number > 0 && number <= pages.length ? pages[number - 1] : null;

  factory MushafLayout.fromJsonString(String source) {
    final json = jsonDecode(source) as Map<String, dynamic>;
    if (json['schemaVersion'] != '1.0.0') {
      throw FormatException(
        'Unsupported Mushaf layout schema: ${json['schemaVersion']}',
      );
    }
    final pages = [
      for (final page in json['pages'] as List<dynamic>)
        MushafLayoutPage.fromJson(page as Map<String, dynamic>),
    ];
    if (pages.length != 604) {
      throw FormatException(
        'Expected 604 Mushaf pages, found ${pages.length}.',
      );
    }
    for (var index = 0; index < pages.length; index++) {
      if (pages[index].number != index + 1) {
        throw FormatException(
          'Expected page ${index + 1}, found ${pages[index].number}.',
        );
      }
    }
    return MushafLayout(
      editionId: json['editionId'] as String,
      pages: pages,
      sourceCommit:
          (json['source'] as Map<String, dynamic>)['commit'] as String,
    );
  }
}

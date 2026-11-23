import 'margin_riwayah.dart';

/// Uniquely refers to a single word within a specific reading's numbering.
class ReadingWordRef {
  const ReadingWordRef({
    required this.reading,
    required this.surah,
    required this.ayah,
    required this.wordIndex,
    this.text,
  }) : assert(surah > 0 && surah <= 114),
       assert(ayah > 0),
       assert(wordIndex > 0);

  final QuranReading reading;
  final int surah;
  final int ayah;
  final int wordIndex;
  final String? text;

  String get ayahKey => '$surah:$ayah';

  factory ReadingWordRef.fromJson(Map<String, dynamic> json) {
    final readingName = json['reading'] as String;
    final reading = _parseReading(readingName);
    final ref = ReadingWordRef(
      reading: reading,
      surah: json['surah'] as int,
      ayah: json['ayah'] as int,
      wordIndex: json['word_index'] as int,
      text: json['text'] as String?,
    );
    if (ref.surah < 1 || ref.surah > 114 || ref.ayah < 1 || ref.wordIndex < 1) {
      throw const FormatException('Invalid reading word reference.');
    }
    return ref;
  }

  Map<String, dynamic> toJson() => {
    'reading': reading.name,
    'surah': surah,
    'ayah': ayah,
    'word_index': wordIndex,
    if (text != null) 'text': text,
  };
}

/// Represents a contiguous sequence of words within an ayah for a specific reading.
///
/// This avoids unsafe assumption that ayah numbering, page lines, or word boundaries
/// are identical across different Quran readings.
class ReadingWordSpan {
  const ReadingWordSpan({
    required this.reading,
    required this.surah,
    required this.ayah,
    required this.startWordIndex,
    required this.endWordIndex,
    required this.text,
  }) : assert(surah > 0 && surah <= 114),
       assert(ayah > 0),
       assert(startWordIndex > 0),
       assert(
         endWordIndex >= startWordIndex,
         'endWordIndex must be >= startWordIndex',
       );

  final QuranReading reading;
  final int surah;
  final int ayah;
  final int startWordIndex;
  final int endWordIndex;
  final String text;

  int get wordCount => endWordIndex - startWordIndex + 1;
  bool get isSingleWord => wordCount == 1;
  String get ayahKey => '$surah:$ayah';

  bool containsWord(int index) =>
      index >= startWordIndex && index <= endWordIndex;

  void validate() {
    if (surah < 1 ||
        surah > 114 ||
        ayah < 1 ||
        startWordIndex < 1 ||
        endWordIndex < startWordIndex ||
        text.trim().isEmpty) {
      throw const FormatException('Invalid reading word span.');
    }
  }

  factory ReadingWordSpan.singleWord({
    required QuranReading reading,
    required int surah,
    required int ayah,
    required int wordIndex,
    required String text,
  }) => ReadingWordSpan(
    reading: reading,
    surah: surah,
    ayah: ayah,
    startWordIndex: wordIndex,
    endWordIndex: wordIndex,
    text: text,
  );

  factory ReadingWordSpan.fromJson(Map<String, dynamic> json) {
    final readingName = json['reading'] as String;
    final reading = _parseReading(readingName);
    final span = ReadingWordSpan(
      reading: reading,
      surah: json['surah'] as int,
      ayah: json['ayah'] as int,
      startWordIndex: json['start_word_index'] as int,
      endWordIndex: json['end_word_index'] as int,
      text: json['text'] as String,
    );
    span.validate();
    return span;
  }

  Map<String, dynamic> toJson() => {
    'reading': reading.name,
    'surah': surah,
    'ayah': ayah,
    'start_word_index': startWordIndex,
    'end_word_index': endWordIndex,
    'text': text,
  };
}

QuranReading _parseReading(String name) {
  for (final reading in QuranReading.values) {
    if (reading.name == name) return reading;
  }
  throw FormatException('Unknown Quran reading: $name');
}

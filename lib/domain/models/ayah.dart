class Ayah {
  const Ayah({
    required this.surah,
    required this.number,
    required this.page,
    required this.text,
    required this.comparisonText,
    this.surahName = '',
    this.lineStart = 1,
    this.lineEnd = 1,
  });

  final int surah;
  final int number;
  final int? page;
  final String text;
  final String comparisonText;
  final String surahName;
  final int lineStart;
  final int lineEnd;

  String get key => '$surah:$number';

  factory Ayah.fromJson(Map<String, dynamic> json, {required bool isHafs}) =>
      Ayah(
        surah: json['sura_no'] as int,
        number: json['aya_no'] as int,
        page: int.tryParse('${json['page']}'),
        text: json['aya_text'] as String,
        comparisonText:
            (isHafs ? json['aya_text_emlaey'] : json['aya_text']) as String,
        surahName: '${json['sura_name_ar'] ?? ''}',
        lineStart: int.tryParse('${json['line_start']}') ?? 1,
        lineEnd: int.tryParse('${json['line_end']}') ?? 1,
      );
}

part of 'mushaf_reader_page.dart';

class _ReviewedDifferenceCard extends StatelessWidget {
  const _ReviewedDifferenceCard({
    required this.difference,
    required this.primaryReading,
    this.compact = false,
  });

  final ReadingDifference difference;
  final QuranReading primaryReading;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final forward = difference.baseReading == primaryReading;
    final first = forward ? difference.baseSpan : difference.targetSpan;
    final second = forward ? difference.targetSpan : difference.baseSpan;
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: EdgeInsets.all(compact ? 6 : 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'الآية ${first.surah}:${first.ayah}',
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (difference.isOneToMany) const Text('محاذاة ١:N'),
            if (difference.isManyToOne) const Text('محاذاة N:١'),
            const SizedBox(height: 8),
            Text(
              '${first.reading.shortTitle}: ${first.text}',
              style: TextStyle(
                fontFamily: first.reading.unicodeFontFamily,
                fontSize: compact ? 18 : 22,
              ),
            ),
            Text(
              '${second.reading.shortTitle}: ${second.text}',
              style: TextStyle(
                fontFamily: second.reading.unicodeFontFamily,
                fontSize: compact ? 16 : 18,
                color: _readingColor(
                  context,
                  _differenceRed,
                  _differenceNightRed,
                ),
              ),
            ),
            if (difference.isPerformanceOnly) const Text('اختلاف أداء أو رسم'),
            if (difference.scholarlyNotes case final notes?) Text(notes),
            const SizedBox(height: 6),
            Text(
              'المراجع: ${difference.reviewer}\nتاريخ الاعتماد: ${difference.reviewDate!.toIso8601String().split('T').first}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

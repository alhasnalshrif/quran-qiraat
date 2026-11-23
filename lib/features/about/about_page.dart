import 'package:flutter/material.dart';

import '../../app/quran_theme.dart';

/// `/about` — every data source and its licence (04 §1), so the app ships an
/// honest attribution page instead of a licence file nobody reads.
class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  static const List<DataSource> sources = [
    DataSource(
      name: 'نص حفص',
      origin: 'مجمع الملك فهد لطباعة المصحف الشريف (KFGQPC)',
      licence: 'شروط المجمع',
      path: 'assets/quran_hafs.json',
      note: 'يُستخدم كما هو دون تعديل.',
    ),
    DataSource(
      name: 'تخطيط مصحف المدينة 1405هـ',
      origin: 'zonetecde/mushaf-layout',
      licence: 'ISC',
      path: 'assets/mushaf/layout/',
      note: '604 صفحات، 15 سطرًا، من commit مثبّت في manifest.json.',
    ),
    DataSource(
      name: 'نص شعبة وقالون',
      origin: 'مجمع الملك فهد لطباعة المصحف الشريف (KFGQPC)',
      licence: 'شروط المجمع',
      path: 'assets/quran_shubah.json · assets/quran_qalun.json',
    ),
    DataSource(
      name: 'ربط آيات حفص بقالون',
      origin: 'مضمّن في المشروع',
      licence: 'QIRAAT_AYAH_MAP_LICENSE.txt',
      path: 'assets/mappings/hafs_to_qalun.json',
    ),
    DataSource(
      name: 'فرش القراءات العشر',
      origin: 'Quran Tajweed Engine (عن مصفوفة Quran.com)',
      licence: 'MIT + شروط Quran.com للنصوص الإنجليزية',
      path: 'assets/qiraat/',
      note: 'يُعرض كما ورد، بلا محاذاة آلية ولا تعليل (القاعدة 1).',
    ),
    DataSource(
      name: 'بدايات الأحزاب',
      origin: 'quran-center/quran-meta',
      licence: 'MIT',
      path: 'assets/navigation/',
    ),
    DataSource(
      name: 'خط أميري قرآن',
      origin: 'Amiri Project',
      licence: 'OFL 1.1',
      path: 'assets/fonts/amiri_quran.ttf',
    ),
    DataSource(
      name: 'خط نوتو سانس عربي',
      origin: 'Google Noto',
      licence: 'OFL 1.1',
      path: 'assets/fonts/noto_sans_arabic.ttf',
    ),
  ];

  /// What was reviewed and rejected, kept visible for honesty (04 §1).
  static const List<String> rejected = [
    'فواصل الأسطر من المصدر: أرقامها ليست مواضع كلمات، فلا يُبنى عليها تخطيط.',
    'فهرس المواضع الآلي: مبني على مقارنة آلية ويشمل فروق الرسم.',
    'ترجمات وشروح الفرش الإنجليزية: المصدر يطلب إذن مؤسسة القرآن قبل النشر.',
    'سجلات التيسير المرشحة: غير مراجعة، ولا تُعرض.',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('حول التطبيق والمصادر')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          QuranDesign.gutter,
          QuranDesign.gap,
          QuranDesign.gutter,
          QuranDesign.section,
        ),
        children: [
          Text('مصحف القراءات', style: theme.textTheme.titleLarge),
          const SizedBox(height: QuranDesign.gap),
          Text(
            'يعرض نص حفص وتخطيط صفحاته، وفرش القراءات العشر في الهامش، وروايتي شعبة وقالون. '
            'كل ما يُعرض هنا من مصدر منشور كما هو، بلا اجتهاد ولا محاذاة آلية تُعرض كفرق.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: QuranDesign.section),
          Text('المصادر والرخص', style: theme.textTheme.titleMedium),
          const SizedBox(height: QuranDesign.gap),
          for (final source in sources) _SourceTile(source: source),
          const SizedBox(height: QuranDesign.section),
          Text('ما رُفض ولماذا', style: theme.textTheme.titleMedium),
          const SizedBox(height: QuranDesign.gap),
          for (final reason in rejected)
            Padding(
              padding: const EdgeInsets.only(bottom: QuranDesign.gap),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('•  ', style: theme.textTheme.bodyMedium),
                  Expanded(child: Text(reason, style: theme.textTheme.bodySmall)),
                ],
              ),
            ),
          const SizedBox(height: QuranDesign.section),
          Text('الخصوصية', style: theme.textTheme.titleMedium),
          const SizedBox(height: QuranDesign.gap),
          Text(
            'لا حسابات ولا تتبع. طلب التحديث يحمل المنصة ورقم النسخة والقناة فقط. '
            'لا تُحفظ عناوين الشبكة كاملة.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

/// One row of the source table.
class DataSource {
  const DataSource({
    required this.name,
    required this.origin,
    required this.licence,
    required this.path,
    this.note,
  });

  final String name;
  final String origin;
  final String licence;
  final String path;
  final String? note;
}

class _SourceTile extends StatelessWidget {
  const _SourceTile({required this.source});

  final DataSource source;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: QuranDesign.section),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(source.name, style: theme.textTheme.bodyLarge),
          const SizedBox(height: 2),
          Text(source.origin, style: theme.textTheme.bodySmall),
          const SizedBox(height: 2),
          Text(
            'الرخصة: ${source.licence}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
          if (source.note != null) ...[
            const SizedBox(height: 2),
            Text(source.note!, style: theme.textTheme.bodySmall),
          ],
          const SizedBox(height: 2),
          Text(
            source.path,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
            textDirection: TextDirection.ltr,
          ),
        ],
      ),
    );
  }
}

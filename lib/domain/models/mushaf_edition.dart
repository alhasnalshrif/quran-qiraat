import 'margin_riwayah.dart';

class MushafEdition {
  const MushafEdition({
    required this.id,
    required this.reading,
    required this.nameAr,
    required this.source,
    required this.version,
    required this.isPageLayoutCapable,
    this.targetPageLayout,
    this.supportsPageNavigation = false,
    required this.isTextComparisonCapable,
    required this.totalAyahs,
    this.pageCount,
    required this.fontFamily,
    this.notes = '',
  });

  final String id;
  final QuranReading reading;
  final String nameAr;
  final String source;
  final String version;

  /// True only when a vetted, bundled, renderer-usable word/line layout package
  /// is present and active. This does not imply pixel-identical page fonts.
  final bool isPageLayoutCapable;

  /// The intended/target page layout architecture (e.g. "madani_604").
  final String? targetPageLayout;

  /// Whether the edition supports page-based reading/navigation containers.
  final bool supportsPageNavigation;

  final bool isTextComparisonCapable;
  final int totalAyahs;
  final int? pageCount;
  final String fontFamily;
  final String notes;

  factory MushafEdition.fromJson(Map<String, dynamic> json) {
    final readingName = json['reading'] as String;
    final reading = QuranReading.values.firstWhere(
      (r) => r.name == readingName,
      orElse: () =>
          throw FormatException('Unknown Quran reading: $readingName'),
    );

    return MushafEdition(
      id: json['id'] as String,
      reading: reading,
      nameAr: json['name_ar'] as String,
      source: json['source'] as String? ?? '',
      version: json['version'] as String? ?? '1.0.0',
      isPageLayoutCapable: json['is_page_layout_capable'] as bool? ?? false,
      targetPageLayout: json['target_page_layout'] as String?,
      supportsPageNavigation:
          json['supports_page_navigation'] as bool? ?? false,
      isTextComparisonCapable:
          json['is_text_comparison_capable'] as bool? ?? true,
      totalAyahs: json['total_ayahs'] as int? ?? 6236,
      pageCount: json['page_count'] as int?,
      fontFamily: json['font_family'] as String? ?? reading.fontFamily,
      notes: json['notes'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'reading': reading.name,
    'name_ar': nameAr,
    'source': source,
    'version': version,
    'is_page_layout_capable': isPageLayoutCapable,
    if (targetPageLayout != null) 'target_page_layout': targetPageLayout,
    'supports_page_navigation': supportsPageNavigation,
    'is_text_comparison_capable': isTextComparisonCapable,
    'total_ayahs': totalAyahs,
    'page_count': pageCount,
    'font_family': fontFamily,
    'notes': notes,
  };
}

class CandidateSourceMetadata {
  const CandidateSourceMetadata({
    required this.id,
    required this.nameAr,
    required this.file,
    required this.status,
    this.notes = '',
  });

  final String id;
  final String nameAr;
  final String file;
  final String status;
  final String notes;

  factory CandidateSourceMetadata.fromJson(Map<String, dynamic> json) =>
      CandidateSourceMetadata(
        id: json['id'] as String,
        nameAr: json['name_ar'] as String? ?? '',
        file: json['file'] as String? ?? '',
        status: json['status'] as String? ?? 'candidate_unreviewed',
        notes: json['notes'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name_ar': nameAr,
    'file': file,
    'status': status,
    'notes': notes,
  };
}

class MushafManifest {
  const MushafManifest({
    required this.schemaVersion,
    required this.generatedAt,
    this.description = '',
    required this.editions,
    this.candidateSources = const [],
  });

  final String schemaVersion;
  final String generatedAt;
  final String description;
  final List<MushafEdition> editions;
  final List<CandidateSourceMetadata> candidateSources;

  MushafEdition? editionFor(QuranReading reading) {
    for (final edition in editions) {
      if (edition.reading == reading) return edition;
    }
    return null;
  }

  bool isLayoutCapable(QuranReading reading) =>
      editionFor(reading)?.isPageLayoutCapable ?? false;

  bool supportsPageNavigation(QuranReading reading) =>
      editionFor(reading)?.supportsPageNavigation ?? false;

  factory MushafManifest.fromJson(Map<String, dynamic> json) => MushafManifest(
    schemaVersion: json['schema_version'] as String? ?? '1.0.0',
    generatedAt: json['generated_at'] as String? ?? '',
    description: json['description'] as String? ?? '',
    editions: [
      for (final item in (json['editions'] as List<dynamic>? ?? []))
        MushafEdition.fromJson(item as Map<String, dynamic>),
    ],
    candidateSources: [
      for (final item in (json['candidate_sources'] as List<dynamic>? ?? []))
        CandidateSourceMetadata.fromJson(item as Map<String, dynamic>),
    ],
  );

  static const bundledDefault = MushafManifest(
    schemaVersion: '1.0.0',
    generatedAt: '2026-09-05',
    description: 'البيان الافتراضي للمصاحف والروايات المضمنة',
    editions: [
      MushafEdition(
        id: 'hafs_kfgqpc',
        reading: QuranReading.hafs,
        nameAr: 'حفص عن عاصم',
        source: 'مجمع الملك فهد لطباعة المصحف الشريف',
        version: '1.0.0',
        isPageLayoutCapable: true,
        targetPageLayout: 'madani_604',
        supportsPageNavigation: true,
        isTextComparisonCapable: true,
        totalAyahs: 6236,
        pageCount: 604,
        fontFamily: 'HafsSmart',
        notes: 'نسخة حفص ذات تخطيط أسطر موثق من 604 صفحات ومحمل محلياً. يستخدم عرض Unicode مقروءاً إلى حين إضافة خط QCF مرخص ومتحقق منه للمطابقة الطباعية التامة.',
      ),
      MushafEdition(
        id: 'shubah_kfgqpc',
        reading: QuranReading.shubah,
        nameAr: 'شعبة عن عاصم',
        source: 'مجمع الملك فهد لطباعة المصحف الشريف',
        version: '1.0.0',
        isPageLayoutCapable: false,
        targetPageLayout: null,
        supportsPageNavigation: false,
        isTextComparisonCapable: true,
        totalAyahs: 6236,
        fontFamily: 'Shubah',
        notes: 'نص رواية شعبة عن عاصم مخصص للمقارنة النصية فقط؛ لا يُدعى له مطابقة تخطيط صفحات مصحف حفص.',
      ),
      MushafEdition(
        id: 'qalun_kfgqpc',
        reading: QuranReading.qalun,
        nameAr: 'قالون عن نافع',
        source: 'مجمع الملك فهد لطباعة المصحف الشريف',
        version: '1.0.0',
        isPageLayoutCapable: false,
        targetPageLayout: null,
        supportsPageNavigation: false,
        isTextComparisonCapable: true,
        totalAyahs: 6214,
        fontFamily: 'Qalun',
        notes: 'نص رواية قالون عن نافع مخصص للمقارنة النصية فقط؛ يستخدم العد المدني في حزمة KFGQPC (6214 آية).',
      ),
    ],
    candidateSources: [
      CandidateSourceMetadata(
        id: 'taisir_review_queue',
        nameAr: 'بيانات التيسير للداني (Corpus Coranicum)',
        file: 'assets/taisir_review_queue.json',
        status: 'candidate_unreviewed',
        notes: 'بيانات أولية مرشحة للاختبار والتطوير الداخلي فقط.',
      ),
    ],
  );
}

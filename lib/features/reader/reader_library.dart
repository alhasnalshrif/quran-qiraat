import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/quran_theme.dart';
import '../../data/quran_repository.dart';
import '../../domain/models/ayah.dart';
import '../../domain/models/margin_riwayah.dart';
import 'reading_text_comparison_page.dart';
import 'page_input.dart';
import 'reader_library_store.dart';
import 'quran_navigation_index.dart';
export 'reader_library_store.dart';
export 'quran_navigation_index.dart';

class ReaderLibraryPage extends StatefulWidget {
  const ReaderLibraryPage({
    super.key,
    required this.index,
    required this.store,
    required this.current,
    this.initialTab = 0,
    this.searchReading,
  });
  final QuranNavigationIndex index;
  final ReaderLibraryStore store;
  final ReaderLocation current;
  final int initialTab;
  final QuranReading? searchReading;
  @override
  State<ReaderLibraryPage> createState() => _ReaderLibraryPageState();
}

class _ReaderLibraryPageState extends State<ReaderLibraryPage> {
  final _query = TextEditingController();
  late final Future<List<Ayah>> _hizbs = widget.index.hizbs();
  int _section = 0;
  late QuranReading _searchReading =
      widget.searchReading ?? widget.current.reading;
  List<Ayah> _results = [];

  void _showStatus(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<void> _copyBackup() async {
    try {
      await Clipboard.setData(
        ClipboardData(text: widget.store.exportBookmarks()),
      );
      _showStatus('تم نسخ العلامات والملاحظات. احفظ النص لاستعادته لاحقًا.');
    } catch (_) {
      _showStatus('تعذر النسخ');
    }
  }

  Future<void> _importBackup() async {
    var input = '';
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: const Text('استيراد العلامات'),
        content: TextField(
          onChanged: (value) => input = value,
          minLines: 3,
          maxLines: 6,
          decoration: const InputDecoration(
            labelText: 'الصق نص النسخة الاحتياطية',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('استيراد'),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted) return;
    try {
      final count = await widget.store.importBookmarks(
        input,
        isValidLocation: widget.index.valid,
      );
      _showStatus(
        count == 0
            ? 'لا توجد علامات جديدة في النسخة'
            : 'تمت إضافة $count علامة',
      );
    } on FormatException {
      _showStatus('نص النسخة الاحتياطية غير صالح');
    } catch (_) {
      _showStatus('تعذر حفظ العلامات المستوردة');
    }
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _open(Ayah ayah) =>
      Navigator.pop(context, widget.index.locate(ayah.surah, ayah.number));
  String _label(ReaderLocation location) =>
      '${widget.index.name(location.surah)} • آية ${location.ayah}${location.word == null ? '' : ' • كلمة ${location.word}'}'
      '${location.reading == QuranReading.hafs ? '' : ' • ${location.reading.shortTitle}'}';
  Future<void> _direct() async {
    final surah = TextEditingController(), ayah = TextEditingController();
    String? error;
    final location = await showDialog<ReaderLocation>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('الانتقال إلى آية'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: surah,
                autofocus: true,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'رقم السورة'),
              ),
              TextField(
                controller: ayah,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'رقم الآية',
                  errorText: error,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () {
                final s = parseMushafPage(surah.text, pageCount: 114),
                    a = parseMushafPage(ayah.text, pageCount: 286);
                final location = s == null || a == null
                    ? null
                    : widget.index.locate(s, a);
                if (location == null) {
                  update(() => error = 'أدخل رقم سورة وآية موجودين');
                  return;
                }
                Navigator.pop(context, location);
              },
              child: const Text('انتقال'),
            ),
          ],
        ),
      ),
    );
    // The dialog route may still be animating out when its result completes.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    surah.dispose();
    ayah.dispose();
    if (mounted && location != null) Navigator.pop(context, location);
  }

  Future<void> _saveCurrent({ReaderBookmark? bookmark}) async {
    final location = bookmark?.location ?? widget.current;
    final existing = widget.store.bookmarks.where(
      (b) => b.location.key == location.key,
    );
    final controller = TextEditingController(
      text: bookmark?.note ?? (existing.isEmpty ? '' : existing.first.note),
    );
    final note = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حفظ علامة مرجعية'),
        content: TextField(
          controller: controller,
          maxLines: 4,
          maxLength: 2000,
          decoration: const InputDecoration(labelText: 'ملاحظة اختيارية'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));
    controller.dispose();
    if (note == null) return;
    try {
      await widget.store.save(location, note);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر حفظ العلامة. حاول مرة أخرى.')),
        );
      }
    }
  }

  Future<void> _deleteBookmark(ReaderBookmark bookmark) async {
    try {
      await widget.store.remove(bookmark.location);
    } catch (_) {
      _showStatus('تعذر حذف العلامة');
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('حُذفت العلامة'),
        action: SnackBarAction(
          label: 'تراجع',
          onPressed: () async {
            if (widget.store.bookmarks.any(
              (saved) => saved.location.key == bookmark.location.key,
            )) {
              return;
            }
            try {
              await widget.store.save(bookmark.location, bookmark.note);
            } catch (_) {
              _showStatus('تعذر استعادة العلامة');
            }
          },
        ),
      ),
    );
  }

  TextSpan _searchResult(String source) {
    final query = normalizeQuranSearch(_query.text);
    final tokens = <(int, int, int, int)>[];
    final searchable = StringBuffer();
    for (final word in RegExp(r'\S+').allMatches(source)) {
      final normalized = normalizeQuranSearch(
        QuranRepository.comparableReadingText(word[0]!),
      );
      if (normalized.isEmpty) continue;
      if (searchable.isNotEmpty) searchable.write(' ');
      final start = searchable.length;
      searchable.write(normalized);
      tokens.add((word.start, word.end, start, searchable.length));
    }
    final match = query.isEmpty ? -1 : searchable.toString().indexOf(query);
    if (match < 0) return TextSpan(text: source);
    final first = tokens.firstWhere((token) => token.$4 > match).$1;
    final last = tokens
        .lastWhere((token) => token.$3 < match + query.length)
        .$2;
    final colors = Theme.of(context).colorScheme;
    return TextSpan(
      children: [
        TextSpan(text: source.substring(0, first)),
        TextSpan(
          text: source.substring(first, last),
          style: TextStyle(
            backgroundColor: colors.primaryContainer,
            color: colors.onPrimaryContainer,
          ),
        ),
        TextSpan(text: source.substring(last)),
      ],
    );
  }

  Widget _ayahTile(Ayah ayah, {String? title, int? surahNumber}) {
    final page = widget.index.locate(ayah.surah, ayah.number)?.page;
    final currentSurah = surahNumber == widget.current.surah;
    final colors = Theme.of(context).colorScheme;
    final largeText = MediaQuery.textScalerOf(context).scale(14) > 21;
    return Column(
      children: [
        ListTile(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(QuranDesign.controlRadius),
          ),
          minTileHeight: 56,
          selected: currentSurah,
          selectedTileColor: colors.primaryContainer,
          selectedColor: colors.onPrimaryContainer,
          leading: surahNumber == null
              ? null
              : SizedBox(
                  width: 32,
                  child: Text(
                    '$surahNumber',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: currentSurah
                          ? colors.onPrimaryContainer
                          : colors.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
          title: Text(
            title ?? '${ayah.surahName} • آية ${ayah.number}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          subtitle: largeText && page != null ? Text('صفحة $page') : null,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!largeText && page != null)
                Text(
                  'صفحة $page',
                  style: TextStyle(color: colors.onSurfaceVariant),
                ),
              const Icon(Icons.chevron_left_rounded, size: 20),
            ],
          ),
          onTap: () => _open(ayah),
        ),
        const Divider(
          height: 1,
          indent: QuranDesign.gutter,
          endIndent: QuranDesign.gutter,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 3,
    initialIndex: widget.initialTab,
    animationDuration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : QuranDesign.motion,
    child: Scaffold(
      appBar: AppBar(
        title: Text('المكتبة', style: Theme.of(context).textTheme.titleLarge),
        toolbarHeight: 54,
        scrolledUnderElevation: 0,
        actions: [
          IconButton(
            tooltip: 'الانتقال إلى آية',
            onPressed: _direct,
            icon: const Icon(Icons.pin_drop_outlined),
          ),
          PopupMenuButton<String>(
            tooltip: 'المصادر والنسخ الاحتياطي',
            onSelected: (action) {
              switch (action) {
                case 'sources':
                  Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (_) =>
                          ReadingSourcesPage(quran: widget.index.quran),
                    ),
                  );
                case 'copy':
                  _copyBackup();
                case 'import':
                  _importBackup();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'sources',
                child: Text('المصادر وحالة المراجعة'),
              ),
              PopupMenuItem(
                value: 'copy',
                child: Text('نسخ العلامات والملاحظات'),
              ),
              PopupMenuItem(
                value: 'import',
                child: Text('استيراد العلامات من نص'),
              ),
            ],
          ),
        ],
      ),
      bottomNavigationBar: const _LibraryDock(),
      body: TabBarView(
        children: [
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  QuranDesign.gutter,
                  QuranDesign.gap,
                  QuranDesign.gutter,
                  QuranDesign.gap,
                ),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: QuranChoiceGroup<int>(
                    options: const [
                      (0, 'السور'),
                      (1, 'الأجزاء'),
                      (2, 'الأحزاب'),
                    ],
                    selected: _section,
                    onSelected: (section) => setState(() => _section = section),
                  ),
                ),
              ),
              Expanded(
                child: _section == 2
                    ? FutureBuilder<List<Ayah>>(
                        future: _hizbs,
                        builder: (context, snapshot) {
                          if (snapshot.hasError) {
                            return Center(
                              child: TextButton(
                                onPressed: () => setState(() {
                                  _section = 0;
                                }),
                                child: const Text(
                                  'تعذر تحميل فهرس الأحزاب. افتح السور',
                                ),
                              ),
                            );
                          }
                          if (!snapshot.hasData) {
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          }
                          return ListView.builder(
                            itemCount: snapshot.data!.length,
                            itemBuilder: (_, i) => _ayahTile(
                              snapshot.data![i],
                              title:
                                  'الحزب ${i + 1} • ${snapshot.data![i].surahName}',
                            ),
                          );
                        },
                      )
                    : ListView(
                        children: [
                          for (final entry
                              in (_section == 0
                                      ? widget.index.surahs
                                      : widget.index.juzs)
                                  .entries)
                            _ayahTile(
                              entry.value,
                              surahNumber: _section == 0 ? entry.key : null,
                              title: _section == 0
                                  ? entry.value.surahName
                                  : 'الجزء ${entry.key} • ${entry.value.surahName}',
                            ),
                        ],
                      ),
              ),
            ],
          ),
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    TextField(
                      controller: _query,
                      decoration: const InputDecoration(
                        labelText: 'ابحث في الآيات',
                        hintText: 'كلمة أو عبارة، بالتشكيل أو بدونه',
                        prefixIcon: Icon(Icons.search),
                      ),
                      onChanged: (query) => setState(
                        () => _results = widget.index.search(
                          query,
                          reading: _searchReading,
                        ),
                      ),
                    ),
                    const SizedBox(height: QuranDesign.gap),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<QuranReading>(
                          isExpanded: true,
                          value: _searchReading,
                          items: [
                            for (final reading in QuranReading.values)
                              DropdownMenuItem(
                                value: reading,
                                child: Text('البحث في ${reading.shortTitle}'),
                              ),
                          ],
                          onChanged: (reading) {
                            if (reading == null) return;
                            setState(() {
                              _searchReading = reading;
                              _results = widget.index.search(
                                _query.text,
                                reading: reading,
                              );
                            });
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                _query.text.trim().isEmpty
                    ? 'أدخل كلمة أو عبارة للبحث'
                    : _results.isEmpty
                    ? 'لا توجد نتائج. جرّب عبارة أقصر أو غيّر الرواية.'
                    : '${_results.length} نتيجة',
                textAlign: TextAlign.center,
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: _results.length,
                  itemBuilder: (_, i) {
                    final ayah = _results[i];
                    final location = widget.index.locateInReading(
                      _searchReading,
                      ayah,
                    );
                    return ListTile(
                      title: Text.rich(
                        _searchResult(ayah.comparisonText),
                        style: TextStyle(
                          fontFamily: _searchReading.unicodeFontFamily,
                          fontSize: 23,
                        ),
                      ),
                      subtitle: Text(
                        '${ayah.surahName} • آية ${ayah.number} • ${location == null ? 'لا توجد صفحة مرتبطة' : 'صفحة ${location.page}'}',
                      ),
                      onTap: location == null
                          ? null
                          : () => Navigator.pop(context, location),
                    );
                  },
                ),
              ),
            ],
          ),
          ListenableBuilder(
            listenable: widget.store,
            builder: (context, _) => Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: FilledButton.icon(
                    onPressed: () => _saveCurrent(),
                    icon: const Icon(Icons.bookmark_add_outlined),
                    label: const Text('حفظ الموضع الحالي'),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    '${_label(widget.current)} • صفحة ${widget.current.page}',
                    textAlign: TextAlign.center,
                  ),
                ),
                Expanded(
                  child: widget.store.bookmarks.isEmpty
                      ? const Center(child: Text('لا توجد علامات محفوظة بعد'))
                      : ListView(
                          children: [
                            for (final bookmark in widget.store.bookmarks)
                              ListTile(
                                title: Text(_label(bookmark.location)),
                                onLongPress: () =>
                                    _saveCurrent(bookmark: bookmark),
                                subtitle: Text(
                                  'صفحة ${bookmark.location.page}${bookmark.note.isEmpty ? '' : '\n${bookmark.note}'}',
                                ),
                                isThreeLine: bookmark.note.isNotEmpty,
                                onTap: widget.index.valid(bookmark.location)
                                    ? () => Navigator.pop(
                                        context,
                                        bookmark.location,
                                      )
                                    : null,
                                trailing: PopupMenuButton<String>(
                                  tooltip: 'خيارات العلامة',
                                  onSelected: (action) {
                                    if (action == 'edit') {
                                      _saveCurrent(bookmark: bookmark);
                                    } else {
                                      _deleteBookmark(bookmark);
                                    }
                                  },
                                  itemBuilder: (_) => const [
                                    PopupMenuItem(
                                      value: 'edit',
                                      child: Text('تعديل الملاحظة'),
                                    ),
                                    PopupMenuItem(
                                      value: 'delete',
                                      child: Text('حذف العلامة'),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _LibraryDock extends StatelessWidget {
  const _LibraryDock();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final scaledLabel = MediaQuery.textScalerOf(context).scale(13);
    final compact = MediaQuery.sizeOf(context).width < 370 || scaledLabel > 18;
    final dockHeight = compact && scaledLabel > 18 ? scaledLabel * 2.6 : 54.0;
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(
        QuranDesign.gutter,
        0,
        QuranDesign.gutter,
        QuranDesign.gap,
      ),
      child: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: QuranGlass(
            native: true,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: TabBar(
                dividerHeight: 0,
                indicatorSize: TabBarIndicatorSize.tab,
                indicator: BoxDecoration(
                  color: colors.primaryContainer,
                  borderRadius: BorderRadius.circular(
                    QuranDesign.controlRadius,
                  ),
                ),
                labelColor: colors.onPrimaryContainer,
                unselectedLabelColor: colors.onSurface,
                labelStyle: theme.textTheme.labelLarge,
                labelPadding: EdgeInsets.zero,
                tabs: [
                  for (final (label, icon) in const [
                    ('الفهرس', Icons.format_list_bulleted_rounded),
                    ('البحث', Icons.search_rounded),
                    ('العلامات', Icons.bookmark_border_rounded),
                  ])
                    Tab(
                      height: dockHeight,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (!compact) Icon(icon, size: QuranDesign.icon),
                          Text(
                            label,
                            textAlign: TextAlign.center,
                            maxLines: compact ? 2 : 1,
                            style: const TextStyle(fontSize: 13, height: 1.25),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../app/quran_theme.dart';
import '../../domain/models/qiraat_variants.dart';

/// One imam with the transmitters (riwayat) that read through him.
class RiwayahGroup {
  const RiwayahGroup({
    required this.readerId,
    required this.readerName,
    required this.riwayat,
  });

  final int readerId;
  final String readerName;
  final List<VariantTransmitter> riwayat;
}

/// The twenty riwayat grouped under the ten imams, in canonical order, with
/// Hafs excluded because it is the body text (R-07).
List<RiwayahGroup> groupRiwayat(QiraatVariants variants) {
  final groups = <int, List<VariantTransmitter>>{};
  for (final transmitter in variants.riwayat) {
    if (transmitter.riwayah == QiraatVariants.hafs) continue;
    (groups[transmitter.reader] ??= []).add(transmitter);
  }

  final result = [
    for (final entry in groups.entries)
      RiwayahGroup(
        readerId: entry.key,
        readerName: variants.readers[entry.key]?.name ?? '',
        riwayat: entry.value,
      ),
  ];
  result.sort((a, b) {
    final byPosition =
        (variants.readers[a.readerId]?.position ?? 99) -
        (variants.readers[b.readerId]?.position ?? 99);
    return byPosition != 0 ? byPosition : a.readerId - b.readerId;
  });
  return result;
}

/// Filters the groups by a search term, matching either the imam's name or a
/// transmitter's name. A group survives when either matches, and keeps only
/// the matching transmitters when the imam itself does not match.
List<RiwayahGroup> filterRiwayat(
  List<RiwayahGroup> groups,
  String query,
) {
  final needle = query.trim();
  if (needle.isEmpty) return groups;

  final result = <RiwayahGroup>[];
  for (final group in groups) {
    final readerMatches = group.readerName.contains(needle);
    final matches = group.riwayat
        .where((t) => t.name.contains(needle) || t.riwayah.contains(needle))
        .toList();
    if (readerMatches) {
      result.add(group);
    } else if (matches.isNotEmpty) {
      result.add(
        RiwayahGroup(
          readerId: group.readerId,
          readerName: group.readerName,
          riwayat: matches,
        ),
      );
    }
  }
  return result;
}

/// The riwayah picker: the imams as section headers with their transmitters
/// beneath, and a search field above (R-07).
class RiwayahPickerSheet extends StatefulWidget {
  const RiwayahPickerSheet({
    super.key,
    required this.variants,
    required this.selected,
  });

  final QiraatVariants variants;
  final String selected;

  @override
  State<RiwayahPickerSheet> createState() => _RiwayahPickerSheetState();
}

class _RiwayahPickerSheetState extends State<RiwayahPickerSheet> {
  late final List<RiwayahGroup> _groups = groupRiwayat(widget.variants);
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final filtered = filterRiwayat(_groups, _query);
    final theme = Theme.of(context);

    return QuranGlassSheet(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          QuranDesign.gutter,
          0,
          QuranDesign.gutter,
          QuranDesign.gutter,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('اختر الرواية', style: theme.textTheme.titleLarge),
            const SizedBox(height: QuranDesign.gap),
            TextField(
              key: const ValueKey('riwayah-search'),
              decoration: const InputDecoration(
                hintText: 'ابحث باسم القارئ أو الراوي',
                prefixIcon: Icon(Icons.search),
                isDense: true,
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
            const SizedBox(height: QuranDesign.gap),
            Flexible(
              child: filtered.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(QuranDesign.section),
                      child: Text(
                        'لا نتائج',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall,
                      ),
                    )
                  : ListView(
                      shrinkWrap: true,
                      children: [
                        for (final group in filtered) ...[
                          Padding(
                            padding: const EdgeInsets.only(top: QuranDesign.gap),
                            child: Text(
                              group.readerName,
                              style: theme.textTheme.titleSmall?.copyWith(
                                color: theme.colorScheme.primary,
                              ),
                              textDirection: TextDirection.rtl,
                            ),
                          ),
                          for (final transmitter in group.riwayat)
                            ListTile(
                              key: ValueKey('riwayah-${transmitter.riwayah}'),
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              title: Text(transmitter.name),
                              trailing: transmitter.riwayah == widget.selected
                                  ? const Icon(Icons.check, size: 18)
                                  : null,
                              onTap: () =>
                                  Navigator.of(context).pop(transmitter.riwayah),
                            ),
                        ],
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

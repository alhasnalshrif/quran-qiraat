import 'package:flutter/material.dart';

import '../../app/quran_theme.dart';
import '../../updates/protocol.dart';

/// The four update and announcement sheets of 03 §6 (D19).
///
/// A single sheet shows at a time, by priority: forced update, ready data,
/// optional update, announcement. Callers go through [UpdateSheetQueue] so the
/// order is enforced in one place.

/// Which sheet is showing.
enum UpdateSheet { forcedUpdate, dataReady, optionalUpdate, announcement }

/// Higher sorts first (03 §6).
extension UpdateSheetPriority on UpdateSheet {
  int get priority => switch (this) {
    UpdateSheet.forcedUpdate => 3,
    UpdateSheet.dataReady => 2,
    UpdateSheet.optionalUpdate => 1,
    UpdateSheet.announcement => 0,
  };
}

/// Shows the modal for [sheet] and resolves when it closes.
Future<void> showUpdateSheet({
  required BuildContext context,
  required UpdateSheet sheet,
  required VoidCallback onOpenStore,
  required VoidCallback onApplyNow,
  required VoidCallback onDismissOptional,
  required VoidCallback onDismissDataReady,
  required VoidCallback onDismissAnnouncement,
  AppPolicy? policy,
  Announcement? announcement,
  List<PackRelease> pendingPacks = const [],
}) {
  final forced = sheet == UpdateSheet.forcedUpdate;
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    isDismissible: !forced,
    enableDrag: !forced,
    builder: (sheetContext) => PopScope(
      canPop: !forced,
      child: QuranGlassSheet(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            QuranDesign.gutter,
            0,
            QuranDesign.gutter,
            QuranDesign.gutter,
          ),
          child: switch (sheet) {
            UpdateSheet.forcedUpdate => _ForcedUpdateBody(
              policy: policy!,
              onOpenStore: () {
                Navigator.of(sheetContext).pop();
                onOpenStore();
              },
            ),
            UpdateSheet.optionalUpdate => _OptionalUpdateBody(
              policy: policy!,
              onUpdate: () {
                Navigator.of(sheetContext).pop();
                onOpenStore();
              },
              onLater: () {
                onDismissOptional();
                Navigator.of(sheetContext).pop();
              },
            ),
            UpdateSheet.dataReady => _DataReadyBody(
              packs: pendingPacks,
              onApplyNow: () {
                Navigator.of(sheetContext).pop();
                onApplyNow();
              },
              onLater: () {
                onDismissDataReady();
                Navigator.of(sheetContext).pop();
              },
            ),
            UpdateSheet.announcement => _AnnouncementBody(
              announcement: announcement!,
              onOpen: announcement.url == null
                  ? null
                  : () {
                      Navigator.of(sheetContext).pop();
                    },
              onClose: () {
                onDismissAnnouncement();
                Navigator.of(sheetContext).pop();
              },
            ),
          },
        ),
      ),
    ),
  );
}

class _SheetTitle extends StatelessWidget {
  const _SheetTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: QuranDesign.gap),
    child: Text(
      text,
      style: Theme.of(context).textTheme.titleLarge,
      textAlign: TextAlign.start,
    ),
  );
}

class _ForcedUpdateBody extends StatelessWidget {
  const _ForcedUpdateBody({required this.policy, required this.onOpenStore});

  final AppPolicy policy;
  final VoidCallback onOpenStore;

  @override
  Widget build(BuildContext context) => Column(
    key: const ValueKey('forced-update-sheet'),
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const _SheetTitle('يلزم تحديث التطبيق'),
      Text(
        policy.message?.ar ?? 'هذه النسخة لم تعد مدعومة. حدّث التطبيق للمتابعة.',
      ),
      const SizedBox(height: QuranDesign.section),
      FilledButton(
        onPressed: onOpenStore,
        child: const Text('فتح المتجر'),
      ),
    ],
  );
}

class _OptionalUpdateBody extends StatelessWidget {
  const _OptionalUpdateBody({
    required this.policy,
    required this.onUpdate,
    required this.onLater,
  });

  final AppPolicy policy;
  final VoidCallback onUpdate;
  final VoidCallback onLater;

  @override
  Widget build(BuildContext context) => Column(
    key: const ValueKey('optional-update-sheet'),
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const _SheetTitle('نسخة جديدة'),
      Text(policy.message?.ar ?? 'يتوفر إصدار أحدث من التطبيق.'),
      const SizedBox(height: QuranDesign.section),
      FilledButton(onPressed: onUpdate, child: const Text('تحديث')),
      const SizedBox(height: QuranDesign.gap),
      TextButton(onPressed: onLater, child: const Text('لاحقًا')),
    ],
  );
}

class _DataReadyBody extends StatelessWidget {
  const _DataReadyBody({
    required this.packs,
    required this.onApplyNow,
    required this.onLater,
  });

  final List<PackRelease> packs;
  final VoidCallback onApplyNow;
  final VoidCallback onLater;

  @override
  Widget build(BuildContext context) => Column(
    key: const ValueKey('data-ready-sheet'),
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const _SheetTitle('تحديث بيانات جاهز'),
      ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 240),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final pack in packs)
                Padding(
                  padding: const EdgeInsets.only(bottom: QuranDesign.gap),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        pack.notes?.ar ?? pack.packId,
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                      if (pack.source != null)
                        Text(
                          '${pack.source!.name} · ${pack.source!.revision}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
      const SizedBox(height: QuranDesign.gap),
      FilledButton(onPressed: onApplyNow, child: const Text('تطبيق الآن')),
      const SizedBox(height: QuranDesign.gap),
      TextButton(onPressed: onLater, child: const Text('عند الفتح التالي')),
    ],
  );
}

class _AnnouncementBody extends StatelessWidget {
  const _AnnouncementBody({
    required this.announcement,
    required this.onOpen,
    required this.onClose,
  });

  final Announcement announcement;
  final VoidCallback? onOpen;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Column(
    key: const ValueKey('announcement-sheet'),
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _SheetTitle(announcement.title.ar),
      Text(announcement.body.ar),
      const SizedBox(height: QuranDesign.section),
      if (onOpen != null)
        FilledButton(onPressed: onOpen, child: const Text('فتح')),
      const SizedBox(height: QuranDesign.gap),
      TextButton(onPressed: onClose, child: const Text('إغلاق')),
    ],
  );
}

/// Picks the next sheet to show, by priority (D19).
///
/// A sheet is never stacked on another open sheet: the caller shows one, and
/// the queue hands out the next only after it closes.
class UpdateSheetQueue {
  UpdateSheetQueue({required this.requiresUpdate, required this.hasOptionalUpdate});

  final bool requiresUpdate;
  final bool hasOptionalUpdate;

  bool _showing = false;

  bool get isShowing => _showing;

  void begin() => _showing = true;

  void end() => _showing = false;

  /// The highest-priority sheet that still has something to say, or null.
  UpdateSheet? next({
    required List<PackRelease> pending,
    required List<Announcement> announcements,
  }) {
    if (_showing) return null;
    if (requiresUpdate) return UpdateSheet.forcedUpdate;
    if (pending.isNotEmpty) return UpdateSheet.dataReady;
    if (hasOptionalUpdate) return UpdateSheet.optionalUpdate;
    if (announcements.isNotEmpty) return UpdateSheet.announcement;
    return null;
  }
}

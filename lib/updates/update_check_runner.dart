import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../features/updates/update_sheets.dart';
import 'providers.dart';
import 'update_service.dart';

/// Runs the background update check after the first frame, then shows whatever
/// sheet the priority queue says is due (03 §5–§6, D19).
///
/// One sheet at a time, never stacked, and never over the reader while the user
/// is scrolling. Every failure is swallowed: reading must never break because
/// the network or the disk had a bad day.
class UpdateCheckRunner extends ConsumerStatefulWidget {
  const UpdateCheckRunner({super.key, required this.child});

  final Widget child;

  /// How long to wait after the first frame before raising a sheet, so the
  /// reader has settled (03 §6: not while scrolling).
  static const settleDelay = Duration(seconds: 3);

  @override
  ConsumerState<UpdateCheckRunner> createState() => _UpdateCheckRunnerState();
}

class _UpdateCheckRunnerState extends ConsumerState<UpdateCheckRunner> {
  bool _started = false;
  bool _done = false;
  bool _showing = false;
  Timer? _settle;

  @override
  void dispose() {
    _settle?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  /// True when a ProviderScope is actually above this widget. Widget tests and
  /// embedders may mount the app without one; the update layer is optional, so
  /// the runner simply stays inert rather than throwing.
  bool _hasScope() {
    try {
      ProviderScope.containerOf(context, listen: false);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _check() async {
    if (_started || !mounted || !_hasScope()) return;
    _started = true;
    try {
      // Honour updates.checkIntervalHours; a no-op when not due.
      await ref.read(manifestProvider.notifier).check(manual: false);
    } catch (_) {
      // Any failure leaves the app on its bundled data, by design (01 §2.3).
    } finally {
      if (mounted) setState(() => _done = true);
    }
    // Let the reader settle before a sheet may appear. A Timer (not a Future)
    // so widget tests can advance it with pump().
    _settle?.cancel();
    _settle = Timer(UpdateCheckRunner.settleDelay, () {
      if (mounted) _showDueSheet();
    });
  }

  /// Shows the highest-priority due sheet, then re-checks for the next one.
  Future<void> _showDueSheet() async {
    if (_showing || !mounted || !_hasScope()) return;

    final service = ref.read(updateServiceProvider).value;
    if (service == null) return;

    final pending = service.pendingReleases();
    final announcements = service.pendingAnnouncements();
    final queue = UpdateSheetQueue(
      requiresUpdate: service.requiresUpdate,
      hasOptionalUpdate: service.hasOptionalUpdate,
    );
    final next = queue.next(pending: pending, announcements: announcements);
    if (next == null) return;

    _showing = true;
    queue.begin();
    try {
      await showUpdateSheet(
        context: context,
        sheet: next,
        policy: service.manifest?.app,
        announcement: next == UpdateSheet.announcement ? announcements.first : null,
        pendingPacks: pending,
        onOpenStore: () => _openStore(service),
        onApplyNow: () => _applyNow(service),
        onDismissOptional: () => service.dismissOptionalUpdate(),
        onDismissDataReady: () {},
        onDismissAnnouncement: () => service.dismissAnnouncement(
          announcements.first.id,
        ),
      );
    } catch (_) {
      // A sheet that cannot be shown must not break the app either.
    } finally {
      _showing = false;
      queue.end();
    }

    // Another sheet may now be due (for example data ready after an update).
    if (mounted) await _showDueSheet();
  }

  Future<void> _openStore(UpdateService service) async {
    final url = service.manifest?.app.storeUrl;
    if (url == null) return;
    try {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (_) {
      // A device without a browser handler simply does nothing.
    }
  }

  Future<void> _applyNow(UpdateService service) async {
    try {
      await service.activatePending();
      ref.invalidate(quranRepositoryProvider);
    } catch (_) {
      // The user keeps reading the current data.
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;

  /// Exposed for tests: whether the startup check has completed.
  bool get completed => _done;
}

/// Outcome label for the updates screen (03 §7).
String describeOutcome(CheckOutcome? outcome) => switch (outcome) {
  CheckOutcome.notModified => 'البيان محدّث.',
  CheckOutcome.upToDate => 'لا توجد تحديثات.',
  CheckOutcome.updated => 'نُزّلت تحديثات، وهي جاهزة للتطبيق.',
  CheckOutcome.rejected => 'البيان الموقّع غير صالح، ولم يُستخدم.',
  CheckOutcome.skipped => 'لا اتصال، أو التنزيل عبر Wi-Fi فقط.',
  null => 'لم يُجرَ فحص بعد.',
};

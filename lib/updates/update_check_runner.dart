import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../updates/providers.dart';
import '../updates/update_service.dart';

/// Runs the background update check once, after the first frame (03 §5).
///
/// It is deliberately fire-and-forget: a network failure must never block or
/// disturb reading, and the result is only surfaced through the sheets and the
/// updates screen. Tests override the providers and never hit the network.
class UpdateCheckRunner extends ConsumerStatefulWidget {
  const UpdateCheckRunner({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<UpdateCheckRunner> createState() => _UpdateCheckRunnerState();
}

class _UpdateCheckRunnerState extends ConsumerState<UpdateCheckRunner> {
  bool _started = false;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  Future<void> _check() async {
    if (_started || !mounted) return;
    _started = true;
    try {
      // Honour updates.checkIntervalHours; a no-op when not due.
      await ref.read(manifestProvider.notifier).check(manual: false);
    } catch (_) {
      // Any failure leaves the app on its bundled data, by design (01 §2.3).
    } finally {
      if (mounted) setState(() => _done = true);
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

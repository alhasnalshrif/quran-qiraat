import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/quran_theme.dart';
import '../../updates/data_source.dart';
import '../../updates/protocol.dart';
import '../../updates/providers.dart';
import '../../updates/update_service.dart';

/// "التحديثات والمصادر" (03 §7): per-pack versions, the last check, the
/// Wi-Fi-only option, the channel picker and the return-to-bundled action.
class UpdatesPage extends ConsumerStatefulWidget {
  const UpdatesPage({super.key});

  @override
  ConsumerState<UpdatesPage> createState() => _UpdatesPageState();
}

class _UpdatesPageState extends ConsumerState<UpdatesPage> {
  int _versionTaps = 0;
  bool _busy = false;

  Future<void> _check(UpdateService service) async {
    setState(() => _busy = true);
    final outcome = await ref.read(manifestProvider.notifier).check(manual: true);
    if (!mounted) return;
    setState(() => _busy = false);
    final message = switch (outcome) {
      CheckOutcome.notModified => 'البيان محدّث.',
      CheckOutcome.upToDate => 'لا توجد تحديثات.',
      CheckOutcome.updated => 'نُزّلت تحديثات، وهي جاهزة للتطبيق.',
      CheckOutcome.rejected => 'البيان الموقّع غير صالح، ولم يُستخدم.',
      CheckOutcome.skipped => 'لا اتصال، أو التنزيل عبر Wi-Fi فقط.',
      null => null,
    };
    if (message != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _applyNow(UpdateService service) async {
    setState(() => _busy = true);
    await service.activatePending();
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('طُبّقت البيانات الجديدة.')),
    );
  }

  void _tapVersion() {
    _versionTaps++;
    if (_versionTaps == 7) {
      _versionTaps = 0;
      _showChannelPicker();
    }
  }

  Future<void> _showChannelPicker() async {
    final channel = ref.read(updateChannelProvider);
    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => QuranGlassSheet(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(QuranDesign.gutter),
              child: Text(
                'قناة التحديثات',
                style: Theme.of(sheetContext).textTheme.titleLarge,
              ),
            ),
            for (final name in channelNames)
              ListTile(
                key: ValueKey('channel-$name'),
                title: Text(_channelLabel(name)),
                trailing: name == channel ? const Icon(Icons.check) : null,
                onTap: () => Navigator.of(sheetContext).pop(name),
              ),
          ],
        ),
      ),
    );
    if (selected != null) {
      await ref.read(updateChannelProvider.notifier).select(selected);
    }
  }

  static String _channelLabel(String channel) => switch (channel) {
    'stable' => 'المستقرة',
    'beta' => 'التجريبية',
    _ => 'الداخلية',
  };

  @override
  Widget build(BuildContext context) {
    final service = ref.watch(updateServiceProvider).value;
    final states = ref.watch(dataSourceProvider).states;
    final store = ref.watch(packStoreFutureProvider).value;

    return Scaffold(
      appBar: AppBar(title: const Text('التحديثات والمصادر')),
      body: service == null || store == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(QuranDesign.gutter),
              children: [
                _Section(
                  title: 'الحزم',
                  child: Column(
                    children: [
                      for (final packId in packIds)
                        _PackRow(
                          label: _packLabel(packId),
                          state: states[packId],
                        ),
                    ],
                  ),
                ),
                _Section(
                  title: 'آخر فحص',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(_lastCheckText(service)),
                      if (service.lastError != null) ...[
                        const SizedBox(height: QuranDesign.gap),
                        Text(
                          service.lastError!,
                          style: TextStyle(color: Theme.of(context).colorScheme.error),
                        ),
                      ],
                      const SizedBox(height: QuranDesign.gap),
                      Row(
                        children: [
                          FilledButton(
                            key: const ValueKey('check-updates'),
                            onPressed: _busy ? null : () => _check(service),
                            child: const Text('البحث عن تحديثات'),
                          ),
                          const SizedBox(width: QuranDesign.gap),
                          if (store.state.pending.isNotEmpty)
                            OutlinedButton(
                              key: const ValueKey('apply-now'),
                              onPressed: _busy ? null : () => _applyNow(service),
                              child: const Text('تطبيق الآن'),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                SwitchListTile(
                  key: const ValueKey('wifi-only'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('التنزيل عبر Wi-Fi فقط'),
                  value: service.wifiOnly,
                  onChanged: (value) => setState(() => service.setWifiOnly(value)),
                ),
                const Divider(),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  onTap: _tapVersion,
                  title: const Text('النسخة'),
                  subtitle: Text(
                    '${service.appBuild} · ${_channelLabel(service.channel)}',
                  ),
                ),
                const SizedBox(height: QuranDesign.section),
                OutlinedButton.icon(
                  key: const ValueKey('reset-packs'),
                  onPressed: _busy
                      ? null
                      : () async {
                          setState(() => _busy = true);
                          await store.resetAll();
                          ref.invalidate(quranRepositoryProvider);
                          if (!mounted) return;
                          setState(() => _busy = false);
                        },
                  icon: const Icon(Icons.restart_alt),
                  label: const Text('الرجوع للبيانات الأصلية'),
                ),
              ],
            ),
    );
  }

  String _lastCheckText(UpdateService service) {
    final last = service.lastCheck;
    if (last == null) return 'لم يُجرَ فحص بعد.';
    final local = last.toLocal();
    final stamp =
        '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    return 'آخر فحص: $stamp';
  }

  static String _packLabel(String packId) => switch (packId) {
    'editions-manifest' => 'بيان الطبعات',
    'hafs-text' => 'نص حفص',
    'riwayah-shubah-text' => 'نص شعبة',
    'riwayah-qalun-text' => 'نص قالون',
    'hafs-layout-1405' => 'تخطيط صفحات حفص',
    'mapping-hafs-qalun' => 'مطابقة حفص وقالون',
    'qiraat-farsh' => 'فرش القراءات',
    'published-differences' => 'الفروق المعتمدة',
    'navigation-hizbs' => 'أحزاب المصحف',
    _ => packId,
  };
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: QuranDesign.section),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: QuranDesign.gap),
        child,
      ],
    ),
  );
}

class _PackRow extends StatelessWidget {
  const _PackRow({required this.label, required this.state});

  final String label;
  final PackState? state;

  @override
  Widget build(BuildContext context) {
    final source = state?.sourceKind == PackSourceKind.downloaded
        ? 'منزّل'
        : 'مضمّن';
    return Padding(
      padding: const EdgeInsets.only(bottom: QuranDesign.gap),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(
            '$source · v${state?.version ?? 1}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

class HafsAyahAudioDialog extends StatefulWidget {
  const HafsAyahAudioDialog({
    super.key,
    required this.surah,
    required this.ayah,
    this.hasAyah,
  });
  final int surah;
  final int ayah;

  /// Whether the given ayah exists, used to continue to the next one.
  final bool Function(int surah, int ayah)? hasAyah;

  @override
  State<HafsAyahAudioDialog> createState() => _HafsAyahAudioDialogState();
}

class _HafsAyahAudioDialogState extends State<HafsAyahAudioDialog> {
  AudioPlayer? _player;
  Future<void>? _operation;
  bool _repeat = false;
  bool _continuous = false;
  bool _error = false;
  late int _ayah = widget.ayah;
  StreamSubscription<void>? _completion;

  bool get _hasNext => widget.hasAyah?.call(widget.surah, _ayah + 1) ?? false;

  void _onComplete(void _) {
    if (!mounted || !_continuous || _repeat || !_hasNext) return;
    setState(() => _ayah++);
    final player = _player;
    if (player == null) return;
    _play(player).catchError((Object _) {
      if (mounted) setState(() => _error = true);
    });
  }

  Future<void> _play(AudioPlayer player) async {
    final surah = widget.surah.toString().padLeft(3, '0');
    final ayah = _ayah.toString().padLeft(3, '0');
    await player.setReleaseMode(
      _repeat ? ReleaseMode.loop : ReleaseMode.release,
    );
    if (!mounted) return;
    await player.play(
      UrlSource('https://everyayah.com/data/Husary_64kbps/$surah$ayah.mp3'),
    );
  }

  Future<void> _togglePlayback() async {
    if (_operation != null) return;
    final player = _player ??= AudioPlayer();
    _completion ??= player.onPlayerComplete.listen(_onComplete);
    final operation = _changePlayback(player);
    setState(() {
      _operation = operation;
      _error = false;
    });
    try {
      await operation;
    } catch (_) {
      if (mounted) setState(() => _error = true);
    } finally {
      if (mounted) setState(() => _operation = null);
    }
  }

  Future<void> _changePlayback(AudioPlayer player) async {
    if (player.state == PlayerState.playing) {
      await player.stop();
      return;
    }
    await _play(player);
  }

  @override
  void dispose() {
    _completion?.cancel();
    final player = _player;
    if (player != null) unawaited(_disposePlayer(player));
    super.dispose();
  }

  Future<void> _disposePlayer(AudioPlayer player) async {
    try {
      await player.dispose();
    } catch (_) {
      // A failed platform player can already have released its resources.
    }
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<PlayerState>(
    stream: _player?.onPlayerStateChanged,
    builder: (context, snapshot) {
      final playing = (_player?.state ?? snapshot.data) == PlayerState.playing;
      return AlertDialog(
        scrollable: true,
        title: Text('تلاوة الآية ${widget.surah}:$_ayah'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('محمود خليل الحصري · حفص عن عاصم'),
            const Text('بث من EveryAyah، يتطلب اتصالًا بالإنترنت.'),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('تكرار الآية'),
              value: _repeat,
              onChanged: playing || _operation != null
                  ? null
                  : (value) => setState(() {
                      _repeat = value;
                      if (value) _continuous = false;
                    }),
            ),
            if (widget.hasAyah != null)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('متابعة الآيات التالية'),
                value: _continuous,
                onChanged: (value) => setState(() {
                  _continuous = value;
                  if (value) _repeat = false;
                }),
              ),
            if (_error)
              const Text(
                'تعذر تشغيل التلاوة. تحقّق من الاتصال وحاول مرة أخرى.',
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إغلاق'),
          ),
          FilledButton(
            onPressed: _operation == null ? _togglePlayback : null,
            child: Text(
              _operation != null
                  ? 'جارٍ التحميل'
                  : playing
                  ? 'إيقاف'
                  : 'تشغيل',
            ),
          ),
        ],
      );
    },
  );
}

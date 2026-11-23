import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/models/margin_riwayah.dart';

class ReaderLocation {
  const ReaderLocation({
    required this.page,
    required this.surah,
    required this.ayah,
    this.word,
    this.reading = QuranReading.hafs,
  });
  final int page;
  final int surah;
  final int ayah;
  final int? word;
  final QuranReading reading;
  String get key => '${reading.name}:$surah:$ayah:${word ?? 0}';
  Map<String, Object?> toJson() => {
    'page': page,
    'surah': surah,
    'ayah': ayah,
    'word': word,
    'reading': reading.name,
  };
  static ReaderLocation? fromJson(Object? value) {
    if (value is! Map) return null;
    final page = value['page'],
        surah = value['surah'],
        ayah = value['ayah'],
        word = value['word'];
    if (page is! int ||
        page < 1 ||
        page > 604 ||
        surah is! int ||
        surah < 1 ||
        surah > 114 ||
        ayah is! int ||
        ayah < 1 ||
        ayah > 286 ||
        (word != null && (word is! int || word < 1 || word > 200))) {
      return null;
    }
    final readings = QuranReading.values.where(
      (r) => r.name == value['reading'],
    );
    if (readings.isEmpty) return null;
    return ReaderLocation(
      page: page,
      surah: surah,
      ayah: ayah,
      word: word as int?,
      reading: readings.first,
    );
  }
}

class ReaderBookmark {
  const ReaderBookmark(this.location, this.note);
  final ReaderLocation location;
  final String note;
  Map<String, Object?> toJson() => {
    'location': location.toJson(),
    'note': note,
  };
}

class ReaderLibraryStore extends ChangeNotifier {
  ReaderLibraryStore(this.preferences) {
    try {
      final raw = jsonDecode(preferences.getString(storageKey) ?? '{}');
      if (raw is Map && raw['version'] == 1) {
        resume = ReaderLocation.fromJson(raw['resume']);
        if (raw['bookmarks'] is List) {
          final seen = <String>{};
          for (final item in raw['bookmarks']) {
            if (item is! Map) continue;
            final location = ReaderLocation.fromJson(item['location']);
            if (location != null &&
                item['note'] is String &&
                seen.add(location.key)) {
              bookmarks.add(ReaderBookmark(location, item['note']));
            }
          }
        }
      }
    } on FormatException {
      /* A damaged library must not prevent reading. */
    }
  }
  static const storageKey = 'reader_library_v1';
  final SharedPreferences preferences;
  final List<ReaderBookmark> bookmarks = [];
  ReaderLocation? resume;
  Future<void> _pending = Future.value();
  bool _disposed = false;
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<void> save(ReaderLocation location, String note) => _commit(() {
    bookmarks.removeWhere((b) => b.location.key == location.key);
    bookmarks.insert(0, ReaderBookmark(location, note.trim()));
  });
  Future<void> remove(ReaderLocation location) => _commit(
    () => bookmarks.removeWhere((b) => b.location.key == location.key),
  );
  Future<void> setResume(ReaderLocation? location) =>
      _commit(() => resume = location);

  String exportBookmarks() => jsonEncode({
    'format': storageKey,
    'bookmarks': [for (final bookmark in bookmarks) bookmark.toJson()],
  });

  Future<int> importBookmarks(
    String backup, {
    required bool Function(ReaderLocation) isValidLocation,
  }) async {
    if (backup.length > 4000000) {
      throw const FormatException('Backup too large');
    }
    final data = jsonDecode(backup);
    if (data is! Map ||
        data['format'] != storageKey ||
        data['bookmarks'] is! List) {
      throw const FormatException('Invalid bookmark backup');
    }
    final entries = <ReaderBookmark>[];
    for (final row in data['bookmarks']) {
      final location = row is Map
          ? ReaderLocation.fromJson(row['location'])
          : null;
      final note = row is Map ? row['note'] : null;
      if (location == null ||
          !isValidLocation(location) ||
          note is! String ||
          note.runes.length > 8000) {
        throw const FormatException('Invalid bookmark entry');
      }
      entries.add(ReaderBookmark(location, note));
    }
    var added = 0;
    await _commit(() {
      final known = bookmarks.map((bookmark) => bookmark.location.key).toSet();
      for (final bookmark in entries) {
        if (known.add(bookmark.location.key)) {
          bookmarks.add(bookmark);
          added++;
        }
      }
    });
    return added;
  }

  Future<void> _commit(VoidCallback change) {
    final operation = _pending.then((_) async {
      final previous = List<ReaderBookmark>.of(bookmarks),
          previousResume = resume;
      change();
      try {
        final saved = await preferences.setString(
          storageKey,
          jsonEncode({
            'version': 1,
            'resume': resume?.toJson(),
            'bookmarks': bookmarks.map((b) => b.toJson()).toList(),
          }),
        );
        if (!saved) throw StateError('Unable to save reader library');
      } catch (_) {
        bookmarks
          ..clear()
          ..addAll(previous);
        resume = previousResume;
        rethrow;
      }
      if (!_disposed) notifyListeners();
    });
    _pending = operation.catchError((Object _) {});
    return operation;
  }
}

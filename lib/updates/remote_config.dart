/// Approved remote config keys with their types and defaults (01 §4).
///
/// Adding a key starts in the plan document, then here and in
/// `packages/contracts/src/config-keys.ts`.
library;

const String checkIntervalHoursKey = 'updates.checkIntervalHours';
const String wifiOnlyDefaultKey = 'updates.wifiOnlyDefault';
const String featuresAudioKey = 'features.audio';
const String featuresAnnouncementsKey = 'features.announcements';
const String audioRecitersKey = 'audio.reciters';

/// Every approved key, in the order the plan lists them.
const List<String> configKeys = [
  checkIntervalHoursKey,
  wifiOnlyDefaultKey,
  featuresAudioKey,
  featuresAnnouncementsKey,
  audioRecitersKey,
];

/// The config values a manifest may change, with plan defaults applied.
class RemoteConfig {
  const RemoteConfig._(this._values);

  factory RemoteConfig(Map<String, dynamic> manifestConfig) {
    final values = <String, Object?>{};
    for (final entry in manifestConfig.entries) {
      final validated = _validate(entry.key, entry.value);
      if (validated != null) values[entry.key] = validated;
    }
    return RemoteConfig._(Map.unmodifiable(values));
  }

  final Map<String, Object?> _values;

  /// `updates.checkIntervalHours` (1–168, default 6).
  int get checkIntervalHours =>
      (_values[checkIntervalHoursKey] as int?) ?? 6;

  Duration get checkInterval => Duration(hours: checkIntervalHours);

  /// `updates.wifiOnlyDefault` (default true).
  bool get wifiOnlyDefault => (_values[wifiOnlyDefaultKey] as bool?) ?? true;

  /// `features.audio` (default true).
  bool get audioEnabled => (_values[featuresAudioKey] as bool?) ?? true;

  /// `features.announcements` (default true).
  bool get announcementsEnabled =>
      (_values[featuresAnnouncementsKey] as bool?) ?? true;

  /// `audio.reciters`: the bundled list stays unless the server sends one.
  List<Object?>? get audioReciters => _values[audioRecitersKey] as List<Object?>?;

  /// The accepted values actually sent by the server.
  Map<String, Object?> get values => _values;

  static Object? _validate(String key, Object? value) {
    switch (key) {
      case checkIntervalHoursKey:
        return value is int && value >= 1 && value <= 168 ? value : null;
      case wifiOnlyDefaultKey:
      case featuresAudioKey:
      case featuresAnnouncementsKey:
        return value is bool ? value : null;
      case audioRecitersKey:
        return value is List ? value : null;
      default:
        return null;
    }
  }
}

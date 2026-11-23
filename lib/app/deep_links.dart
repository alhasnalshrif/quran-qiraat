/// In-app deep links carried by notifications (03 §12).
///
/// A notification puts a `link` string in its `additionalData`; this parses it
/// into something the app can act on. Anything unknown or malformed is ignored
/// and the app opens normally, so a bad link can never break start-up.
library;

/// Where a link points.
sealed class DeepLink {
  const DeepLink();
}

/// `quranqiraat://page/<1-604>` — open the reader at this page.
class PageLink extends DeepLink {
  const PageLink(this.page);

  final int page;
}

/// `quranqiraat://ayah/<surah>/<ayah>` — open a verse (Hafs numbering).
class AyahLink extends DeepLink {
  const AyahLink({required this.surah, required this.ayah});

  final int surah;
  final int ayah;
}

/// `quranqiraat://updates` — open the updates screen and check now.
class UpdatesLink extends DeepLink {
  const UpdatesLink();
}

/// `quranqiraat://announcement/<id>` — show that announcement sheet.
class AnnouncementLink extends DeepLink {
  const AnnouncementLink(this.id);

  final String id;
}

const int _pageCount = 604;
const int _surahCount = 114;

/// Parses a link; returns null for anything that is not an allowed link.
DeepLink? parseDeepLink(String? raw) {
  if (raw == null) return null;
  final value = raw.trim();
  if (!value.startsWith('quranqiraat://')) return null;

  // Everything after the scheme, without a trailing slash.
  final path = value.substring('quranqiraat://'.length);
  final segments = path.split('/').where((segment) => segment.isNotEmpty).toList();
  if (segments.isEmpty) return null;

  switch (segments.first) {
    case 'page':
      if (segments.length != 2) return null;
      final page = int.tryParse(segments[1]);
      if (page == null || page < 1 || page > _pageCount) return null;
      return PageLink(page);

    case 'ayah':
      if (segments.length != 3) return null;
      final surah = int.tryParse(segments[1]);
      final ayah = int.tryParse(segments[2]);
      if (surah == null || surah < 1 || surah > _surahCount) return null;
      if (ayah == null || ayah < 1) return null;
      return AyahLink(surah: surah, ayah: ayah);

    case 'updates':
      if (segments.length != 1) return null;
      return const UpdatesLink();

    case 'announcement':
      if (segments.length != 2) return null;
      final id = segments[1].trim();
      if (id.isEmpty) return null;
      return AnnouncementLink(id);

    default:
      return null;
  }
}

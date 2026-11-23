import 'package:shared_preferences/shared_preferences.dart';

import 'deep_links.dart';

/// The preference the reader restores its page from (03 §12 page links).
const String lastPagePreference = 'last_page';

/// A route target resolved from a [DeepLink].
sealed class LinkAction {
  const LinkAction();
}

/// Open the reader at this page.
class OpenPage extends LinkAction {
  const OpenPage(this.page);

  final int page;
}

/// Open the reader at the page holding a verse, then reveal that verse.
class OpenAyah extends LinkAction {
  const OpenAyah({required this.surah, required this.ayah});

  final int surah;
  final int ayah;
}

/// Open the updates screen and check now.
class OpenUpdates extends LinkAction {
  const OpenUpdates();
}

/// Show one announcement sheet.
class OpenAnnouncement extends LinkAction {
  const OpenAnnouncement(this.id);

  final String id;
}

/// The page a verse sits on, using the Hafs layout the reader already loads.
int? pageForAyah(
  Map<int, List<String>> ayahKeysByPage,
  int surah,
  int ayah,
) {
  final key = '$surah:$ayah';
  for (final entry in ayahKeysByPage.entries) {
    if (entry.value.contains(key)) return entry.key;
  }
  return null;
}

/// Turns a parsed link into the action the app should take, or null when the
/// link cannot be resolved (an unknown announcement, an unreachable verse).
LinkAction? actionForLink(
  DeepLink? link, {
  required Map<int, List<String>> ayahKeysByPage,
  required bool Function(String id) hasAnnouncement,
}) {
  switch (link) {
    case null:
      return null;
    case PageLink(:final page):
      return OpenPage(page);
    case AyahLink(:final surah, :final ayah):
      // Only resolve verses the loaded layout actually contains.
      if (pageForAyah(ayahKeysByPage, surah, ayah) == null) return null;
      return OpenAyah(surah: surah, ayah: ayah);
    case UpdatesLink():
      return const OpenUpdates();
    case AnnouncementLink(:final id):
      return hasAnnouncement(id) ? OpenAnnouncement(id) : null;
  }
}

/// Saves the target page so the reader opens there on the next build.
///
/// The reader reads `last_page` at start-up, so a notification can steer it
/// without threading a new parameter through every widget.
Future<void> preparePageTarget(SharedPreferences preferences, int page) async {
  final clamped = page.clamp(1, 604);
  await preferences.setInt(lastPagePreference, clamped);
}

import 'prefs_store.dart';

/// The user's real search history on this phone — what they typed or picked,
/// newest first, max 8. Replaces the old demo list.
class RecentSearches {
  RecentSearches._();

  static const int _max = 8;

  static List<String> get all =>
      Prefs.isReady ? Prefs.instance.recentSearches : const [];

  /// Adds [term] to the top (moving it if it's already there).
  static Future<void> remember(String term) async {
    final t = term.trim();
    if (t.length < 2 || !Prefs.isReady) return;
    final next = [
      t,
      ...all.where((e) => e.toLowerCase() != t.toLowerCase()),
    ].take(_max).toList();
    await Prefs.instance.setRecentSearches(next);
  }

  static Future<void> remove(String term) async {
    if (!Prefs.isReady) return;
    await Prefs.instance
        .setRecentSearches(all.where((e) => e != term).toList());
  }

  static Future<void> clear() async {
    if (!Prefs.isReady) return;
    await Prefs.instance.setRecentSearches(const []);
  }
}

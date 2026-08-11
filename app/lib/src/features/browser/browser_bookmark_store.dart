import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class BrowserBookmark {
  const BrowserBookmark({required this.title, required this.url});

  final String title;
  final String url;

  BrowserBookmark renamed(String value) {
    final normalized = value.trim();
    return BrowserBookmark(
      title: normalized.isEmpty ? title : normalized,
      url: url,
    );
  }

  Map<String, dynamic> toJson() => {'title': title, 'url': url};

  static BrowserBookmark? tryParse(Object? value) {
    if (value is! Map<String, dynamic>) return null;
    final canonicalUrl = canonicalBrowserBookmarkUrl(value['url']?.toString());
    if (canonicalUrl == null) return null;
    final rawTitle = value['title']?.toString().trim() ?? '';
    return BrowserBookmark(
      title: rawTitle.isEmpty ? Uri.parse(canonicalUrl).host : rawTitle,
      url: canonicalUrl,
    );
  }
}

/// Returns a conservative duplicate key for an HTTP(S) page.
///
/// Only surrounding whitespace plus scheme/host casing are normalized. Paths,
/// trailing slashes, query strings, and fragments remain distinct because they
/// can identify meaningful application routes.
String? canonicalBrowserBookmarkUrl(String? value) {
  final trimmed = value?.trim() ?? '';
  final uri = Uri.tryParse(trimmed);
  final scheme = uri?.scheme.toLowerCase();
  if (uri == null ||
      (scheme != 'http' && scheme != 'https') ||
      uri.host.isEmpty) {
    return null;
  }
  return uri.replace(scheme: scheme, host: uri.host.toLowerCase()).toString();
}

class BrowserBookmarkStore {
  BrowserBookmarkStore({SharedPreferencesAsync? preferences})
      : _preferences = preferences ?? SharedPreferencesAsync();

  static const keyPrefix = 'wingman.browser.bookmarks.v1.';
  final SharedPreferencesAsync _preferences;

  Future<List<BrowserBookmark>> load(String signerNpub) async {
    final key = _storageKey(signerNpub);
    if (key == null) return const [];
    final raw = await _preferences.getString(key);
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic> || decoded['bookmarks'] is! List) {
        return const [];
      }
      final seen = <String>{};
      final bookmarks = <BrowserBookmark>[];
      for (final value in decoded['bookmarks'] as List<dynamic>) {
        final bookmark = BrowserBookmark.tryParse(value);
        if (bookmark != null && seen.add(bookmark.url)) bookmarks.add(bookmark);
      }
      return bookmarks;
    } catch (_) {
      return const [];
    }
  }

  Future<void> save(
    String signerNpub,
    List<BrowserBookmark> bookmarks,
  ) async {
    final key = _storageKey(signerNpub);
    if (key == null) return;
    await _preferences.setString(
      key,
      jsonEncode({
        'version': 1,
        'bookmarks': [for (final bookmark in bookmarks) bookmark.toJson()],
      }),
    );
  }

  String? _storageKey(String signerNpub) {
    final normalized = signerNpub.trim();
    return normalized.isEmpty ? null : '$keyPrefix$normalized';
  }
}

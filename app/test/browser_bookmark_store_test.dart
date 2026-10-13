import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:wingman_app/src/features/browser/browser_bookmark_store.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  test('canonicalization only normalizes whitespace and scheme/host casing',
      () {
    expect(
      canonicalBrowserBookmarkUrl(' HTTPS://Example.COM/path/?b=2&a=1#part '),
      'https://example.com/path/?b=2&a=1#part',
    );
    expect(
      canonicalBrowserBookmarkUrl('https://example.com/path?b=2&a=1#part'),
      isNot(
        canonicalBrowserBookmarkUrl('https://example.com/path/?b=2&a=1#part'),
      ),
    );
    expect(canonicalBrowserBookmarkUrl('file:///tmp/page'), isNull);
    expect(canonicalBrowserBookmarkUrl('not a URL'), isNull);
  });

  test('bookmarks persist and reload for one signer', () async {
    final store = BrowserBookmarkStore();
    const bookmarks = [
      BrowserBookmark(title: 'Useful page', url: 'https://example.com/page'),
    ];

    await store.save('npub-pete', bookmarks);

    expect(await BrowserBookmarkStore().load('npub-pete'), hasLength(1));
    final restored = (await BrowserBookmarkStore().load('npub-pete')).single;
    expect(restored.title, 'Useful page');
    expect(restored.url, 'https://example.com/page');
    expect(await store.load('npub-someone-else'), isEmpty);
  });

  test('renaming trims the title while preserving bookmark identity', () async {
    final store = BrowserBookmarkStore();
    const original = BrowserBookmark(
      title: 'Original title',
      url: 'https://example.com/page',
    );
    final renamed = original.renamed('  Better title  ');

    expect(renamed.title, 'Better title');
    expect(renamed.url, original.url);
    expect(original.renamed('   ').title, original.title);

    await store.save('npub-pete', [renamed]);
    final restored = (await BrowserBookmarkStore().load('npub-pete')).single;
    expect(restored.title, 'Better title');
    expect(restored.url, original.url);
  });

  test('thumbnail precedence and background are persisted and identity scoped',
      () async {
    final store = BrowserBookmarkStore();
    final image = 'data:image/png;base64,${base64Encode([
          137,
          80,
          78,
          71,
          13,
          10,
          26,
          10
        ])}';
    final app = BrowserBookmark(
        title: 'App',
        url: 'https://example.com/?keep=1#part',
        iconUrl: 'https://example.com/icon.png',
        customImage: image);
    await store.save('npub-a', [app]);
    await store.saveBackground('npub-a', image);
    final restored = (await store.load('npub-a')).single;
    expect(restored.thumbnail, image);
    expect(restored.url, app.url);
    expect(restored.iconUrl, app.iconUrl);
    expect(await store.loadBackground('npub-a'), image);
    expect(await store.loadBackground('npub-b'), isNull);
    await store.saveBackground('npub-a', null);
    expect(await store.loadBackground('npub-a'), isNull);
  });

  test('metadata cannot become a service endpoint or script', () {
    expect(safeBookmarkIconUrl('https://peer.fips/icon.png'), isNull);
    expect(safeBookmarkIconUrl('http://remote.example/icon.png'), isNull);
    expect(safeBookmarkIconUrl('javascript:alert(1)'), isNull);
    expect(safeBookmarkImage('data:image/svg+xml,<svg/>'), isNull);
    expect(safeBookmarkImage('data:image/png;base64,broken'), isNull);
    expect(safeBookmarkIconUrl('http://127.0.0.1:47831/icon.png'), isNotNull);
    expect(
        canonicalBrowserBookmarkUrl('https://user:pass@example.com'), isNull);
    expect(canonicalBrowserBookmarkUrl('https://example.com/a b'), isNull);
    const app = BrowserBookmark(
        title: 'Legacy', url: 'https://example.com/path?private=1');
    expect(app.thumbnail, 'https://example.com/favicon.ico');
    expect(app.renamed('New').url, app.url);
  });

  test('corrupt and stale entries are ignored and duplicates are removed',
      () async {
    final preferences = SharedPreferencesAsync();
    final store = BrowserBookmarkStore(preferences: preferences);
    await preferences.setString(
      '${BrowserBookmarkStore.keyPrefix}npub-corrupt',
      jsonEncode({
        'bookmarks': [
          {'title': 'First', 'url': 'HTTPS://Example.COM/page?x=1'},
          {'title': 'Duplicate', 'url': 'https://example.com/page?x=1'},
          {'title': 'Bad', 'url': 'javascript:alert(1)'},
          {'title': '', 'url': 'https://fallback.example/path'},
          'stale',
        ],
      }),
    );

    final bookmarks = await store.load('npub-corrupt');

    expect(bookmarks, hasLength(2));
    expect(bookmarks.first.title, 'First');
    expect(bookmarks.last.title, 'fallback.example');

    await preferences.setString(
      '${BrowserBookmarkStore.keyPrefix}npub-corrupt',
      '{not-json',
    );
    expect(await store.load('npub-corrupt'), isEmpty);
  });
}

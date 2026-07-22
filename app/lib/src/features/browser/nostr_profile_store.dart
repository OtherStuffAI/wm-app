import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class NostrProfileStore {
  NostrProfileStore({SharedPreferencesAsync? preferences})
      : _preferences = preferences ?? SharedPreferencesAsync();

  static const _profileKeyPrefix = 'wingman.nostr.profile.v1.';

  final SharedPreferencesAsync _preferences;

  Future<NostrProfile> load(String npub) async {
    final key = _keyFor(npub);
    if (key == null) return const NostrProfile();
    final raw = await _preferences.getString(key);
    return NostrProfile.tryParse(raw) ?? const NostrProfile();
  }

  Future<void> save(String npub, NostrProfile profile) async {
    final key = _keyFor(npub);
    if (key == null) return;
    await _preferences.setString(key, jsonEncode(profile.toJson()));
  }

  String? _keyFor(String npub) {
    final normalized = npub.trim();
    if (normalized.isEmpty) return null;
    return '$_profileKeyPrefix$normalized';
  }
}

class NostrProfile {
  const NostrProfile({
    this.displayName = '',
    this.name = '',
    this.pictureUrl = '',
    this.nip05 = '',
    this.website = '',
    this.about = '',
  });

  final String displayName;
  final String name;
  final String pictureUrl;
  final String nip05;
  final String website;
  final String about;

  String labelFor(String npub) {
    final primary = displayName.trim();
    if (primary.isNotEmpty) return primary;
    final secondary = name.trim();
    if (secondary.isNotEmpty) return secondary;
    final normalized = npub.trim();
    if (normalized.length > 12) {
      return '${normalized.substring(0, 8)}...${normalized.substring(normalized.length - 4)}';
    }
    return normalized.isEmpty ? 'Wingman' : normalized;
  }

  String get avatarUrl {
    final value = pictureUrl.trim();
    final uri = Uri.tryParse(value);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return '';
    return value;
  }

  NostrProfile copyWith({
    String? displayName,
    String? name,
    String? pictureUrl,
    String? nip05,
    String? website,
    String? about,
  }) {
    return NostrProfile(
      displayName: displayName ?? this.displayName,
      name: name ?? this.name,
      pictureUrl: pictureUrl ?? this.pictureUrl,
      nip05: nip05 ?? this.nip05,
      website: website ?? this.website,
      about: about ?? this.about,
    );
  }

  Map<String, dynamic> toKind0Json() {
    return {
      if (name.trim().isNotEmpty) 'name': name.trim(),
      if (displayName.trim().isNotEmpty) 'display_name': displayName.trim(),
      if (pictureUrl.trim().isNotEmpty) 'picture': pictureUrl.trim(),
      if (nip05.trim().isNotEmpty) 'nip05': nip05.trim(),
      if (website.trim().isNotEmpty) 'website': website.trim(),
      if (about.trim().isNotEmpty) 'about': about.trim(),
    };
  }

  Map<String, dynamic> toJson() {
    return {
      'version': 1,
      'display_name': displayName,
      'name': name,
      'picture_url': pictureUrl,
      'nip05': nip05,
      'website': website,
      'about': about,
      'kind0_content': toKind0Json(),
    };
  }

  static NostrProfile? tryParse(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(value);
      if (decoded is! Map<String, dynamic>) return null;
      return NostrProfile(
        displayName: decoded['display_name']?.toString() ?? '',
        name: decoded['name']?.toString() ?? '',
        pictureUrl: decoded['picture_url']?.toString() ??
            decoded['picture']?.toString() ??
            '',
        nip05: decoded['nip05']?.toString() ?? '',
        website: decoded['website']?.toString() ?? '',
        about: decoded['about']?.toString() ?? '',
      );
    } catch (_) {
      return null;
    }
  }
}

import 'dart:convert';

import 'package:flutter/services.dart';
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

  Future<NostrProfile> save(String npub, NostrProfile profile) async {
    final key = _keyFor(npub);
    if (key == null) return profile;
    final cached = await _withCachedAvatar(profile);
    await _preferences.setString(key, jsonEncode(cached.toJson()));
    return cached;
  }

  String? _keyFor(String npub) {
    final normalized = npub.trim();
    if (normalized.isEmpty) return null;
    return '$_profileKeyPrefix$normalized';
  }

  Future<NostrProfile> _withCachedAvatar(NostrProfile profile) async {
    final avatarUrl = profile.avatarUrl;
    if (avatarUrl.isEmpty) {
      return profile.copyWithCachedAvatar(url: '', base64: '');
    }
    if (profile.cachedPictureUrl == avatarUrl &&
        profile.cachedPictureBase64.isNotEmpty) {
      return profile;
    }
    try {
      final data = await NetworkAssetBundle(Uri.parse(avatarUrl))
          .load(avatarUrl)
          .timeout(const Duration(seconds: 6));
      if (data.lengthInBytes > 1500000) return profile;
      final bytes = Uint8List.view(
        data.buffer,
        data.offsetInBytes,
        data.lengthInBytes,
      );
      return profile.copyWithCachedAvatar(
        url: avatarUrl,
        base64: base64Encode(bytes),
      );
    } catch (_) {
      return profile.copyWithCachedAvatar(url: '', base64: '');
    }
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
    this.cachedPictureUrl = '',
    this.cachedPictureBase64 = '',
  });

  final String displayName;
  final String name;
  final String pictureUrl;
  final String nip05;
  final String website;
  final String about;
  final String cachedPictureUrl;
  final String cachedPictureBase64;

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

  Uint8List? get cachedAvatarBytes {
    if (cachedPictureUrl.trim() != avatarUrl || cachedPictureBase64.isEmpty) {
      return null;
    }
    try {
      return base64Decode(cachedPictureBase64);
    } catch (_) {
      return null;
    }
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
      cachedPictureUrl: cachedPictureUrl,
      cachedPictureBase64: cachedPictureBase64,
    );
  }

  NostrProfile copyWithCachedAvatar({
    required String url,
    required String base64,
  }) {
    return NostrProfile(
      displayName: displayName,
      name: name,
      pictureUrl: pictureUrl,
      nip05: nip05,
      website: website,
      about: about,
      cachedPictureUrl: url,
      cachedPictureBase64: base64,
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
      'cached_picture_url': cachedPictureUrl,
      'cached_picture_base64': cachedPictureBase64,
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
        cachedPictureUrl: decoded['cached_picture_url']?.toString() ?? '',
        cachedPictureBase64: decoded['cached_picture_base64']?.toString() ?? '',
      );
    } catch (_) {
      return null;
    }
  }
}

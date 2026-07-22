import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'nostr_crypto.dart';

class SignerVault {
  SignerVault({
    SignerVaultLocalStore? localStore,
    SignerVaultSecretStore? secretStore,
  })  : _localStore = localStore ?? SharedPreferencesSignerVaultLocalStore(),
        _secretStore = secretStore ?? SecureStorageSignerVaultSecretStore();

  static const _vaultRecordKey = 'wingman.signer.vault.v1';
  static const _deviceSecretKey = 'wingman.signer.device_secret.v1';
  static const _iterations = 210000;

  final SignerVaultLocalStore _localStore;
  final SignerVaultSecretStore _secretStore;

  Future<SignerVaultRecord?> loadRecord() async {
    final raw = await _localStore.getString(_vaultRecordKey);
    if (raw == null || raw.trim().isEmpty) return null;
    return SignerVaultRecord.tryParse(raw);
  }

  Future<bool> hasVault() async => await loadRecord() != null;

  Future<SignerVaultUnlock> create({
    required String nsec,
    required String pin,
  }) async {
    _validatePin(pin);
    final identity = NostrCrypto.importIdentity(nsec);
    final deviceSecret = await _loadOrCreateDeviceSecret();
    final salt = _randomBytes(16);
    final nonce = _randomBytes(12);
    final secretKey = await _deriveKey(
      pin: pin,
      deviceSecret: deviceSecret,
      salt: salt,
      iterations: _iterations,
    );
    final secretBox = await AesGcm.with256bits().encrypt(
      utf8.encode(identity.nsec),
      secretKey: secretKey,
      nonce: nonce,
    );
    final record = SignerVaultRecord(
      version: 1,
      kdf: 'pbkdf2-hmac-sha256',
      iterations: _iterations,
      salt: base64.encode(salt),
      nonce: base64.encode(secretBox.nonce),
      ciphertext: base64.encode(secretBox.cipherText),
      mac: base64.encode(secretBox.mac.bytes),
      npub: identity.npub,
      publicKeyHex: identity.publicKeyHex,
      createdAt: DateTime.now().toUtc(),
    );
    await _localStore.setString(_vaultRecordKey, jsonEncode(record.toJson()));
    return SignerVaultUnlock(
      nsec: identity.nsec,
      npub: identity.npub,
      publicKeyHex: identity.publicKeyHex,
    );
  }

  Future<SignerVaultUnlock> unlock({required String pin}) async {
    _validatePin(pin);
    final record = await loadRecord();
    if (record == null) {
      throw const SignerVaultException('No signer vault exists yet.');
    }
    final deviceSecret = await _secretStore.read(_deviceSecretKey);
    if (deviceSecret == null || deviceSecret.isEmpty) {
      throw const SignerVaultException(
        'Signer vault device secret is missing. Re-import the nsec on this device.',
      );
    }

    try {
      final secretKey = await _deriveKey(
        pin: pin,
        deviceSecret: deviceSecret,
        salt: base64.decode(record.salt),
        iterations: record.iterations,
      );
      final cleartext = await AesGcm.with256bits().decrypt(
        SecretBox(
          base64.decode(record.ciphertext),
          nonce: base64.decode(record.nonce),
          mac: Mac(base64.decode(record.mac)),
        ),
        secretKey: secretKey,
      );
      final nsec = utf8.decode(cleartext);
      final identity = NostrCrypto.importIdentity(nsec);
      return SignerVaultUnlock(
        nsec: identity.nsec,
        npub: identity.npub,
        publicKeyHex: identity.publicKeyHex,
      );
    } catch (_) {
      throw const SignerVaultException('Invalid PIN or signer vault.');
    }
  }

  Future<void> clear() async {
    await _localStore.remove(_vaultRecordKey);
    await _secretStore.delete(_deviceSecretKey);
  }

  Future<String> _loadOrCreateDeviceSecret() async {
    final existing = await _secretStore.read(_deviceSecretKey);
    if (existing != null && existing.isNotEmpty) return existing;
    final created = base64.encode(_randomBytes(32));
    await _secretStore.write(_deviceSecretKey, created);
    return created;
  }

  Future<SecretKey> _deriveKey({
    required String pin,
    required String deviceSecret,
    required List<int> salt,
    required int iterations,
  }) {
    return Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: iterations,
      bits: 256,
    ).deriveKey(
      secretKey: SecretKey(utf8.encode('$pin:$deviceSecret')),
      nonce: salt,
    );
  }

  void _validatePin(String pin) {
    if (!RegExp(r'^[0-9]{4,12}$').hasMatch(pin)) {
      throw const SignerVaultException('PIN must be 4 to 12 digits.');
    }
  }

  List<int> _randomBytes(int length) {
    final random = Random.secure();
    return List<int>.generate(length, (_) => random.nextInt(256));
  }
}

abstract class SignerVaultLocalStore {
  Future<String?> getString(String key);
  Future<void> setString(String key, String value);
  Future<void> remove(String key);
}

class SharedPreferencesSignerVaultLocalStore implements SignerVaultLocalStore {
  SharedPreferencesSignerVaultLocalStore({SharedPreferencesAsync? preferences})
      : _preferences = preferences ?? SharedPreferencesAsync();

  final SharedPreferencesAsync _preferences;

  @override
  Future<String?> getString(String key) {
    return _preferences.getString(key);
  }

  @override
  Future<void> setString(String key, String value) {
    return _preferences.setString(key, value);
  }

  @override
  Future<void> remove(String key) {
    return _preferences.remove(key);
  }
}

class MemorySignerVaultLocalStore implements SignerVaultLocalStore {
  final Map<String, String> _values = {};

  @override
  Future<String?> getString(String key) async => _values[key];

  @override
  Future<void> setString(String key, String value) async {
    _values[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    _values.remove(key);
  }
}

abstract class SignerVaultSecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class SecureStorageSignerVaultSecretStore implements SignerVaultSecretStore {
  SecureStorageSignerVaultSecretStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) {
    return _storage.read(key: key);
  }

  @override
  Future<void> write(String key, String value) {
    return _storage.write(key: key, value: value);
  }

  @override
  Future<void> delete(String key) {
    return _storage.delete(key: key);
  }
}

class MemorySignerVaultSecretStore implements SignerVaultSecretStore {
  final Map<String, String> _values = {};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }
}

class SignerVaultRecord {
  const SignerVaultRecord({
    required this.version,
    required this.kdf,
    required this.iterations,
    required this.salt,
    required this.nonce,
    required this.ciphertext,
    required this.mac,
    required this.npub,
    required this.publicKeyHex,
    required this.createdAt,
  });

  final int version;
  final String kdf;
  final int iterations;
  final String salt;
  final String nonce;
  final String ciphertext;
  final String mac;
  final String npub;
  final String publicKeyHex;
  final DateTime createdAt;

  static SignerVaultRecord? tryParse(String value) {
    try {
      final json = jsonDecode(value);
      if (json is! Map<String, dynamic>) return null;
      final createdAt = DateTime.tryParse(json['created_at']?.toString() ?? '');
      if (createdAt == null) return null;
      return SignerVaultRecord(
        version: int.tryParse(json['version']?.toString() ?? '') ?? 0,
        kdf: json['kdf']?.toString() ?? '',
        iterations: int.tryParse(json['iterations']?.toString() ?? '') ?? 0,
        salt: json['salt']?.toString() ?? '',
        nonce: json['nonce']?.toString() ?? '',
        ciphertext: json['ciphertext']?.toString() ?? '',
        mac: json['mac']?.toString() ?? '',
        npub: json['npub']?.toString() ?? '',
        publicKeyHex: json['public_key_hex']?.toString() ?? '',
        createdAt: createdAt,
      );
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'version': version,
      'kdf': kdf,
      'iterations': iterations,
      'salt': salt,
      'nonce': nonce,
      'ciphertext': ciphertext,
      'mac': mac,
      'npub': npub,
      'public_key_hex': publicKeyHex,
      'created_at': createdAt.toIso8601String(),
    };
  }
}

class SignerVaultUnlock {
  const SignerVaultUnlock({
    required this.nsec,
    required this.npub,
    required this.publicKeyHex,
  });

  final String nsec;
  final String npub;
  final String publicKeyHex;
}

class SignerVaultException implements Exception {
  const SignerVaultException(this.message);

  final String message;

  @override
  String toString() => message;
}

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Stores explicit manual grants, never document capabilities or signing keys.
class TowerPairingStore {
  bool _revoked = false;
  static const key = 'wingman.tower.manual_pairings.v2';
  String _tuple(String page, String tower, String endpoint, String identity) =>
      jsonEncode([page, tower, endpoint, identity]);
  Future<bool> contains(
      String page, String tower, String endpoint, String identity) async {
    if (identity.isEmpty || _revoked) return false;
    final prefs = await SharedPreferences.getInstance();
    return !_revoked &&
        (prefs.getStringList(key) ?? [])
            .contains(_tuple(page, tower, endpoint, identity));
  }

  Future<void> grant(
      String page, String tower, String endpoint, String identity) async {
    if (identity.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final values = (prefs.getStringList(key) ?? []).toSet();
    values.add(_tuple(page, tower, endpoint, identity));
    await prefs.setStringList(key, values.toList());
    _revoked = false;
  }

  Future<void> remove(
      String page, String tower, String endpoint, String identity) async {
    _revoked = true;
    final prefs = await SharedPreferences.getInstance();
    final values = prefs.getStringList(key) ?? [];
    values.remove(_tuple(page, tower, endpoint, identity));
    await prefs.setStringList(key, values);
  }

  Future<void> clear() async {
    _revoked = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(key);
    } catch (_) {
      // Storage unavailable: this instance remains revoked, never auto-approve.
    }
  }
}

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/app_config.dart';
import 'core/native_core_bridge.dart';
import 'core/signer_vault.dart';
import 'features/browser/signer_store.dart';
import 'features/onboarding/signer_onboarding_screen.dart';
import 'features/shell/shell_home.dart';

class WingmanApp extends StatefulWidget {
  const WingmanApp({
    this.useSignerVault = true,
    this.signerVault,
    this.localFlightDeckUrl = '',
    super.key,
  });

  final bool useSignerVault;
  final SignerVault? signerVault;
  final String localFlightDeckUrl;

  @override
  State<WingmanApp> createState() => _WingmanAppState();
}

class _WingmanAppState extends State<WingmanApp> {
  static const _appConfigKey = 'wingman.app.config.v1';

  AppConfig _config = AppConfig.defaults();
  late final NativeCoreBridge _bridge = NativeCoreBridge();
  late final SignerStore _signerStore = SignerStore();
  late final SignerVault _signerVault = widget.signerVault ?? SignerVault();
  SignerVaultRecord? _vaultRecord;
  bool _checkingVault = true;

  @override
  void initState() {
    super.initState();
    _loadInitialState();
  }

  void _updateConfig(AppConfig config) {
    setState(() {
      _config = config;
    });
    unawaited(_saveAppConfig(config));
  }

  Future<void> _loadInitialState() async {
    final savedConfig = await _loadAppConfig();
    SignerVaultRecord? record;
    if (widget.useSignerVault) {
      record = await _signerVault.loadRecord();
    }
    if (!mounted) return;
    setState(() {
      _config = savedConfig.copyWith(
        deviceSecret: _config.deviceSecret,
        deviceNpub: _config.deviceNpub,
        devicePublicKeyHex: _config.devicePublicKeyHex,
      );
      _vaultRecord = record;
      _checkingVault = false;
    });
  }

  Future<AppConfig> _loadAppConfig() async {
    final defaults = AppConfig.defaults();
    final raw = await SharedPreferencesAsync().getString(_appConfigKey);
    if (raw == null || raw.trim().isEmpty) return defaults;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return defaults;
      return defaults.copyWith(
        towerUrl: _stringValue(decoded, 'tower_url') ?? defaults.towerUrl,
        appNpub: _stringValue(decoded, 'app_npub') ?? defaults.appNpub,
        flightDeckUrl:
            _stringValue(decoded, 'flight_deck_url') ?? defaults.flightDeckUrl,
        workspaceId:
            _stringValue(decoded, 'workspace_id') ?? defaults.workspaceId,
        workspaceServiceNpub: _stringValue(decoded, 'workspace_service_npub') ??
            defaults.workspaceServiceNpub,
        channelId: _stringValue(decoded, 'channel_id') ?? defaults.channelId,
        trustedOrigins: _stringListValue(decoded, 'trusted_origins') ??
            defaults.trustedOrigins,
        rememberNip98Approvals: decoded['remember_nip98_approvals'] is bool
            ? decoded['remember_nip98_approvals'] as bool
            : defaults.rememberNip98Approvals,
        displayExperimentalFlightDeckDriveSync:
            decoded['display_experimental_flight_deck_drive_sync'] is bool
                ? decoded['display_experimental_flight_deck_drive_sync'] as bool
                : defaults.displayExperimentalFlightDeckDriveSync,
      );
    } catch (_) {
      return defaults;
    }
  }

  Future<void> _saveAppConfig(AppConfig config) async {
    final payload = {
      'version': 1,
      'tower_url': config.towerUrl,
      'app_npub': config.appNpub,
      'flight_deck_url': config.flightDeckUrl,
      'workspace_id': config.workspaceId,
      'workspace_service_npub': config.workspaceServiceNpub,
      'channel_id': config.channelId,
      'trusted_origins': config.trustedOrigins,
      'remember_nip98_approvals': config.rememberNip98Approvals,
      'display_experimental_flight_deck_drive_sync':
          config.displayExperimentalFlightDeckDriveSync,
    };
    await SharedPreferencesAsync()
        .setString(_appConfigKey, jsonEncode(payload));
  }

  String? _stringValue(Map<String, dynamic> map, String key) {
    final value = map[key]?.toString().trim();
    return value == null || value.isEmpty ? null : value;
  }

  List<String>? _stringListValue(Map<String, dynamic> map, String key) {
    final value = map[key];
    if (value is! List) return null;
    final items = value
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    return items.isEmpty ? null : items;
  }

  void _unlockSigner(SignerVaultUnlock unlocked) {
    setState(() {
      _config = _config.copyWith(
        deviceSecret: unlocked.nsec,
        deviceNpub: unlocked.npub,
        devicePublicKeyHex: unlocked.publicKeyHex,
      );
    });
  }

  void _logOutSigner() {
    setState(() {
      _config = _config.copyWith(deviceSecret: '');
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Wingman',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF286A5A),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        visualDensity: VisualDensity.standard,
      ),
      home: _home(),
    );
  }

  Widget _home() {
    if (_checkingVault) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (widget.useSignerVault && !_config.hasDeviceSecret) {
      return SignerOnboardingScreen(
        vault: _signerVault,
        record: _vaultRecord,
        onUnlocked: _unlockSigner,
      );
    }
    return ShellHome(
      config: _config,
      localFlightDeckUrl: widget.localFlightDeckUrl,
      bridge: _bridge,
      signerStore: _signerStore,
      onConfigChanged: _updateConfig,
      onLogOut: _logOutSigner,
    );
  }
}

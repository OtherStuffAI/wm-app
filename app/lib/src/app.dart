import 'package:flutter/material.dart';

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
    super.key,
  });

  final bool useSignerVault;
  final SignerVault? signerVault;

  @override
  State<WingmanApp> createState() => _WingmanAppState();
}

class _WingmanAppState extends State<WingmanApp> {
  AppConfig _config = AppConfig.defaults();
  late final NativeCoreBridge _bridge = NativeCoreBridge();
  late final SignerStore _signerStore = SignerStore();
  late final SignerVault _signerVault = widget.signerVault ?? SignerVault();
  SignerVaultRecord? _vaultRecord;
  bool _checkingVault = true;

  @override
  void initState() {
    super.initState();
    _loadSignerVault();
  }

  void _updateConfig(AppConfig config) {
    setState(() {
      _config = config;
    });
  }

  Future<void> _loadSignerVault() async {
    if (!widget.useSignerVault) {
      setState(() {
        _checkingVault = false;
      });
      return;
    }
    final record = await _signerVault.loadRecord();
    if (!mounted) return;
    setState(() {
      _vaultRecord = record;
      _checkingVault = false;
    });
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
      bridge: _bridge,
      signerStore: _signerStore,
      onConfigChanged: _updateConfig,
    );
  }
}

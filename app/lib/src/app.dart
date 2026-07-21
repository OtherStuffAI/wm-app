import 'package:flutter/material.dart';

import 'core/app_config.dart';
import 'core/native_core_bridge.dart';
import 'core/runtime_environment.dart';
import 'features/browser/signer_store.dart';
import 'features/shell/shell_home.dart';

class WingmanApp extends StatefulWidget {
  const WingmanApp({
    this.seedDeviceKeyFromEnvironment = true,
    super.key,
  });

  final bool seedDeviceKeyFromEnvironment;

  @override
  State<WingmanApp> createState() => _WingmanAppState();
}

class _WingmanAppState extends State<WingmanApp> {
  AppConfig _config = AppConfig.defaults();
  late final NativeCoreBridge _bridge = NativeCoreBridge();
  late final SignerStore _signerStore = SignerStore();

  @override
  void initState() {
    super.initState();
    if (widget.seedDeviceKeyFromEnvironment) {
      _seedDeviceKeyFromEnvironment();
    }
  }

  void _updateConfig(AppConfig config) {
    setState(() {
      _config = config;
    });
  }

  Future<void> _seedDeviceKeyFromEnvironment() async {
    final secret = RuntimeEnvironment.wingmanSecret?.trim();
    if (secret == null || secret.isEmpty) return;

    try {
      final identity = await _bridge.importDeviceKey(secret);
      if (!mounted) return;
      setState(() {
        _config = _config.copyWith(
          deviceSecret: secret,
          deviceNpub: identity.npub,
        );
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _config = _config.copyWith(deviceSecret: secret);
      });
    }
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
      home: ShellHome(
        config: _config,
        bridge: _bridge,
        signerStore: _signerStore,
        onConfigChanged: _updateConfig,
      ),
    );
  }
}

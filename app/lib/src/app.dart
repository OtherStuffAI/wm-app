import 'package:flutter/material.dart';

import 'core/app_config.dart';
import 'core/native_core_bridge.dart';
import 'features/browser/signer_store.dart';
import 'features/shell/shell_home.dart';

class WingmanApp extends StatefulWidget {
  const WingmanApp({super.key});

  @override
  State<WingmanApp> createState() => _WingmanAppState();
}

class _WingmanAppState extends State<WingmanApp> {
  AppConfig _config = AppConfig.defaults();
  late final NativeCoreBridge _bridge = NativeCoreBridge();
  late final SignerStore _signerStore = SignerStore();

  void _updateConfig(AppConfig config) {
    setState(() {
      _config = config;
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
      home: ShellHome(
        config: _config,
        bridge: _bridge,
        signerStore: _signerStore,
        onConfigChanged: _updateConfig,
      ),
    );
  }
}

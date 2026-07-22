import 'package:flutter/material.dart';

import '../../core/app_config.dart';
import '../../core/native_core_bridge.dart';

class SetupScreen extends StatefulWidget {
  const SetupScreen({
    required this.config,
    required this.bridge,
    required this.onConfigChanged,
    required this.onClearBrowserData,
    super.key,
  });

  final AppConfig config;
  final NativeCoreBridge bridge;
  final ValueChanged<AppConfig> onConfigChanged;
  final Future<void> Function() onClearBrowserData;

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  late final TextEditingController _towerController;
  late final TextEditingController _appNpubController;
  late final TextEditingController _flightDeckController;
  late final TextEditingController _workspaceController;
  late final TextEditingController _workspaceServiceController;
  late final TextEditingController _channelController;
  late final TextEditingController _registrationSecretController;
  late final TextEditingController _deviceNpubController;
  late final TextEditingController _devicePublicKeyHexController;
  late final TextEditingController _trustedOriginsController;
  late bool _rememberNip98Approvals;
  String? _message;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _towerController = TextEditingController(text: widget.config.towerUrl);
    _appNpubController = TextEditingController(text: widget.config.appNpub);
    _flightDeckController =
        TextEditingController(text: widget.config.flightDeckUrl);
    _workspaceController =
        TextEditingController(text: widget.config.workspaceId);
    _workspaceServiceController =
        TextEditingController(text: widget.config.workspaceServiceNpub);
    _channelController = TextEditingController(text: widget.config.channelId);
    _registrationSecretController =
        TextEditingController(text: widget.config.registrationSecret);
    _deviceNpubController =
        TextEditingController(text: widget.config.deviceNpub);
    _devicePublicKeyHexController =
        TextEditingController(text: widget.config.devicePublicKeyHex);
    _trustedOriginsController = TextEditingController(
      text: widget.config.trustedOrigins.join('\n'),
    );
    _rememberNip98Approvals = widget.config.rememberNip98Approvals;
  }

  @override
  void dispose() {
    _towerController.dispose();
    _appNpubController.dispose();
    _flightDeckController.dispose();
    _workspaceController.dispose();
    _workspaceServiceController.dispose();
    _channelController.dispose();
    _registrationSecretController.dispose();
    _deviceNpubController.dispose();
    _devicePublicKeyHexController.dispose();
    _trustedOriginsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('Setup', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 20),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.cleaning_services_outlined),
          title: const Text('Browser data'),
          subtitle: const Text('Clear cookies, cache, and local storage.'),
          trailing: OutlinedButton(
            onPressed: _busy ? null : _resetBrowserData,
            child: const Text('Reset browser data'),
          ),
        ),
        const SizedBox(height: 14),
        _field(
          controller: _towerController,
          label: 'Tower URL',
          icon: Icons.dns_outlined,
        ),
        _field(
          controller: _appNpubController,
          label: 'Flight Deck App npub',
          icon: Icons.apps,
        ),
        _field(
          controller: _flightDeckController,
          label: 'Flight Deck URL',
          icon: Icons.public,
        ),
        _field(
          controller: _workspaceController,
          label: 'Workspace ID',
          icon: Icons.workspaces_outline,
        ),
        _field(
          controller: _workspaceServiceController,
          label: 'Workspace service npub',
          icon: Icons.badge_outlined,
        ),
        _field(
          controller: _channelController,
          label: 'Default Channel ID',
          icon: Icons.tag,
        ),
        _field(
          controller: _deviceNpubController,
          label: 'Device npub',
          icon: Icons.fingerprint,
        ),
        _field(
          controller: _devicePublicKeyHexController,
          label: 'Device public key hex',
          icon: Icons.tag,
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            widget.config.hasDeviceSecret
                ? Icons.lock_open_outlined
                : Icons.lock_outline,
          ),
          title: const Text('Signer key'),
          subtitle: Text(
            widget.config.hasDeviceSecret
                ? 'Unlocked for this app session. The nsec is not shown or saved in settings.'
                : 'Locked. Restart the app and unlock the signer vault.',
          ),
        ),
        _field(
          controller: _registrationSecretController,
          label: 'Registration signer key',
          icon: Icons.admin_panel_settings_outlined,
          obscureText: true,
        ),
        _field(
          controller: _trustedOriginsController,
          label: 'Trusted origins',
          icon: Icons.verified_user_outlined,
          maxLines: 3,
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _rememberNip98Approvals,
          onChanged: (value) {
            setState(() {
              _rememberNip98Approvals = value;
            });
          },
          title: const Text('Remember NIP-98 approvals'),
          secondary: const Icon(Icons.verified_outlined),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            FilledButton.icon(
              onPressed: _busy ? null : _save,
              icon: const Icon(Icons.save_outlined),
              label: const Text('Save'),
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : _registerDevice,
              icon: const Icon(Icons.how_to_reg_outlined),
              label: const Text('Register device'),
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : _validateChannel,
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('Validate channel'),
            ),
          ],
        ),
        if (_message != null) ...[
          const SizedBox(height: 16),
          Text(_message!),
        ],
      ],
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obscureText = false,
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextField(
        controller: controller,
        obscureText: obscureText,
        maxLines: obscureText ? 1 : maxLines,
        decoration: InputDecoration(
          border: const OutlineInputBorder(),
          prefixIcon: Icon(icon),
          labelText: label,
        ),
      ),
    );
  }

  void _save() {
    final origins = _trustedOriginsController.text
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
    widget.onConfigChanged(_currentConfig().copyWith(trustedOrigins: origins));
    setState(() {
      _message = 'Configuration saved.';
    });
  }

  AppConfig _currentConfig() {
    return widget.config.copyWith(
      towerUrl: _towerController.text.trim(),
      appNpub: _appNpubController.text.trim(),
      flightDeckUrl: _flightDeckController.text.trim(),
      workspaceId: _workspaceController.text.trim(),
      workspaceServiceNpub: _workspaceServiceController.text.trim(),
      channelId: _channelController.text.trim(),
      deviceNpub: _deviceNpubController.text.trim(),
      deviceSecret: widget.config.deviceSecret,
      registrationSecret: _registrationSecretController.text.trim(),
      rememberNip98Approvals: _rememberNip98Approvals,
      devicePublicKeyHex: _devicePublicKeyHexController.text.trim(),
    );
  }

  Future<void> _registerDevice() async {
    _save();
    await _run('Registering device...', () async {
      final result = await widget.bridge.registerDevice(_currentConfig());
      if (!result.ok) return 'Device registration failed: ${result.error}';
      return 'Device registered with Tower.';
    });
  }

  Future<void> _validateChannel() async {
    _save();
    await _run('Validating channel...', () async {
      final result = await widget.bridge.validateChannel(_currentConfig());
      if (!result.ok) return 'Channel validation failed: ${result.error}';
      return 'Channel validated.';
    });
  }

  Future<void> _resetBrowserData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset browser data?'),
        content: const Text(
          'This clears WebView cookies, cache, local storage, and service worker cache. Open tabs remain listed, but sites may sign out.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.cleaning_services_outlined),
            label: const Text('Reset'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _run('Resetting browser data...', () async {
      await widget.onClearBrowserData();
      return 'Browser cookies, cache, and local storage reset.';
    });
  }

  Future<void> _run(
    String progress,
    Future<String> Function() action,
  ) async {
    setState(() {
      _busy = true;
      _message = progress;
    });
    try {
      final message = await action();
      if (!mounted) return;
      setState(() {
        _message = message;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _message = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }
}

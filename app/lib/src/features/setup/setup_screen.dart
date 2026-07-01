import 'package:flutter/material.dart';

import '../../core/app_config.dart';

class SetupScreen extends StatefulWidget {
  const SetupScreen({
    required this.config,
    required this.onConfigChanged,
    super.key,
  });

  final AppConfig config;
  final ValueChanged<AppConfig> onConfigChanged;

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  late final TextEditingController _towerController;
  late final TextEditingController _workspaceController;
  late final TextEditingController _channelController;
  late final TextEditingController _secretController;

  @override
  void initState() {
    super.initState();
    _towerController = TextEditingController(text: widget.config.towerUrl);
    _workspaceController = TextEditingController(text: widget.config.workspaceId);
    _channelController = TextEditingController(text: widget.config.channelId);
    _secretController = TextEditingController(text: widget.config.deviceSecret);
  }

  @override
  void dispose() {
    _towerController.dispose();
    _workspaceController.dispose();
    _channelController.dispose();
    _secretController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('Setup', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 20),
        _field(
          controller: _towerController,
          label: 'Tower URL',
          icon: Icons.dns_outlined,
        ),
        _field(
          controller: _workspaceController,
          label: 'Workspace ID',
          icon: Icons.workspaces_outline,
        ),
        _field(
          controller: _channelController,
          label: 'Default Channel ID',
          icon: Icons.tag,
        ),
        _field(
          controller: _secretController,
          label: 'Device key',
          icon: Icons.key,
          obscureText: true,
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save_outlined),
            label: const Text('Save'),
          ),
        ),
      ],
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obscureText = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextField(
        controller: controller,
        obscureText: obscureText,
        decoration: InputDecoration(
          border: const OutlineInputBorder(),
          prefixIcon: Icon(icon),
          labelText: label,
        ),
      ),
    );
  }

  void _save() {
    widget.onConfigChanged(
      widget.config.copyWith(
        towerUrl: _towerController.text.trim(),
        workspaceId: _workspaceController.text.trim(),
        channelId: _channelController.text.trim(),
        deviceSecret: _secretController.text.trim(),
      ),
    );
  }
}

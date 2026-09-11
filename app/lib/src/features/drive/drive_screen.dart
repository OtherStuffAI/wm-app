import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/app_config.dart';
import '../../core/native_core_bridge.dart';
import 'drive_host.dart';

class DriveScreen extends StatefulWidget {
  const DriveScreen(
      {required this.config, required this.bridge, this.host, super.key});
  final AppConfig config;
  final NativeCoreBridge bridge;
  final DriveHost? host;
  @override
  State<DriveScreen> createState() => _DriveScreenState();
}

class _DriveScreenState extends State<DriveScreen> {
  late final DriveHost host = widget.host ?? DriveHost.shared;
  @override
  void initState() {
    super.initState();
    unawaited(host.configure(widget.config));
  }

  @override
  void didUpdateWidget(covariant DriveScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    unawaited(host.configure(widget.config));
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _add() async {
    final name = TextEditingController(text: 'Shared folder');
    final source = TextEditingController(text: 'Desktop');
    var audience = 'private';
    final approved = await showDialog<bool>(
        context: context,
        builder: (context) => StatefulBuilder(
            builder: (context, set) => AlertDialog(
                    title: const Text('Share a folder'),
                    content: Column(mainAxisSize: MainAxisSize.min, children: [
                      TextField(
                          controller: name,
                          maxLength: 120,
                          decoration:
                              const InputDecoration(labelText: 'Share name')),
                      TextField(
                          controller: source,
                          maxLength: 120,
                          decoration:
                              const InputDecoration(labelText: 'Source name')),
                      SelectableText('Workspace: ${widget.config.workspaceId}'),
                      DropdownButton<String>(
                          value: audience,
                          isExpanded: true,
                          items: const [
                            DropdownMenuItem(
                                value: 'private',
                                child: Text('Only I can read')),
                            DropdownMenuItem(
                                value: 'workspace',
                                child: Text('Anyone in the workspace'))
                          ],
                          onChanged: (v) => set(() => audience = v!)),
                      const Text(
                          'Select the folder in the next window. Hosting stops when you lock or exit WM App.')
                    ]),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Cancel')),
                      FilledButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('Choose folder'))
                    ])));
    if (approved == true) {
      try {
        await host.add(name.text.trim(), audience, source.text.trim());
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text(
                  'Sharing could not be registered. Check Tower, workspace and FIPS, then retry.')));
        }
      }
    }
    name.dispose();
    source.dispose();
  }

  Future<void> _edit(Map<String, dynamic> share) async {
    final name = TextEditingController(text: share['name']);
    var audience = share['audience'] as String;
    final approved = await showDialog<bool>(
        context: context,
        builder: (context) => StatefulBuilder(
            builder: (context, set) => AlertDialog(
                    title: const Text('Edit share'),
                    content: Column(mainAxisSize: MainAxisSize.min, children: [
                      TextField(
                          controller: name,
                          maxLength: 120,
                          decoration:
                              const InputDecoration(labelText: 'Share name')),
                      DropdownButton<String>(
                          value: audience,
                          items: const [
                            DropdownMenuItem(
                                value: 'private',
                                child: Text('Only I can read')),
                            DropdownMenuItem(
                                value: 'workspace',
                                child: Text('Anyone in the workspace'))
                          ],
                          onChanged: (v) => set(() => audience = v!))
                    ]),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Cancel')),
                      FilledButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('Save and share'))
                    ])));
    if (approved == true) {
      try {
        await host.updateShare(share, name.text.trim(), audience);
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text(
                  'Could not update sharing. Retry when Tower is available.')));
        }
      }
    }
    name.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: host,
      builder: (context, _) =>
          ListView(padding: const EdgeInsets.all(24), children: [
            Text('Shared folders',
                style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 12),
            Text(host.supported
                ? host.message
                : 'Browse shared folders in Flight Deck. Phone background hosting is not supported.'),
            const SizedBox(height: 12),
            if (host.supported)
              Wrap(spacing: 12, children: [
                FilledButton.icon(
                    onPressed:
                        widget.config.hasWorkspace && host.endpoint != null
                            ? _add
                            : null,
                    icon: const Icon(Icons.create_new_folder),
                    label: const Text('Share folder')),
                OutlinedButton.icon(
                    onPressed: () async {
                      try {
                        await host.configure(widget.config);
                        await host.refreshPolicies();
                        for (final s in host.visible) {
                          await host.publish(s);
                        }
                      } catch (_) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                              content: Text(
                                  'Tower unavailable. Local stop sharing still applies.')));
                        }
                      }
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry registration'))
              ]),
            if (!widget.config.hasWorkspace)
              const Text('Choose a Tower workspace in Setup first.'),
            for (final s in host.visible)
              ListTile(
                  leading: const Icon(Icons.folder_shared),
                  title: Text(s['name']),
                  subtitle: Text(
                      '${s['root']}\n${s['audience'] == 'private' ? 'Only I can read' : 'Anyone in the workspace'} · ${s['enabled'] == true ? 'Sharing' : 'Stopped'}'),
                  isThreeLine: true,
                  onTap: () => _edit(s),
                  trailing: s['enabled'] == true
                      ? TextButton(
                          onPressed: () => host.disable(s),
                          child: const Text('Stop sharing'))
                      : null)
          ]));
}

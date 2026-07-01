import 'package:flutter/material.dart';

import '../../core/app_config.dart';
import '../../core/native_core_bridge.dart';

class DriveScreen extends StatefulWidget {
  const DriveScreen({
    required this.config,
    required this.bridge,
    super.key,
  });

  final AppConfig config;
  final NativeCoreBridge bridge;

  @override
  State<DriveScreen> createState() => _DriveScreenState();
}

class _DriveScreenState extends State<DriveScreen> {
  late Future<DriveListing> _listing = widget.bridge.listDrive(widget.config);
  String? _syncMessage;
  bool _syncing = false;

  @override
  void didUpdateWidget(covariant DriveScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.config != widget.config) {
      _listing = widget.bridge.listDrive(widget.config);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DriveListing>(
      future: _listing,
      builder: (context, snapshot) {
        final listing = snapshot.data;
        final items = listing?.items ?? const <DriveItem>[];
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text('Drive', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 8),
            Text(listing?.message ?? 'Loading Drive metadata...'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              children: [
                FilledButton.icon(
                  onPressed: widget.config.canSync && !_syncing ? _syncOnce : null,
                  icon: const Icon(Icons.sync),
                  label: const Text('Sync'),
                ),
                OutlinedButton.icon(
                  onPressed: _refresh,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Refresh'),
                ),
              ],
            ),
            if (_syncMessage != null) ...[
              const SizedBox(height: 12),
              Text(_syncMessage!),
            ],
            const SizedBox(height: 20),
            for (final item in items)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  item.kind == DriveItemKind.folder
                      ? Icons.folder
                      : Icons.description_outlined,
                ),
                title: Text(item.name),
                subtitle: Text(item.path),
                trailing: Text(item.localState),
              ),
          ],
        );
      },
    );
  }

  void _refresh() {
    setState(() {
      _listing = widget.bridge.listDrive(widget.config);
    });
  }

  Future<void> _syncOnce() async {
    setState(() {
      _syncing = true;
      _syncMessage = 'Syncing...';
    });
    final result = await widget.bridge.syncOnce(widget.config);
    if (!mounted) return;
    setState(() {
      _syncing = false;
      _syncMessage = result.ok ? 'Sync complete.' : 'Sync failed: ${result.error}';
      _listing = widget.bridge.listDrive(widget.config);
    });
  }
}

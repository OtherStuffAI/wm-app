import 'package:flutter/material.dart';

import '../../core/app_config.dart';
import '../../core/native_core_bridge.dart';

class DriveScreen extends StatelessWidget {
  const DriveScreen({
    required this.config,
    required this.bridge,
    super.key,
  });

  final AppConfig config;
  final NativeCoreBridge bridge;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DriveListing>(
      future: bridge.listDrive(config),
      builder: (context, snapshot) {
        final listing = snapshot.data;
        final items = listing?.items ?? const <DriveItem>[];
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text('Drive', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 8),
            Text(listing?.message ?? 'Loading Drive metadata...'),
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
}

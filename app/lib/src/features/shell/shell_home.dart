import 'package:flutter/material.dart';

import '../../core/app_config.dart';
import '../../core/native_core_bridge.dart';
import '../browser/browser_screen.dart';
import '../drive/drive_screen.dart';
import '../setup/setup_screen.dart';
import '../status/status_screen.dart';

class ShellHome extends StatefulWidget {
  const ShellHome({
    required this.config,
    required this.bridge,
    required this.onConfigChanged,
    super.key,
  });

  final AppConfig config;
  final NativeCoreBridge bridge;
  final ValueChanged<AppConfig> onConfigChanged;

  @override
  State<ShellHome> createState() => _ShellHomeState();
}

class _ShellHomeState extends State<ShellHome> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    const destinations = [
      NavigationDestination(
        icon: Icon(Icons.tune),
        selectedIcon: Icon(Icons.tune),
        label: 'Setup',
      ),
      NavigationDestination(
        icon: Icon(Icons.folder_outlined),
        selectedIcon: Icon(Icons.folder),
        label: 'Drive',
      ),
      NavigationDestination(
        icon: Icon(Icons.public),
        selectedIcon: Icon(Icons.public),
        label: 'Browser',
      ),
      NavigationDestination(
        icon: Icon(Icons.monitor_heart_outlined),
        selectedIcon: Icon(Icons.monitor_heart),
        label: 'Status',
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Wingman'),
        centerTitle: false,
      ),
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _selectedIndex,
            labelType: NavigationRailLabelType.all,
            destinations: destinations
                .map(
                  (destination) => NavigationRailDestination(
                    icon: destination.icon,
                    selectedIcon: destination.selectedIcon ?? destination.icon,
                    label: Text(destination.label),
                  ),
                )
                .toList(),
            onDestinationSelected: (index) {
              setState(() {
                _selectedIndex = index;
              });
            },
          ),
          const VerticalDivider(width: 1),
          Expanded(child: _screenForIndex()),
        ],
      ),
    );
  }

  Widget _screenForIndex() {
    return switch (_selectedIndex) {
      0 => SetupScreen(
          config: widget.config,
          bridge: widget.bridge,
          onConfigChanged: widget.onConfigChanged,
        ),
      1 => DriveScreen(
          config: widget.config,
          bridge: widget.bridge,
        ),
      2 => BrowserScreen(
          config: widget.config,
          bridge: widget.bridge,
        ),
      _ => StatusScreen(
          config: widget.config,
          bridge: widget.bridge,
        ),
    };
  }
}

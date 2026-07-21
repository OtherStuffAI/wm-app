import 'package:flutter/material.dart';

import '../../core/app_config.dart';
import '../../core/native_core_bridge.dart';
import '../browser/browser_screen.dart';
import '../browser/signer_store.dart';
import '../drive/drive_screen.dart';
import '../signer/signer_screen.dart';
import '../setup/setup_screen.dart';
import '../status/status_screen.dart';

class ShellHome extends StatefulWidget {
  const ShellHome({
    required this.config,
    required this.bridge,
    required this.signerStore,
    required this.onConfigChanged,
    super.key,
  });

  final AppConfig config;
  final NativeCoreBridge bridge;
  final SignerStore signerStore;
  final ValueChanged<AppConfig> onConfigChanged;

  @override
  State<ShellHome> createState() => _ShellHomeState();
}

class _ShellHomeState extends State<ShellHome> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  ShellSurface _selectedSurface = ShellSurface.browser;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      drawer: _buildDrawer(context),
      body: _screenForSurface(),
    );
  }

  Widget _buildDrawer(BuildContext context) {
    return NavigationDrawer(
      selectedIndex: _drawerIndexForSurface(_selectedSurface),
      onDestinationSelected: (index) {
        Navigator.of(context).pop();
        final surface = _surfaceForDrawerIndex(index);
        if (surface == null) return;
        _selectSurface(surface);
      },
      children: const [
        Padding(
          padding: EdgeInsets.fromLTRB(28, 24, 16, 16),
          child: Text('Wingman'),
        ),
        NavigationDrawerDestination(
          icon: Icon(Icons.public),
          selectedIcon: Icon(Icons.public),
          label: Text('Browser'),
        ),
        NavigationDrawerDestination(
          icon: Icon(Icons.folder_outlined),
          selectedIcon: Icon(Icons.folder),
          label: Text('Drive'),
        ),
        NavigationDrawerDestination(
          icon: Icon(Icons.shield_outlined),
          selectedIcon: Icon(Icons.shield),
          label: Text('Signer'),
        ),
        NavigationDrawerDestination(
          icon: Icon(Icons.monitor_heart_outlined),
          selectedIcon: Icon(Icons.monitor_heart),
          label: Text('Status'),
        ),
      ],
    );
  }

  Widget _surfaceScaffold({
    required String title,
    required Widget child,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: Theme.of(context).colorScheme.surface,
          elevation: 1,
          child: SafeArea(
            bottom: false,
            child: SizedBox(
              height: 48,
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Open menu',
                    onPressed: _openDrawer,
                    icon: const Icon(Icons.menu),
                  ),
                  Expanded(
                    child: Text(
                      title,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  _AvatarMenu(
                    deviceNpub: widget.config.deviceNpub,
                    onOpenSetup: () => _selectSurface(ShellSurface.setup),
                    onOpenSigner: () => _selectSurface(ShellSurface.signer),
                    onOpenStatus: () => _selectSurface(ShellSurface.status),
                  ),
                ],
              ),
            ),
          ),
        ),
        Expanded(child: child),
      ],
    );
  }

  Widget _screenForSurface() {
    return switch (_selectedSurface) {
      ShellSurface.browser => BrowserScreen(
          config: widget.config,
          bridge: widget.bridge,
          signerStore: widget.signerStore,
          onOpenDrawer: _openDrawer,
          onOpenSetup: () => _selectSurface(ShellSurface.setup),
          onOpenSigner: () => _selectSurface(ShellSurface.signer),
          onOpenStatus: () => _selectSurface(ShellSurface.status),
        ),
      ShellSurface.setup => _surfaceScaffold(
          title: 'Setup',
          child: SetupScreen(
            config: widget.config,
            bridge: widget.bridge,
            onConfigChanged: widget.onConfigChanged,
          ),
        ),
      ShellSurface.drive => _surfaceScaffold(
          title: 'Drive',
          child: DriveScreen(
            config: widget.config,
            bridge: widget.bridge,
          ),
        ),
      ShellSurface.signer => _surfaceScaffold(
          title: 'Signer',
          child: SignerScreen(
            config: widget.config,
            signerStore: widget.signerStore,
          ),
        ),
      ShellSurface.status => _surfaceScaffold(
          title: 'Status',
          child: StatusScreen(
            config: widget.config,
            bridge: widget.bridge,
          ),
        ),
    };
  }

  int? _drawerIndexForSurface(ShellSurface surface) {
    return switch (surface) {
      ShellSurface.browser => 0,
      ShellSurface.drive => 1,
      ShellSurface.signer => 2,
      ShellSurface.status => 3,
      ShellSurface.setup => null,
    };
  }

  ShellSurface? _surfaceForDrawerIndex(int index) {
    return switch (index) {
      0 => ShellSurface.browser,
      1 => ShellSurface.drive,
      2 => ShellSurface.signer,
      3 => ShellSurface.status,
      _ => null,
    };
  }

  void _openDrawer() {
    _scaffoldKey.currentState?.openDrawer();
  }

  void _selectSurface(ShellSurface surface) {
    setState(() {
      _selectedSurface = surface;
    });
  }
}

enum ShellSurface {
  browser,
  drive,
  signer,
  status,
  setup,
}

class _AvatarMenu extends StatelessWidget {
  const _AvatarMenu({
    required this.deviceNpub,
    required this.onOpenSetup,
    required this.onOpenSigner,
    required this.onOpenStatus,
  });

  final String deviceNpub;
  final VoidCallback onOpenSetup;
  final VoidCallback onOpenSigner;
  final VoidCallback onOpenStatus;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_AvatarMenuAction>(
      tooltip: 'Account',
      icon: CircleAvatar(
        radius: 15,
        child: Text(_avatarLabel),
      ),
      onSelected: (action) {
        switch (action) {
          case _AvatarMenuAction.setup:
            onOpenSetup();
          case _AvatarMenuAction.signer:
            onOpenSigner();
          case _AvatarMenuAction.status:
            onOpenStatus();
        }
      },
      itemBuilder: (context) => const [
        PopupMenuItem(
          value: _AvatarMenuAction.setup,
          child: ListTile(
            leading: Icon(Icons.tune),
            title: Text('Setup'),
          ),
        ),
        PopupMenuItem(
          value: _AvatarMenuAction.signer,
          child: ListTile(
            leading: Icon(Icons.shield_outlined),
            title: Text('Signer'),
          ),
        ),
        PopupMenuItem(
          value: _AvatarMenuAction.status,
          child: ListTile(
            leading: Icon(Icons.monitor_heart_outlined),
            title: Text('Status'),
          ),
        ),
      ],
    );
  }

  String get _avatarLabel {
    final trimmed = deviceNpub.trim();
    if (trimmed.isEmpty) return 'W';
    return trimmed.substring(0, 1).toUpperCase();
  }
}

enum _AvatarMenuAction {
  setup,
  signer,
  status,
}

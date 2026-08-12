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
    this.onLogOut,
    super.key,
  });

  final AppConfig config;
  final NativeCoreBridge bridge;
  final SignerStore signerStore;
  final ValueChanged<AppConfig> onConfigChanged;
  final VoidCallback? onLogOut;

  @override
  State<ShellHome> createState() => _ShellHomeState();
}

class _ShellHomeState extends State<ShellHome> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final GlobalKey<BrowserScreenState> _browserKey =
      GlobalKey<BrowserScreenState>();
  ShellSurface _selectedSurface = ShellSurface.browser;
  final ValueNotifier<bool> _browserFocusMode = ValueNotifier(false);
  final ValueNotifier<BrowserBookmarkMenuState> _bookmarkMenuState =
      ValueNotifier(const BrowserBookmarkMenuState.unavailable());

  @override
  void dispose() {
    _browserFocusMode.dispose();
    _bookmarkMenuState.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      drawer: _buildDrawer(context),
      body: IndexedStack(
        index: _surfaceIndex(_selectedSurface),
        children: [
          _browserScreen(),
          _surfaceScaffold(
            title: 'Drive',
            child: DriveScreen(
              config: widget.config,
              bridge: widget.bridge,
            ),
          ),
          _surfaceScaffold(
            title: 'Signer',
            child: SignerScreen(
              config: widget.config,
              signerStore: widget.signerStore,
            ),
          ),
          _surfaceScaffold(
            title: 'Status',
            child: StatusScreen(
              config: widget.config,
              bridge: widget.bridge,
            ),
          ),
          _surfaceScaffold(
            title: 'Setup',
            child: SetupScreen(
              config: widget.config,
              bridge: widget.bridge,
              onConfigChanged: widget.onConfigChanged,
              onClearBrowserData: _clearBrowserData,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDrawer(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: _browserFocusMode,
      builder: (context, browserFocused, _) {
        return ValueListenableBuilder<BrowserBookmarkMenuState>(
          valueListenable: _bookmarkMenuState,
          builder: (context, bookmarkState, _) => NavigationDrawer(
            selectedIndex: _drawerIndexForSurface(_selectedSurface),
            onDestinationSelected: (index) {
              Navigator.of(context).pop();
              final surface = _surfaceForDrawerIndex(index);
              if (surface == null) return;
              _selectSurface(surface);
            },
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(28, 24, 16, 16),
                child: Text('Wingman'),
              ),
              if (_selectedSurface == ShellSurface.browser && browserFocused)
                Semantics(
                  label: 'Show controls',
                  button: true,
                  excludeSemantics: true,
                  child: ListTile(
                    key: const ValueKey('show-controls-drawer-action'),
                    leading: const Icon(Icons.fullscreen_exit),
                    title: const Text('Show controls'),
                    onTap: _showBrowserControls,
                  ),
                ),
              if (_selectedSurface == ShellSurface.browser &&
                  bookmarkState.available)
                Semantics(
                  label: bookmarkState.bookmarked
                      ? 'Remove bookmark for current page'
                      : 'Add bookmark for current page',
                  button: true,
                  excludeSemantics: true,
                  child: ListTile(
                    key: const ValueKey('toggle-bookmark-drawer-action'),
                    leading: Icon(
                      bookmarkState.bookmarked
                          ? Icons.bookmark_remove
                          : Icons.bookmark_add_outlined,
                    ),
                    title: Text(
                      bookmarkState.bookmarked
                          ? 'Remove bookmark'
                          : 'Add bookmark',
                    ),
                    onTap: _toggleActivePageBookmark,
                  ),
                ),
              const NavigationDrawerDestination(
                icon: Icon(Icons.public),
                selectedIcon: Icon(Icons.public),
                label: Text('Browser'),
              ),
              if (widget.config.displayExperimentalFlightDeckDriveSync)
                const NavigationDrawerDestination(
                  icon: Icon(Icons.folder_outlined),
                  selectedIcon: Icon(Icons.folder),
                  label: Text('Drive'),
                ),
              const NavigationDrawerDestination(
                icon: Icon(Icons.shield_outlined),
                selectedIcon: Icon(Icons.shield),
                label: Text('Signer'),
              ),
              const NavigationDrawerDestination(
                icon: Icon(Icons.monitor_heart_outlined),
                selectedIcon: Icon(Icons.monitor_heart),
                label: Text('Status'),
              ),
            ],
          ),
        );
      },
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
                    onLogOut: widget.onLogOut == null ? null : _confirmLogOut,
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

  Widget _browserScreen() {
    return BrowserScreen(
      key: _browserKey,
      config: widget.config,
      bridge: widget.bridge,
      signerStore: widget.signerStore,
      onOpenDrawer: _openDrawer,
      onOpenSetup: () => _selectSurface(ShellSurface.setup),
      onOpenSigner: () => _selectSurface(ShellSurface.signer),
      onOpenStatus: () => _selectSurface(ShellSurface.status),
      onFocusModeChanged: (focused) => _browserFocusMode.value = focused,
      onBookmarkMenuStateChanged: (state) => _bookmarkMenuState.value = state,
      onLogOut: widget.onLogOut == null ? null : _confirmLogOut,
    );
  }

  int _surfaceIndex(ShellSurface surface) {
    return switch (surface) {
      ShellSurface.browser => 0,
      ShellSurface.drive => 1,
      ShellSurface.signer => 2,
      ShellSurface.status => 3,
      ShellSurface.setup => 4,
    };
  }

  int? _drawerIndexForSurface(ShellSurface surface) {
    final driveVisible = widget.config.displayExperimentalFlightDeckDriveSync;
    return switch (surface) {
      ShellSurface.browser => 0,
      ShellSurface.drive => driveVisible ? 1 : null,
      ShellSurface.signer => driveVisible ? 2 : 1,
      ShellSurface.status => driveVisible ? 3 : 2,
      ShellSurface.setup => null,
    };
  }

  ShellSurface? _surfaceForDrawerIndex(int index) {
    final driveVisible = widget.config.displayExperimentalFlightDeckDriveSync;
    if (!driveVisible) {
      return switch (index) {
        0 => ShellSurface.browser,
        1 => ShellSurface.signer,
        2 => ShellSurface.status,
        _ => null,
      };
    }
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

  void _showBrowserControls() {
    Navigator.of(context).pop();
    _browserKey.currentState?.exitFocusMode();
  }

  void _toggleActivePageBookmark() {
    Navigator.of(context).pop();
    _browserKey.currentState?.toggleActivePageBookmark();
  }

  void _selectSurface(ShellSurface surface) {
    setState(() {
      _selectedSurface = surface;
    });
  }

  Future<void> _clearBrowserData() async {
    await _browserKey.currentState?.clearBrowserData();
  }

  Future<void> _confirmLogOut() async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Log out?'),
            content: const Text(
              'This locks the signer and clears the private key from this app session. '
              'The encrypted signer vault stays on this device, so you can unlock it again with your PIN.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.of(context).pop(true),
                icon: const Icon(Icons.logout),
                label: const Text('Log out'),
              ),
            ],
          ),
        ) ??
        false;
    if (confirmed) widget.onLogOut?.call();
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
    this.onLogOut,
  });

  final String deviceNpub;
  final VoidCallback onOpenSetup;
  final VoidCallback onOpenSigner;
  final VoidCallback onOpenStatus;
  final VoidCallback? onLogOut;

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
          case _AvatarMenuAction.logOut:
            onLogOut?.call();
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: _AvatarMenuAction.setup,
          child: ListTile(
            leading: Icon(Icons.tune),
            title: Text('Setup'),
          ),
        ),
        const PopupMenuItem(
          value: _AvatarMenuAction.signer,
          child: ListTile(
            leading: Icon(Icons.shield_outlined),
            title: Text('Signer'),
          ),
        ),
        const PopupMenuItem(
          value: _AvatarMenuAction.status,
          child: ListTile(
            leading: Icon(Icons.monitor_heart_outlined),
            title: Text('Status'),
          ),
        ),
        if (onLogOut != null) ...[
          const PopupMenuDivider(),
          const PopupMenuItem(
            value: _AvatarMenuAction.logOut,
            child: ListTile(
              leading: Icon(Icons.logout),
              title: Text('Log out'),
            ),
          ),
        ],
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
  logOut,
}

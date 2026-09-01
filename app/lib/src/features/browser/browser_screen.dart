import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/app_config.dart';
import '../../core/fips_app_target.dart';
import '../../core/native_core_bridge.dart';
import '../../core/nostr_crypto.dart';
import 'browser_bookmark_store.dart';
import 'nostr_profile_relay_client.dart';
import 'nostr_profile_store.dart';
import 'signer_policy.dart';
import 'signer_store.dart';

class BrowserScreen extends StatefulWidget {
  const BrowserScreen({
    required this.config,
    required this.bridge,
    required this.signerStore,
    required this.onOpenDrawer,
    required this.onOpenSetup,
    required this.onOpenSigner,
    required this.onOpenStatus,
    this.localFlightDeckUrl = '',
    this.onBookmarkMenuStateChanged,
    this.onFocusModeChanged,
    this.onLogOut,
    super.key,
  });

  final AppConfig config;
  final NativeCoreBridge bridge;
  final SignerStore signerStore;
  final VoidCallback onOpenDrawer;
  final VoidCallback onOpenSetup;
  final VoidCallback onOpenSigner;
  final VoidCallback onOpenStatus;
  final String localFlightDeckUrl;
  final ValueChanged<BrowserBookmarkMenuState>? onBookmarkMenuStateChanged;
  final ValueChanged<bool>? onFocusModeChanged;
  final VoidCallback? onLogOut;

  @override
  State<BrowserScreen> createState() => BrowserScreenState();
}

class BrowserScreenState extends State<BrowserScreen> {
  static final Set<Factory<OneSequenceGestureRecognizer>>
      _androidWebViewGestureRecognizers = {
    const Factory<EagerGestureRecognizer>(EagerGestureRecognizer.new),
  };
  final List<BrowserTab> _tabs = [];
  final ScrollController _tabStripController = ScrollController();
  double _tabItemExtent = 194;
  int _activeTabId = 0;
  int _nextTabId = 1;
  Timer? _addressBarHideTimer;
  int _addressBarHideGeneration = 0;
  bool _addressBarVisible = false;
  bool _focusMode = false;
  static const _nip44PolicyTarget = '*';
  static const _newTabAddressReveal = Duration(seconds: 5);
  static const _tabClickAddressReveal = Duration(seconds: 3);
  static const _homeTitle = 'New Tab';
  static const _flightDeckTitle = 'Flight Deck';
  static const _browserSignerKey = 'wingman.browser.last_signer_npub.v1';
  static const _browserTabsKeyPrefix = 'wingman.browser.tabs.v1.';
  final WebViewCookieManager _cookieManager = WebViewCookieManager();
  final NostrProfileStore _profileStore = NostrProfileStore();
  final NostrProfileRelayClient _profileRelayClient = NostrProfileRelayClient();
  final BrowserBookmarkStore _bookmarkStore = BrowserBookmarkStore();
  List<BrowserBookmark> _bookmarks = const [];
  String? _lastWebStateSignerNpub;
  NostrProfile _profile = const NostrProfile();
  Timer? _persistTabsTimer;
  bool _clearingWebState = false;
  bool _restoringTabs = false;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleKeyboardEvent);
    if (_hasLocalFlightDeck) {
      _createTab(
        widget.localFlightDeckUrl,
        activate: true,
        title: _flightDeckTitle,
      );
    } else {
      _createHomeTab(activate: true);
    }
    unawaited(_loadProfile());
    _syncWebStateToSigner(resetTabsOnChange: false);
  }

  @override
  void didUpdateWidget(covariant BrowserScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.config.deviceNpub != widget.config.deviceNpub) {
      unawaited(_loadProfile());
      unawaited(_switchSignerTabs(oldWidget.config.deviceNpub));
    }
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyboardEvent);
    unawaited(_persistTabsNow());
    _persistTabsTimer?.cancel();
    _addressBarHideTimer?.cancel();
    _tabStripController.dispose();
    for (final tab in _tabs) {
      tab.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!_focusMode) _buildTabBar(context),
            Expanded(
              child: Stack(
                key: const ValueKey('browser-content-viewport'),
                fit: StackFit.expand,
                children: [
                  _buildWebViewStack(),
                  if (!_focusMode && _addressBarVisible)
                    Positioned(
                      key: const ValueKey('browser-address-bar-overlay'),
                      top: 0,
                      left: 0,
                      right: 0,
                      child: _buildAddressBar(context),
                    ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildWebViewStack() {
    final stack = IndexedStack(
      index: _activeTabIndex,
      children: [
        for (final tab in _tabs)
          WebViewWidget(
            key: ValueKey(tab.id),
            controller: tab.controller,
            gestureRecognizers: defaultTargetPlatform == TargetPlatform.android
                ? _androidWebViewGestureRecognizers
                : const <Factory<OneSequenceGestureRecognizer>>{},
          ),
      ],
    );
    if (!_focusMode) return stack;
    return SafeArea(bottom: false, child: stack);
  }

  Widget _buildTabBar(BuildContext context) {
    final theme = Theme.of(context);
    final availableWidth = MediaQuery.sizeOf(context).width -
        MediaQuery.paddingOf(context).horizontal;
    // Keep every tab in one viewport while allowing the strip to scroll.
    final tabWidth = (availableWidth - 200).clamp(96.0, 190.0);
    _tabItemExtent = tabWidth + 4;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 42,
          child: Row(
            children: [
              IconButton(
                tooltip: 'Open menu',
                onPressed: widget.onOpenDrawer,
                icon: const Icon(Icons.menu),
              ),
              Expanded(
                child: ReorderableListView.builder(
                  key: const ValueKey('browser-tab-strip'),
                  scrollController: _tabStripController,
                  padding: const EdgeInsets.only(left: 4, right: 12),
                  scrollDirection: Axis.horizontal,
                  itemExtent: _tabItemExtent,
                  buildDefaultDragHandles: false,
                  itemCount: _tabs.length,
                  onReorderItem: _reorderTabs,
                  proxyDecorator: (child, index, animation) {
                    return FadeTransition(
                      opacity: animation.drive(
                        Tween<double>(begin: 0.82, end: 1),
                      ),
                      child: child,
                    );
                  },
                  itemBuilder: (context, index) {
                    final tab = _tabs[index];
                    final active = tab.id == _activeTabId;
                    final button = _BrowserTabButton(
                      title: tab.label,
                      active: active,
                      fipsTransport: tab.isFips,
                      closeable: true,
                      width: tabWidth,
                      onPressed: () => _activateTab(tab.id),
                      onClose: () => _closeTab(tab.id),
                    );
                    return Padding(
                      key: ValueKey('tab-${tab.id}'),
                      padding: const EdgeInsets.only(right: 4),
                      child: _TabReorderHandle(index: index, child: button),
                    );
                  },
                ),
              ),
              IconButton(
                tooltip: 'New tab',
                onPressed: () => _createHomeTab(),
                icon: const Icon(Icons.add),
              ),
              Semantics(
                label: 'Enter Focus Mode',
                button: true,
                excludeSemantics: true,
                child: IconButton(
                  key: const ValueKey('enter-focus-mode-button'),
                  tooltip: 'Enter Focus Mode',
                  onPressed: _enterFocusMode,
                  icon: const Icon(Icons.fullscreen),
                ),
              ),
              _BrowserAvatarMenu(
                deviceNpub: widget.config.deviceNpub,
                profile: _profile,
                onEditProfile: _editProfile,
                onOpenSetup: widget.onOpenSetup,
                onOpenSigner: widget.onOpenSigner,
                onOpenStatus: widget.onOpenStatus,
                onLogOut: widget.onLogOut,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAddressBar(BuildContext context) {
    final tab = _activeTab;
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      elevation: 6,
      shadowColor: theme.colorScheme.shadow,
      shape: Border(
        bottom: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
        child: Row(
          children: [
            IconButton(
              tooltip: 'Back',
              onPressed: tab.canGoBack ? _goBack : null,
              icon: const Icon(Icons.arrow_back),
            ),
            IconButton(
              tooltip: 'Forward',
              onPressed: tab.canGoForward ? _goForward : null,
              icon: const Icon(Icons.arrow_forward),
            ),
            IconButton(
              tooltip: 'Reload',
              onPressed: _reload,
              icon: const Icon(Icons.refresh),
            ),
            Expanded(
              child: TextField(
                controller: tab.addressController,
                focusNode: tab.addressFocusNode,
                onSubmitted: _loadAddress,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.public),
                  hintText: 'Search or enter URL',
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            IconButton.filled(
              tooltip: 'Go',
              onPressed: () => _loadAddress(tab.addressController.text),
              icon: const Icon(Icons.arrow_forward),
            ),
          ],
        ),
      ),
    );
  }

  BrowserTab get _activeTab {
    return _tabs.firstWhere((tab) => tab.id == _activeTabId);
  }

  int get _activeTabIndex {
    final index = _tabs.indexWhere((tab) => tab.id == _activeTabId);
    return index < 0 ? 0 : index;
  }

  BrowserTab? _tabById(int id) {
    for (final tab in _tabs) {
      if (tab.id == id) return tab;
    }
    return null;
  }

  BrowserBookmarkMenuState get _bookmarkMenuState {
    if (_tabs.isEmpty) return const BrowserBookmarkMenuState.unavailable();
    final tab = _activeTab;
    final url = canonicalBrowserBookmarkUrl(
      tab.isHome ? null : tab.currentUrl ?? tab.addressController.text,
    );
    if (url == null) return const BrowserBookmarkMenuState.unavailable();
    return BrowserBookmarkMenuState(
      available: true,
      bookmarked: _isLocalFlightDeckUrl(url) ||
          _bookmarks.any((bookmark) => bookmark.url == url),
    );
  }

  bool get _hasLocalFlightDeck =>
      canonicalBrowserBookmarkUrl(widget.localFlightDeckUrl) != null;

  BrowserBookmark? get _localFlightDeckBookmark {
    final url = canonicalBrowserBookmarkUrl(widget.localFlightDeckUrl);
    if (url == null) return null;
    return BrowserBookmark(title: _flightDeckTitle, url: url);
  }

  List<BrowserBookmark> get _visibleBookmarks {
    final flightDeck = _localFlightDeckBookmark;
    if (flightDeck == null) return _bookmarks;
    return [
      flightDeck,
      for (final bookmark in _bookmarks)
        if (!_isLocalFlightDeckUrl(bookmark.url)) bookmark,
    ];
  }

  bool _isLocalFlightDeckUrl(String? value) {
    final localOrigin = SignerPolicy.normalizeOrigin(widget.localFlightDeckUrl);
    return localOrigin.isNotEmpty &&
        SignerPolicy.normalizeOrigin(value ?? '') == localOrigin;
  }

  SignerPolicy get _signerPolicy => SignerPolicy(
        trustedOrigins: [
          ...widget.config.effectiveTrustedOrigins(),
          if (_hasLocalFlightDeck) widget.localFlightDeckUrl,
        ],
      );

  void _notifyBookmarkMenuState() {
    widget.onBookmarkMenuStateChanged?.call(_bookmarkMenuState);
  }

  Future<void> toggleActivePageBookmark() async {
    final tab = _activeTab;
    final url = canonicalBrowserBookmarkUrl(
      tab.isHome ? null : tab.currentUrl ?? tab.addressController.text,
    );
    if (url == null) return;
    if (_isLocalFlightDeckUrl(url)) return;
    final existing = _bookmarks.indexWhere((bookmark) => bookmark.url == url);
    if (existing >= 0) {
      _bookmarks = List<BrowserBookmark>.from(_bookmarks)..removeAt(existing);
    } else {
      _bookmarks = [
        ..._bookmarks,
        BrowserBookmark(title: tab.label, url: url),
      ];
    }
    await _persistBookmarks();
    if (!mounted) return;
    _reloadHomeTabs();
    _notifyBookmarkMenuState();
  }

  Future<void> _removeBookmark(String url) async {
    final canonicalUrl = canonicalBrowserBookmarkUrl(url);
    if (_isLocalFlightDeckUrl(canonicalUrl)) return;
    if (canonicalUrl == null ||
        !_bookmarks.any((bookmark) => bookmark.url == canonicalUrl)) {
      return;
    }
    _bookmarks = [
      for (final bookmark in _bookmarks)
        if (bookmark.url != canonicalUrl) bookmark,
    ];
    await _persistBookmarks();
    if (!mounted) return;
    _reloadHomeTabs();
    _notifyBookmarkMenuState();
  }

  Future<bool> _renameBookmark(String url, String title) async {
    final canonicalUrl = canonicalBrowserBookmarkUrl(url);
    if (_isLocalFlightDeckUrl(canonicalUrl)) return false;
    final normalizedTitle = title.trim();
    final index = canonicalUrl == null
        ? -1
        : _bookmarks.indexWhere((bookmark) => bookmark.url == canonicalUrl);
    if (index < 0 || normalizedTitle.isEmpty) return false;
    _bookmarks = List<BrowserBookmark>.from(_bookmarks)
      ..[index] = _bookmarks[index].renamed(normalizedTitle);
    await _persistBookmarks();
    if (!mounted) return true;
    _reloadHomeTabs();
    return true;
  }

  Future<void> _loadBookmarksForSigner(String signerNpub) async {
    final bookmarks = await _bookmarkStore.load(signerNpub);
    if (!mounted || widget.config.deviceNpub.trim() != signerNpub.trim()) {
      return;
    }
    _bookmarks = bookmarks;
    _reloadHomeTabs();
    _notifyBookmarkMenuState();
  }

  Future<void> _persistBookmarks() {
    return _bookmarkStore.save(widget.config.deviceNpub, _bookmarks);
  }

  void _reloadHomeTabs() {
    for (final tab in _tabs.where((tab) => tab.isHome)) {
      _loadHomeForTab(tab);
    }
  }

  void _enterFocusMode() {
    setState(() {
      _focusMode = true;
    });
    widget.onFocusModeChanged?.call(true);
  }

  void exitFocusMode() {
    if (!_focusMode) return;
    setState(() {
      _focusMode = false;
    });
    widget.onFocusModeChanged?.call(false);
  }

  void reloadFlightDeck() {
    for (final tab in _tabs) {
      if (_isLocalFlightDeckUrl(tab.currentUrl ?? tab.addressController.text)) {
        tab.controller.reload();
      }
    }
  }

  Future<void> _loadProfile() async {
    final deviceNpub = widget.config.deviceNpub;
    final profile = await _profileStore.load(deviceNpub);
    if (!mounted || widget.config.deviceNpub != deviceNpub) return;
    setState(() {
      _profile = profile;
    });
    unawaited(_refreshProfileFromRelays(deviceNpub));
  }

  Future<void> _refreshProfileFromRelays(String deviceNpub) async {
    late final String publicKeyHex;
    try {
      publicKeyHex = NostrCrypto.publicKeyHexFromNpub(deviceNpub);
    } catch (_) {
      return;
    }
    final fetched = await _profileRelayClient.fetchProfile(publicKeyHex);
    if (fetched == null) return;
    final cached = await _profileStore.save(deviceNpub, fetched);
    if (!mounted || widget.config.deviceNpub != deviceNpub) return;
    setState(() {
      _profile = cached;
    });
  }

  Future<void> _editProfile() async {
    final deviceNpub = widget.config.deviceNpub;
    final profile = await showDialog<NostrProfile>(
      context: context,
      builder: (context) => _EditNostrProfileDialog(
        deviceNpub: deviceNpub,
        profile: _profile,
      ),
    );
    if (profile == null) return;
    final cachedProfile = await _profileStore.save(deviceNpub, profile);
    if (!mounted || widget.config.deviceNpub != deviceNpub) return;
    setState(() {
      _profile = cachedProfile;
    });
  }

  bool _handleKeyboardEvent(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;
    if (event.logicalKey != LogicalKeyboardKey.tab) return false;
    final keyboard = HardwareKeyboard.instance;
    if (!keyboard.isControlPressed) return false;
    _activateAdjacentTab(keyboard.isShiftPressed ? -1 : 1);
    return true;
  }

  void _activateAdjacentTab(int delta) {
    if (_tabs.length < 2) return;
    final nextIndex = (_activeTabIndex + delta) % _tabs.length;
    final normalizedIndex =
        nextIndex < 0 ? nextIndex + _tabs.length : nextIndex;
    setState(() {
      _activeTabId = _tabs[normalizedIndex].id;
    });
    _revealTab(_activeTabId);
    _refreshNavigationState(_activeTab);
    _schedulePersistTabs();
    _notifyBookmarkMenuState();
  }

  WebViewController _createWebViewController(int id) {
    return WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'WingmanSigner',
        onMessageReceived: (message) => _onSignerMessage(id, message),
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: _onNavigationRequest,
          onUrlChange: (change) => _onUrlChanged(id, change.url),
          onPageFinished: (url) => _onPageFinished(id, url),
        ),
      );
  }

  void _createTab(
    String url, {
    bool activate = true,
    bool persistState = true,
    String? title,
  }) {
    final id = _nextTabId++;
    late final BrowserTab tab;
    final controller = _createWebViewController(id);
    tab = BrowserTab(
      id: id,
      controller: controller,
      addressController: TextEditingController(text: url),
      addressFocusNode: FocusNode(),
      title: title ?? 'New tab',
    );
    tab.addressFocusNode.addListener(() => _onAddressFocusChanged(tab.id));
    setState(() {
      _tabs.add(tab);
      if (activate) {
        _activeTabId = id;
      }
    });
    if (activate) {
      _revealTab(id);
      _revealAddressBar(_newTabAddressReveal);
    }
    _loadAddressForTab(tab, url);
    if (persistState) _schedulePersistTabs();
  }

  void _createHomeTab({
    bool activate = true,
    bool persistState = true,
  }) {
    final id = _nextTabId++;
    late final BrowserTab tab;
    final controller = _createWebViewController(id);
    tab = BrowserTab(
      id: id,
      controller: controller,
      addressController: TextEditingController(),
      addressFocusNode: FocusNode(),
      title: _homeTitle,
      isHome: true,
    );
    tab.addressFocusNode.addListener(() => _onAddressFocusChanged(tab.id));
    setState(() {
      _tabs.add(tab);
      if (activate) {
        _activeTabId = id;
      }
    });
    if (activate) {
      _revealTab(id);
      _revealAddressBar(_newTabAddressReveal);
    }
    _loadHomeForTab(tab);
    if (persistState) _schedulePersistTabs();
  }

  void openTab(String url) {
    _createTab(url);
  }

  void _activateTab(int id) {
    if (_activeTabId == id) {
      _revealTab(id);
      if (_addressBarVisible) {
        _hideAddressBar();
      } else {
        _revealAddressBar(_tabClickAddressReveal);
      }
      _notifyBookmarkMenuState();
      return;
    }
    setState(() {
      _activeTabId = id;
    });
    _revealTab(id);
    _revealAddressBar(_tabClickAddressReveal);
    _refreshNavigationState(_activeTab);
    _schedulePersistTabs();
    _notifyBookmarkMenuState();
  }

  void _revealTab(int id) {
    final index = _tabs.indexWhere((tab) => tab.id == id);
    if (index < 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_tabStripController.hasClients) return;
      final position = _tabStripController.position;
      final centeredOffset = index * _tabItemExtent -
          (position.viewportDimension - _tabItemExtent)
                  .clamp(0.0, double.infinity) /
              2;
      _tabStripController.animateTo(
        centeredOffset.clamp(0.0, position.maxScrollExtent),
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  void _closeTab(int id) {
    final target = _tabById(id);
    if (target == null) return;
    if (_tabs.length == 1) {
      setState(() {
        _tabs.clear();
        _activeTabId = 0;
      });
      target.dispose();
      _createHomeTab();
      return;
    }
    final index = _tabs.indexWhere((tab) => tab.id == id);
    if (index < 0) return;
    final removed = _tabs[index];
    final nextActiveId = id == _activeTabId
        ? _tabs[index == 0 ? 1 : index - 1].id
        : _activeTabId;
    setState(() {
      _tabs.removeAt(index);
      _activeTabId = nextActiveId;
    });
    _revealTab(nextActiveId);
    _revealAddressBar(_tabClickAddressReveal);
    removed.dispose();
    _schedulePersistTabs();
  }

  Future<void> clearBrowserData() {
    return _clearWebState(resetTabs: false);
  }

  Future<void> _switchSignerTabs(String previousSignerNpub) async {
    await _persistTabsForSigner(previousSignerNpub);
    if (!mounted) return;
    await _syncWebStateToSigner();
  }

  Future<void> _syncWebStateToSigner({
    bool resetTabsOnChange = true,
  }) async {
    final signerNpub = widget.config.deviceNpub.trim();
    if (signerNpub.isEmpty || _lastWebStateSignerNpub == signerNpub) return;
    _lastWebStateSignerNpub = signerNpub;

    final preferences = SharedPreferencesAsync();
    final previousSignerNpub = await preferences.getString(_browserSignerKey);
    if (!mounted) return;
    if (previousSignerNpub == signerNpub) {
      await _loadBookmarksForSigner(signerNpub);
      await _restoreTabsForSigner(signerNpub);
      return;
    }

    await _clearWebState(
      resetTabs: resetTabsOnChange &&
          previousSignerNpub != null &&
          previousSignerNpub.isNotEmpty,
    );
    await preferences.setString(_browserSignerKey, signerNpub);
    await _loadBookmarksForSigner(signerNpub);
    await _restoreTabsForSigner(
      signerNpub,
      resetToHomeWhenMissing: previousSignerNpub != null &&
          previousSignerNpub.isNotEmpty &&
          previousSignerNpub != signerNpub,
    );
  }

  Future<void> _clearWebState({required bool resetTabs}) async {
    if (_clearingWebState) return;
    _clearingWebState = true;
    final tabs = List<BrowserTab>.from(_tabs);
    try {
      try {
        await _cookieManager.clearCookies();
      } catch (_) {}
      for (final tab in tabs) {
        try {
          await tab.controller.clearCache();
        } catch (_) {}
        try {
          await tab.controller.clearLocalStorage();
        } catch (_) {}
      }
    } finally {
      _clearingWebState = false;
    }
    if (!mounted || !resetTabs) return;
    _resetTabsToDefault(persistState: false);
  }

  void _resetTabsToDefault({required bool persistState}) {
    final tabs = List<BrowserTab>.from(_tabs);
    for (final tab in tabs) {
      tab.dispose();
    }
    setState(() {
      _tabs.clear();
      _activeTabId = 0;
      _nextTabId = 1;
      _addressBarVisible = false;
      _addressBarHideTimer?.cancel();
    });
    final wasRestoringTabs = _restoringTabs;
    if (!persistState) _restoringTabs = true;
    if (_hasLocalFlightDeck) {
      _createTab(
        widget.localFlightDeckUrl,
        activate: true,
        persistState: persistState,
        title: _flightDeckTitle,
      );
    } else {
      _createHomeTab(activate: true, persistState: persistState);
    }
    _restoringTabs = wasRestoringTabs;
  }

  Future<void> _restoreTabsForSigner(
    String signerNpub, {
    bool resetToHomeWhenMissing = false,
  }) async {
    final key = _tabsStorageKey(signerNpub);
    if (key == null) {
      if (resetToHomeWhenMissing) {
        _resetTabsToDefault(persistState: true);
      }
      return;
    }
    final raw = await SharedPreferencesAsync().getString(key);
    if (!mounted) return;
    final snapshot = _BrowserTabsSnapshot.tryParse(raw);
    if (snapshot == null || snapshot.tabs.isEmpty) {
      if (resetToHomeWhenMissing) {
        _resetTabsToDefault(persistState: true);
      }
      return;
    }

    _restoringTabs = true;
    final oldTabs = List<BrowserTab>.from(_tabs);
    for (final tab in oldTabs) {
      tab.dispose();
    }
    setState(() {
      _tabs.clear();
      _activeTabId = 0;
      _nextTabId = 1;
      _addressBarVisible = false;
      _addressBarHideTimer?.cancel();
    });

    for (final tab in snapshot.tabs) {
      // Version 1 snapshots predate the packaged Flight Deck. Seed it once on
      // upgrade, then version 2 persistence remembers if the user closes it.
      if (_tabs.isEmpty &&
          snapshot.version < 2 &&
          _hasLocalFlightDeck &&
          !snapshot.tabs.any((saved) => _isLocalFlightDeckUrl(saved.url))) {
        _createTab(
          widget.localFlightDeckUrl,
          activate: false,
          persistState: false,
          title: _flightDeckTitle,
        );
      }
      if (tab.isHome || tab.url == null || tab.url!.isEmpty) {
        _createHomeTab(activate: false, persistState: false);
      } else {
        _createTab(tab.url!, activate: false, persistState: false);
      }
      final restored = _tabs.last;
      if (tab.title != null && tab.title!.trim().isNotEmpty) {
        restored.title = tab.title!.trim();
      }
    }

    final seededFlightDeck = snapshot.version < 2 &&
        _hasLocalFlightDeck &&
        _tabs.isNotEmpty &&
        _isLocalFlightDeckUrl(_tabs.first.currentUrl) &&
        !snapshot.tabs.any((saved) => _isLocalFlightDeckUrl(saved.url));
    final activeIndex = seededFlightDeck
        ? 0
        : snapshot.activeIndex.clamp(0, _tabs.length - 1).toInt();
    setState(() {
      _activeTabId = _tabs[activeIndex].id;
    });
    _restoringTabs = false;
  }

  void _schedulePersistTabs() {
    if (_restoringTabs) return;
    _persistTabsTimer?.cancel();
    _persistTabsTimer = Timer(const Duration(milliseconds: 100), () {
      unawaited(_persistTabsNow());
    });
  }

  Future<void> _persistTabsNow() {
    return _persistTabsForSigner(widget.config.deviceNpub);
  }

  Future<void> _persistTabsForSigner(String signerNpub) async {
    if (_restoringTabs) return;
    final key = _tabsStorageKey(signerNpub);
    if (key == null || _tabs.isEmpty) return;
    final snapshot = _BrowserTabsSnapshot(
      version: 2,
      activeIndex: _activeTabIndex,
      tabs: [
        for (final tab in _tabs)
          _BrowserTabSnapshot(
            title: tab.title,
            url: tab.isHome
                ? null
                : (tab.currentUrl ?? tab.addressController.text).trim(),
            isHome: tab.isHome,
          ),
      ],
    );
    await SharedPreferencesAsync().setString(
      key,
      jsonEncode(snapshot.toJson()),
    );
  }

  String? _tabsStorageKey(String signerNpub) {
    final normalized = signerNpub.trim();
    if (normalized.isEmpty) return null;
    return '$_browserTabsKeyPrefix$normalized';
  }

  void _reload() {
    final tab = _activeTab;
    if (tab.isHome) {
      _loadHomeForTab(tab);
      return;
    }
    final uri = Uri.tryParse(tab.currentUrl ?? tab.addressController.text);
    if (uri != null && uri.hasScheme && uri.host.isNotEmpty) {
      tab.controller.reload();
    } else {
      _loadAddress(tab.addressController.text);
    }
  }

  Future<void> _goBack() async {
    final tab = _activeTab;
    if (!await tab.controller.canGoBack()) return;
    await tab.controller.goBack();
    await _refreshNavigationState(tab);
  }

  Future<void> _goForward() async {
    final tab = _activeTab;
    if (!await tab.controller.canGoForward()) return;
    await tab.controller.goForward();
    await _refreshNavigationState(tab);
  }

  void _loadAddress(String value) {
    final tab = _activeTab;
    _loadAddressForTab(tab, value, hideAddressBarAfterLoad: true);
  }

  void _loadAddressForTab(
    BrowserTab tab,
    String value, {
    bool hideAddressBarAfterLoad = false,
  }) {
    final normalized = _normalizeAddress(value);
    final uri = Uri.tryParse(normalized);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      setState(() {
        tab.message = 'Enter a valid website URL.';
      });
      return;
    }
    setState(() {
      tab.isHome = false;
      tab.currentUrl = uri.toString();
      tab.addressController.text = tab.currentUrl!;
      tab.title = _titleForUrl(tab.currentUrl!);
      tab.message = null;
      if (hideAddressBarAfterLoad) {
        _addressBarHideTimer?.cancel();
        _addressBarVisible = false;
        tab.addressFocusNode.unfocus();
      }
    });
    tab.controller.loadRequest(uri);
    _schedulePersistTabs();
    if (tab.id == _activeTabId) _notifyBookmarkMenuState();
  }

  void _loadHomeForTab(BrowserTab tab) {
    setState(() {
      tab.isHome = true;
      tab.currentUrl = null;
      tab.addressController.clear();
      tab.title = _homeTitle;
      tab.message = null;
    });
    tab.controller.loadHtmlString(
      _homePageHtml(savedBookmarks: _visibleBookmarks),
      baseUrl: 'https://wingman.local/',
    );
    _schedulePersistTabs();
    if (tab.id == _activeTabId) _notifyBookmarkMenuState();
  }

  void _reorderTabs(int oldIndex, int newIndex) {
    if (_tabs.length <= 1) return;
    if (oldIndex < 0 || oldIndex >= _tabs.length) {
      return;
    }
    var destination = newIndex;
    if (oldIndex < destination) destination -= 1;
    destination = destination.clamp(0, _tabs.length - 1);
    if (oldIndex == destination) return;
    setState(() {
      final tab = _tabs.removeAt(oldIndex);
      _tabs.insert(destination, tab);
    });
    _schedulePersistTabs();
  }

  void _onAddressFocusChanged(int tabId) {
    final tab = _tabById(tabId);
    if (tab == null || tab.id != _activeTabId) return;
    if (tab.addressFocusNode.hasFocus) {
      _addressBarHideTimer?.cancel();
      if (!_addressBarVisible && mounted) {
        setState(() {
          _addressBarVisible = true;
        });
      }
      return;
    }
    if (_addressBarVisible) {
      _scheduleAddressBarHide(Duration.zero);
    }
  }

  void _revealAddressBar(Duration duration) {
    _cancelAddressBarHide();
    if (mounted) {
      setState(() {
        _addressBarVisible = true;
      });
    } else {
      _addressBarVisible = true;
    }
    _scheduleAddressBarHide(duration);
  }

  void _hideAddressBar() {
    _cancelAddressBarHide();
    final tab = _activeTab;
    if (tab.addressFocusNode.hasFocus) {
      tab.addressFocusNode.unfocus();
      _cancelAddressBarHide();
    }
    if (!_addressBarVisible) return;
    if (mounted) {
      setState(() {
        _addressBarVisible = false;
      });
    } else {
      _addressBarVisible = false;
    }
  }

  void _cancelAddressBarHide() {
    _addressBarHideTimer?.cancel();
    _addressBarHideTimer = null;
    _addressBarHideGeneration += 1;
  }

  void _scheduleAddressBarHide(Duration duration) {
    _addressBarHideTimer?.cancel();
    final generation = ++_addressBarHideGeneration;
    _addressBarHideTimer = Timer(duration, () {
      if (!mounted || generation != _addressBarHideGeneration) return;
      _addressBarHideTimer = null;
      final tab = _activeTab;
      if (tab.addressFocusNode.hasFocus) return;
      setState(() {
        _addressBarVisible = false;
      });
    });
  }

  String _normalizeAddress(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return trimmed;
    final uri = Uri.tryParse(trimmed);
    if (uri != null && uri.hasScheme) return trimmed;
    if (trimmed.contains('.') && !trimmed.contains(' ')) {
      return 'https://$trimmed';
    }
    return Uri.https('njump.me', '/', {'q': trimmed}).toString();
  }

  String? _normalizeOpenTabUrl(String value, String baseUrl) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    final parsed = Uri.tryParse(trimmed);
    if (parsed != null && parsed.hasScheme && parsed.host.isNotEmpty) {
      return parsed.toString();
    }
    final base = Uri.tryParse(baseUrl);
    if (base == null || !base.hasScheme || base.host.isEmpty) return null;
    return base.resolve(trimmed).toString();
  }

  String _titleForUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) return 'New tab';
    return uri.host;
  }

  Future<void> _refreshNavigationState(BrowserTab tab) async {
    final canGoBack = await tab.controller.canGoBack();
    final canGoForward = await tab.controller.canGoForward();
    if (!mounted || _tabById(tab.id) == null) return;
    setState(() {
      tab.canGoBack = canGoBack;
      tab.canGoForward = canGoForward;
    });
  }

  NavigationDecision _onNavigationRequest(NavigationRequest request) {
    return NavigationDecision.navigate;
  }

  void _onUrlChanged(int tabId, String? url) {
    if (!mounted) return;
    final tab = _tabById(tabId);
    if (tab == null || url == null || url.isEmpty) return;
    if (tab.isHome &&
        (url == 'about:blank' || url == 'https://wingman.local/')) {
      return;
    }
    if (tab.currentUrl == url && tab.addressController.text == url) return;
    setState(() {
      tab.isHome = false;
      tab.currentUrl = url;
      tab.addressController.text = url;
      if (_isLocalFlightDeckUrl(url)) {
        tab.title = _flightDeckTitle;
      }
    });
    _schedulePersistTabs();
    if (tab.id == _activeTabId) _notifyBookmarkMenuState();
  }

  Future<void> _onPageFinished(int tabId, String url) async {
    final tab = _tabById(tabId);
    if (tab == null) return;
    if (tab.isHome &&
        (url == 'about:blank' || url == 'https://wingman.local/')) {
      await _injectTabCapture(tab);
      return;
    }
    final title = await tab.controller.getTitle();
    setState(() {
      tab.isHome = false;
      tab.currentUrl = url;
      tab.addressController.text = url;
      tab.title = _isLocalFlightDeckUrl(url)
          ? _flightDeckTitle
          : title?.trim().isNotEmpty == true
              ? title!.trim()
              : _titleForUrl(url);
    });
    await _refreshNavigationState(tab);
    await _applyFlightDeckDisplayDefaults(tab, url);
    await _injectTabCapture(tab);
    await _injectIfTrusted(tab);
    _schedulePersistTabs();
    if (tab.id == _activeTabId) _notifyBookmarkMenuState();
  }

  Future<void> _applyFlightDeckDisplayDefaults(
    BrowserTab tab,
    String url,
  ) async {
    final pageOrigin = SignerPolicy.normalizeOrigin(url);
    final flightDeckOrigin =
        SignerPolicy.normalizeOrigin(widget.config.flightDeckUrl);
    final localFlightDeckOrigin =
        SignerPolicy.normalizeOrigin(widget.localFlightDeckUrl);
    if (pageOrigin.isEmpty ||
        (pageOrigin != flightDeckOrigin &&
            pageOrigin != localFlightDeckOrigin)) {
      return;
    }
    await tab.controller.runJavaScript('''
(() => {
  const root = document.documentElement;
  if (!root) return;
  root.style.setProperty('-webkit-text-size-adjust', 'none');
  root.style.setProperty('text-size-adjust', 'none');
})();
''');
  }

  String _homePageHtml({required List<BrowserBookmark> savedBookmarks}) {
    final bookmarkCards = savedBookmarks.map((bookmark) {
      final builtInFlightDeck = _isLocalFlightDeckUrl(bookmark.url);
      final bookmarkEditor = builtInFlightDeck
          ? ''
          : '''
          <form class="bookmark-editor" data-wingman-bookmark-editor hidden>
            <label>
              <span class="visually-hidden">Bookmark display name</span>
              <input class="bookmark-title-input" value="${_escapeHtml(bookmark.title)}" data-wingman-original-title="${_escapeHtml(bookmark.title)}" aria-label="Bookmark display name">
            </label>
            <button type="submit">Save</button>
            <button type="button" data-wingman-cancel-bookmark-edit>Cancel</button>
          </form>
          <div class="bookmark-actions">
            <button class="bookmark-edit" type="button" data-wingman-edit-bookmark aria-label="Edit ${_escapeHtml(bookmark.title)} bookmark name" title="Edit bookmark name">Edit</button>
            <button class="bookmark-remove" type="button" data-wingman-remove-bookmark-url="${_escapeHtml(bookmark.url)}" aria-label="Remove ${_escapeHtml(bookmark.title)} bookmark" title="Remove bookmark">Remove</button>
          </div>
''';
      return '''
        <article class="bookmark saved-bookmark">
          <button class="bookmark-open" type="button" data-wingman-bookmark-url="${_escapeHtml(bookmark.url)}" aria-label="Open ${_escapeHtml(bookmark.title)}">
            <span class="bookmark-title">${_escapeHtml(bookmark.title)}</span>
            <span class="bookmark-url">${_escapeHtml(bookmark.url)}</span>
          </button>
          $bookmarkEditor
        </article>
      ''';
    }).join('\n');
    final savedSection = savedBookmarks.isEmpty
        ? '<p class="empty-bookmarks">No saved bookmarks yet. Swipe from the left on a page and choose Add bookmark.</p>'
        : '<section class="grid">$bookmarkCards</section>';
    return '''
<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Wingman New Tab</title>
  <style>
    :root {
      color-scheme: light;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      background: #f7f8f5;
      color: #1d1f1d;
    }
    body {
      margin: 0;
      min-height: 100vh;
      display: grid;
      place-items: start center;
      background: #f7f8f5;
    }
    main {
      width: min(860px, calc(100vw - 32px));
      padding: 56px 0;
    }
    h1 {
      margin: 0 0 20px;
      font-size: 28px;
      font-weight: 650;
    }
    h2 {
      margin: 28px 0 12px;
      font-size: 18px;
    }
    .grid {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(240px, 1fr));
      gap: 12px;
    }
    .bookmark {
      display: grid;
      gap: 8px;
      min-height: 132px;
      padding: 18px;
      border: 1px solid #d8ddd4;
      border-radius: 8px;
      background: #ffffff;
      color: inherit;
      text-decoration: none;
      box-sizing: border-box;
    }
    .bookmark:focus,
    .bookmark:hover {
      border-color: #286a5a;
      outline: none;
    }
    .bookmark-title {
      font-size: 18px;
      font-weight: 650;
      overflow-wrap: anywhere;
    }
    .bookmark-url {
      color: #286a5a;
      font-size: 13px;
      overflow-wrap: anywhere;
    }
    .bookmark-description {
      color: #535b55;
      font-size: 14px;
      line-height: 1.35;
    }
    .saved-bookmark {
      padding: 0;
      overflow: hidden;
    }
    .bookmark-open {
      display: grid;
      gap: 8px;
      min-width: 0;
      padding: 18px;
      border: 0;
      background: transparent;
      color: inherit;
      text-align: left;
      cursor: pointer;
    }
    .bookmark-open:focus-visible,
    .bookmark-edit:focus-visible,
    .bookmark-remove:focus-visible {
      outline: 2px solid #286a5a;
      outline-offset: -2px;
    }
    .bookmark-actions {
      display: grid;
      grid-template-columns: 1fr 1fr;
      border-top: 1px solid #d8ddd4;
    }
    .bookmark-edit,
    .bookmark-remove {
      min-height: 44px;
      border: 0;
      background: #f7f8f5;
      cursor: pointer;
    }
    .bookmark-edit {
      color: #286a5a;
      border-right: 1px solid #d8ddd4;
    }
    .bookmark-remove { color: #7a2e2e; }
    .bookmark-editor {
      grid-template-columns: minmax(0, 1fr) auto auto;
      gap: 6px;
      padding: 10px;
      border-top: 1px solid #d8ddd4;
    }
    .bookmark-editor:not([hidden]) { display: grid; }
    .bookmark-title-input {
      width: 100%;
      min-width: 0;
      padding: 8px;
      box-sizing: border-box;
    }
    .visually-hidden {
      position: absolute;
      width: 1px;
      height: 1px;
      padding: 0;
      margin: -1px;
      overflow: hidden;
      clip: rect(0, 0, 0, 0);
      white-space: nowrap;
      border: 0;
    }
    .empty-bookmarks {
      color: #535b55;
      line-height: 1.45;
    }
  </style>
</head>
<body>
  <main>
    <h1>Wingman</h1>
    <p class="empty-bookmarks">Browser and Nostr signer ready. Enter a website in the address bar to begin.</p>
    <h2>Bookmarks</h2>
    $savedSection
  </main>
  <script>
    (() => {
      let seq = 0;
      const closeEditor = (card) => {
        const editor = card.querySelector('[data-wingman-bookmark-editor]');
        const actions = card.querySelector('.bookmark-actions');
        const input = card.querySelector('.bookmark-title-input');
        input.value = input.dataset.wingmanOriginalTitle;
        editor.hidden = true;
        actions.hidden = false;
      };
      document.addEventListener('click', (event) => {
        const target = event.target;
        const editBookmark = target && target.closest
          ? target.closest('[data-wingman-edit-bookmark]')
          : null;
        const cancelEdit = target && target.closest
          ? target.closest('[data-wingman-cancel-bookmark-edit]')
          : null;
        if (editBookmark || cancelEdit) {
          event.preventDefault();
          const card = (editBookmark || cancelEdit).closest('.saved-bookmark');
          if (cancelEdit) {
            closeEditor(card);
          } else {
            card.querySelector('[data-wingman-bookmark-editor]').hidden = false;
            card.querySelector('.bookmark-actions').hidden = true;
            const input = card.querySelector('.bookmark-title-input');
            input.focus();
            input.select();
          }
          return;
        }
        const openBookmark = target && target.closest
          ? target.closest('[data-wingman-bookmark-url]')
          : null;
        const removeBookmark = target && target.closest
          ? target.closest('[data-wingman-remove-bookmark-url]')
          : null;
        const action = removeBookmark || openBookmark;
        if (!action || !window.WingmanSigner) return;
        event.preventDefault();
        let href;
        try {
          href = new URL(
            removeBookmark?.dataset.wingmanRemoveBookmarkUrl ||
            openBookmark?.dataset.wingmanBookmarkUrl,
            window.location.href,
          ).href;
        } catch (_) {
          return;
        }
        window.WingmanSigner.postMessage(JSON.stringify({
          id: `home-tab-\${++seq}`,
          method: removeBookmark
            ? 'removeBookmark'
            : 'navigateTab',
          params: { url: href },
        }));
      }, true);
      document.addEventListener('keydown', (event) => {
        if (event.key !== 'Escape') return;
        const editor = event.target.closest?.('[data-wingman-bookmark-editor]');
        if (!editor) return;
        event.preventDefault();
        closeEditor(editor.closest('.saved-bookmark'));
      });
      document.addEventListener('submit', (event) => {
        const editor = event.target.closest?.('[data-wingman-bookmark-editor]');
        if (!editor) return;
        event.preventDefault();
        const card = editor.closest('.saved-bookmark');
        const input = editor.querySelector('.bookmark-title-input');
        const title = input.value.trim();
        if (!title) {
          closeEditor(card);
          return;
        }
        const url = card.querySelector('[data-wingman-bookmark-url]')
          ?.dataset.wingmanBookmarkUrl;
        if (!url || !window.WingmanSigner) return;
        window.WingmanSigner.postMessage(JSON.stringify({
          id: `home-tab-\${++seq}`,
          method: 'renameBookmark',
          params: { url, title },
        }));
      });
    })();
  </script>
</body>
</html>
''';
  }

  String _escapeHtml(String value) {
    return value
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;');
  }

  Future<void> _injectIfTrusted(BrowserTab tab) async {
    final url = tab.currentUrl ?? widget.config.flightDeckUrl;
    final origin = SignerPolicy.normalizeOrigin(url);
    final policy = _signerPolicy;
    if (!policy.canInject(url)) {
      setState(() {
        tab.message = 'Signer withheld for unsupported page: $url';
      });
      return;
    }
    await tab.controller.runJavaScript(
      _bridgeScript(widget.config.devicePublicKeyHex),
    );
    setState(() {
      tab.message = 'window.nostr injected for $origin';
    });
  }

  Future<void> _onSignerMessage(int tabId, JavaScriptMessage message) async {
    final tab = _tabById(tabId);
    if (tab == null) return;
    final payload = _decodeMessage(message.message);
    if (payload == null) return;
    final requestId = payload['id']?.toString() ?? '';
    final method = payload['method']?.toString() ?? '';
    if (requestId.isEmpty || method.isEmpty) return;

    if (method == 'openTab') {
      final params = payload['params'] is Map<String, dynamic>
          ? payload['params'] as Map<String, dynamic>
          : <String, dynamic>{};
      final url = params['url']?.toString() ?? '';
      final normalized = _normalizeOpenTabUrl(
        url,
        tab.currentUrl ?? widget.config.flightDeckUrl,
      );
      if (normalized == null) {
        await _resolveSignerRequest(
          tab,
          requestId,
          {'error': 'invalid new tab URL'},
        );
        return;
      }
      _createTab(normalized);
      await _resolveSignerRequest(tab, requestId, {'result': true});
      return;
    }

    if (method == 'navigateTab' ||
        method == 'removeBookmark' ||
        method == 'renameBookmark') {
      final params = payload['params'] is Map<String, dynamic>
          ? payload['params'] as Map<String, dynamic>
          : <String, dynamic>{};
      final url = canonicalBrowserBookmarkUrl(params['url']?.toString());
      if (url == null) {
        await _resolveSignerRequest(
          tab,
          requestId,
          {'error': 'invalid bookmark URL'},
        );
        return;
      }
      if (method == 'renameBookmark') {
        final title = params['title'];
        if (title is! String || title.trim().isEmpty) {
          await _resolveSignerRequest(
            tab,
            requestId,
            {'error': 'invalid bookmark title'},
          );
          return;
        }
        final renamed = await _renameBookmark(url, title);
        if (!renamed) {
          await _resolveSignerRequest(
            tab,
            requestId,
            {'error': 'bookmark not found'},
          );
          return;
        }
      } else if (method == 'removeBookmark') {
        await _removeBookmark(url);
      } else {
        _loadAddressForTab(tab, url, hideAddressBarAfterLoad: true);
      }
      await _resolveSignerRequest(tab, requestId, {'result': true});
      return;
    }

    if (method == 'getPublicKey') {
      await _resolveSignerRequest(
        tab,
        requestId,
        {'result': widget.config.devicePublicKeyHex},
      );
      return;
    }

    if (method == 'signEvent') {
      final event = payload['params'] is Map<String, dynamic>
          ? payload['params'] as Map<String, dynamic>
          : <String, dynamic>{};
      final pageUrl = tab.currentUrl ?? widget.config.flightDeckUrl;
      final pageOrigin = SignerPolicy.normalizeOrigin(pageUrl);
      if (!_signerPolicy.canSignNip07(pageUrl)) {
        final reason = 'unsupported NIP-07 page origin: $pageOrigin';
        setState(() {
          tab.message = 'Signer denied: $reason';
        });
        await _resolveSignerRequest(tab, requestId, {'error': reason});
        return;
      }
      const operation = 'signEvent';
      final policyTarget = _signEventPolicyTarget(event);
      final policyRule = await widget.signerStore.findPolicyRule(
        pageOrigin: pageOrigin,
        operation: operation,
        target: policyTarget,
        deviceNpub: widget.config.deviceNpub,
      );
      if (policyRule != null && !policyRule.allows) {
        await _recordNip07Audit(
          pageOrigin: pageOrigin,
          targetUrl: pageUrl,
          event: event,
          allowed: false,
          outcome: 'policy_denied',
          reason: 'denied by signer policy',
          rememberedApproval: true,
        );
        await _resolveSignerRequest(
          tab,
          requestId,
          {'error': 'denied by signer policy'},
        );
        return;
      }
      final remembered = policyRule != null && policyRule.allows;
      final approval = remembered
          ? const SignerPromptResult(approved: true)
          : await _confirmSignEvent(event, pageOrigin);
      if (!approval.approved) {
        if (approval.denyAlways) {
          await _rememberSignerPolicy(
            pageOrigin: pageOrigin,
            operation: operation,
            target: policyTarget,
            decision: SignerPolicyRuleDecision.deny,
            label: 'Sign event ${policyTarget.replaceFirst('kind:', 'kind ')}',
          );
        }
        await _recordNip07Audit(
          pageOrigin: pageOrigin,
          targetUrl: pageUrl,
          event: event,
          allowed: false,
          outcome: approval.denyAlways ? 'policy_saved_deny' : 'user_denied',
          reason: approval.denyAlways
              ? 'denied by user and saved as policy'
              : 'denied by user',
        );
        await _resolveSignerRequest(tab, requestId, {'error': 'denied'});
        return;
      }
      if (approval.remember) {
        await _rememberSignerPolicy(
          pageOrigin: pageOrigin,
          operation: operation,
          target: policyTarget,
          decision: SignerPolicyRuleDecision.allow,
          label: 'Sign event ${policyTarget.replaceFirst('kind:', 'kind ')}',
        );
      }
      final result = await widget.bridge.signEvent(
        config: widget.config,
        event: event,
      );
      if (!result.ok) {
        await _recordNip07Audit(
          pageOrigin: pageOrigin,
          targetUrl: pageUrl,
          event: event,
          allowed: false,
          outcome: 'signer_error',
          reason: result.error ?? 'native signer failed',
        );
        await _resolveSignerRequest(tab, requestId, {'error': result.error});
        return;
      }
      await _recordNip07Audit(
        pageOrigin: pageOrigin,
        targetUrl: pageUrl,
        event: event,
        allowed: true,
        outcome: remembered ? 'signed_with_policy' : 'signed',
        rememberedApproval: remembered || approval.remember,
      );
      await _resolveSignerRequest(tab, requestId, {
        'result': result.json,
      });
      return;
    }

    if (method == 'nip44.encrypt' || method == 'nip44.decrypt') {
      await _handleNip44Request(
        tab: tab,
        requestId: requestId,
        method: method,
        params: payload['params'] is Map<String, dynamic>
            ? payload['params'] as Map<String, dynamic>
            : <String, dynamic>{},
      );
      return;
    }

    if (method == 'signNip98') {
      final request = payload['params'] is Map<String, dynamic>
          ? payload['params'] as Map<String, dynamic>
          : <String, dynamic>{};
      final requestMethod = request['httpMethod']?.toString() ?? 'GET';
      final requestUrl = request['url']?.toString() ?? '';
      final requestBody = request['body']?.toString();
      final decision = _signerPolicy.validateNip98(
        pageUrl: tab.currentUrl ?? widget.config.flightDeckUrl,
        targetUrl: requestUrl,
        method: requestMethod,
        body: requestBody,
      );
      if (!decision.allowed) {
        setState(() {
          tab.message = 'Signer denied: ${decision.reason}';
        });
        await _recordSignerAudit(
          decision: decision,
          targetUrl: requestUrl,
          method: requestMethod,
          allowed: false,
          outcome: 'policy_denied',
          reason: decision.reason,
        );
        await _resolveSignerRequest(tab, requestId, {'error': decision.reason});
        return;
      }
      const policyOperation = 'nip98';
      final policyRule = await widget.signerStore.findPolicyRule(
        pageOrigin: decision.pageOrigin,
        operation: policyOperation,
        target: decision.targetOrigin,
        deviceNpub: widget.config.deviceNpub,
      );
      if (policyRule != null && !policyRule.allows) {
        await _recordSignerAudit(
          decision: decision,
          targetUrl: requestUrl,
          method: decision.method,
          allowed: false,
          outcome: 'policy_denied',
          reason: 'denied by signer policy',
          rememberedApproval: true,
        );
        await _resolveSignerRequest(
          tab,
          requestId,
          {'error': 'denied by signer policy'},
        );
        return;
      }
      final rememberedPolicy = policyRule != null && policyRule.allows;
      final rememberedApproval = widget.config.rememberNip98Approvals &&
          await widget.signerStore.hasApproval(
            pageOrigin: decision.pageOrigin,
            targetOrigin: decision.targetOrigin,
            deviceNpub: widget.config.deviceNpub,
          );
      final remembered = rememberedPolicy || rememberedApproval;
      final approval = remembered
          ? const SignerPromptResult(approved: true)
          : await _confirmNip98(request, decision);
      if (!approval.approved) {
        if (approval.denyAlways) {
          await _rememberSignerPolicy(
            pageOrigin: decision.pageOrigin,
            operation: policyOperation,
            target: decision.targetOrigin,
            decision: SignerPolicyRuleDecision.deny,
            label: 'NIP-98 ${decision.pageOrigin} -> ${decision.targetOrigin}',
          );
        }
        await _recordSignerAudit(
          decision: decision,
          targetUrl: requestUrl,
          method: decision.method,
          allowed: false,
          outcome: approval.denyAlways ? 'policy_saved_deny' : 'user_denied',
          reason: approval.denyAlways
              ? 'denied by user and saved as policy'
              : 'denied by user',
        );
        await _resolveSignerRequest(tab, requestId, {'error': 'denied'});
        return;
      }
      if (approval.remember) {
        await _rememberSignerPolicy(
          pageOrigin: decision.pageOrigin,
          operation: policyOperation,
          target: decision.targetOrigin,
          decision: SignerPolicyRuleDecision.allow,
          label: 'NIP-98 ${decision.pageOrigin} -> ${decision.targetOrigin}',
        );
      }
      if (approval.remember && widget.config.rememberNip98Approvals) {
        await widget.signerStore.rememberApproval(
          SignerApproval(
            pageOrigin: decision.pageOrigin,
            targetOrigin: decision.targetOrigin,
            deviceNpub: widget.config.deviceNpub,
            createdAt: DateTime.now().toUtc(),
            label: 'NIP-98 ${decision.pageOrigin}',
          ),
        );
      }
      final result = await widget.bridge.signNip98(
        config: widget.config,
        method: decision.method,
        url: requestUrl,
        body: requestBody,
      );
      if (!result.ok) {
        await _recordSignerAudit(
          decision: decision,
          targetUrl: requestUrl,
          method: decision.method,
          allowed: false,
          outcome: 'signer_error',
          reason: result.error ?? 'native signer failed',
          rememberedApproval: remembered,
        );
        await _resolveSignerRequest(tab, requestId, {'error': result.error});
        return;
      }
      await _recordSignerAudit(
        decision: decision,
        targetUrl: requestUrl,
        method: decision.method,
        allowed: true,
        outcome: remembered ? 'signed_with_remembered_approval' : 'signed',
        rememberedApproval: remembered || approval.remember,
      );
      await _resolveSignerRequest(tab, requestId, {
        'result': result.json['authorization'],
        'event': result.json['event'],
      });
    }
  }

  Map<String, dynamic>? _decodeMessage(String message) {
    try {
      final parsed = jsonDecode(message);
      return parsed is Map<String, dynamic> ? parsed : null;
    } catch (_) {
      return null;
    }
  }

  String _signEventPolicyTarget(Map<String, dynamic> event) {
    return 'kind:${event['kind']?.toString() ?? 'unknown'}';
  }

  Future<void> _rememberSignerPolicy({
    required String pageOrigin,
    required String operation,
    required String target,
    required SignerPolicyRuleDecision decision,
    required String label,
  }) {
    return widget.signerStore.rememberPolicyRule(
      SignerPolicyRule(
        pageOrigin: pageOrigin,
        operation: operation,
        target: target,
        deviceNpub: widget.config.deviceNpub,
        decision: decision,
        createdAt: DateTime.now().toUtc(),
        label: label,
      ),
    );
  }

  Future<SignerPromptResult> _confirmNip98(
    Map<String, dynamic> request,
    SignerPolicyDecision decision,
  ) async {
    final url = request['url']?.toString() ?? '';
    return await showDialog<SignerPromptResult>(
          context: context,
          builder: (context) {
            return AlertDialog(
              title: const Text('Approve NIP-98 signature'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('WebView origin: ${decision.pageOrigin}'),
                  Text('Target origin: ${decision.targetOrigin}'),
                  Text('Method: ${decision.method}'),
                  Text('URL: $url'),
                  const Text('Event kind: 27235'),
                  Text('Device: ${widget.config.deviceNpub}'),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(
                    const SignerPromptResult(
                      approved: false,
                      denyAlways: true,
                    ),
                  ),
                  child: const Text('Deny always'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(
                    const SignerPromptResult(approved: false),
                  ),
                  child: const Text('Deny'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(
                    const SignerPromptResult(approved: true),
                  ),
                  child: const Text('Approve'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(
                    const SignerPromptResult(
                      approved: true,
                      remember: true,
                    ),
                  ),
                  child: const Text('Approve always'),
                ),
              ],
            );
          },
        ) ??
        const SignerPromptResult(approved: false);
  }

  Future<SignerPromptResult> _confirmSignEvent(
    Map<String, dynamic> event,
    String pageOrigin,
  ) async {
    final kind = event['kind']?.toString() ?? 'unknown';
    final content = event['content']?.toString() ?? '';
    final tags = event['tags'] is List ? event['tags'] as List<dynamic> : [];
    return await showDialog<SignerPromptResult>(
          context: context,
          builder: (context) {
            return AlertDialog(
              title: const Text('Approve Nostr event signature'),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Website: $pageOrigin'),
                    Text('Kind: $kind'),
                    Text('Tags: ${tags.length}'),
                    Text('Device: ${widget.config.deviceNpub}'),
                    if (content.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      const Text('Content preview:'),
                      SelectableText(
                        content.length > 500
                            ? '${content.substring(0, 500)}...'
                            : content,
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(
                    const SignerPromptResult(
                      approved: false,
                      denyAlways: true,
                    ),
                  ),
                  child: const Text('Reject always'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(
                    const SignerPromptResult(approved: false),
                  ),
                  child: const Text('Reject'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(
                    const SignerPromptResult(approved: true),
                  ),
                  child: const Text('Sign'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(
                    const SignerPromptResult(
                      approved: true,
                      remember: true,
                    ),
                  ),
                  child: const Text('Sign always'),
                ),
              ],
            );
          },
        ) ??
        const SignerPromptResult(approved: false);
  }

  Future<void> _handleNip44Request({
    required BrowserTab tab,
    required String requestId,
    required String method,
    required Map<String, dynamic> params,
  }) async {
    final pageUrl = tab.currentUrl ?? widget.config.flightDeckUrl;
    final pageOrigin = SignerPolicy.normalizeOrigin(pageUrl);
    if (!_signerPolicy.canSignNip07(pageUrl)) {
      final reason = 'unsupported NIP-44 page origin: $pageOrigin';
      setState(() {
        tab.message = 'Signer denied: $reason';
      });
      await _resolveSignerRequest(tab, requestId, {'error': reason});
      return;
    }

    final peerPubkey = params['peerPubkey']?.toString() ?? '';
    final payload = params['payload']?.toString() ?? '';
    final operation = method == 'nip44.encrypt' ? 'encrypt' : 'decrypt';
    final policyRule = await widget.signerStore.findPolicyRule(
      pageOrigin: pageOrigin,
      operation: method,
      target: _nip44PolicyTarget,
      deviceNpub: widget.config.deviceNpub,
    );
    if (policyRule != null && !policyRule.allows) {
      await _recordNip44Audit(
        pageOrigin: pageOrigin,
        peerPubkey: peerPubkey,
        operation: operation,
        allowed: false,
        outcome: 'policy_denied',
        reason: 'denied by signer policy',
        rememberedApproval: true,
      );
      await _resolveSignerRequest(
        tab,
        requestId,
        {'error': 'denied by signer policy'},
      );
      return;
    }
    final remembered = policyRule != null && policyRule.allows;
    final approval = remembered
        ? const SignerPromptResult(approved: true)
        : await _confirmNip44(
            operation: operation,
            pageOrigin: pageOrigin,
            peerPubkey: peerPubkey,
            payload: payload,
          );
    if (!approval.approved) {
      if (approval.denyAlways) {
        await _rememberSignerPolicy(
          pageOrigin: pageOrigin,
          operation: method,
          target: _nip44PolicyTarget,
          decision: SignerPolicyRuleDecision.deny,
          label: 'NIP-44 $operation for $pageOrigin',
        );
      }
      await _recordNip44Audit(
        pageOrigin: pageOrigin,
        peerPubkey: peerPubkey,
        operation: operation,
        allowed: false,
        outcome: approval.denyAlways ? 'policy_saved_deny' : 'user_denied',
        reason: approval.denyAlways
            ? 'denied by user and saved as policy'
            : 'denied by user',
      );
      await _resolveSignerRequest(tab, requestId, {'error': 'denied'});
      return;
    }
    if (approval.remember) {
      await _rememberSignerPolicy(
        pageOrigin: pageOrigin,
        operation: method,
        target: _nip44PolicyTarget,
        decision: SignerPolicyRuleDecision.allow,
        label: 'NIP-44 $operation for $pageOrigin',
      );
    }

    final result = method == 'nip44.encrypt'
        ? await widget.bridge.nip44Encrypt(
            config: widget.config,
            peerPubkey: peerPubkey,
            plaintext: payload,
          )
        : await widget.bridge.nip44Decrypt(
            config: widget.config,
            peerPubkey: peerPubkey,
            ciphertext: payload,
          );
    if (!result.ok) {
      await _recordNip44Audit(
        pageOrigin: pageOrigin,
        peerPubkey: peerPubkey,
        operation: operation,
        allowed: false,
        outcome: 'signer_error',
        reason: result.error ?? 'native NIP-44 failed',
        rememberedApproval: remembered,
      );
      await _resolveSignerRequest(tab, requestId, {'error': result.error});
      return;
    }

    await _recordNip44Audit(
      pageOrigin: pageOrigin,
      peerPubkey: peerPubkey,
      operation: operation,
      allowed: true,
      outcome: remembered ? '${operation}_with_policy' : operation,
      rememberedApproval: remembered || approval.remember,
    );
    await _resolveSignerRequest(tab, requestId, {
      'result': operation == 'encrypt'
          ? result.json['ciphertext']
          : result.json['plaintext'],
    });
  }

  Future<SignerPromptResult> _confirmNip44({
    required String operation,
    required String pageOrigin,
    required String peerPubkey,
    required String payload,
  }) async {
    final title = operation == 'encrypt'
        ? 'Approve NIP-44 encryption'
        : 'Approve NIP-44 decryption';
    return await showDialog<SignerPromptResult>(
          context: context,
          builder: (context) {
            return AlertDialog(
              title: Text(title),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Website: $pageOrigin'),
                    Text('Peer pubkey: $peerPubkey'),
                    Text('Device: ${widget.config.deviceNpub}'),
                    if (payload.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(operation == 'encrypt'
                          ? 'Plaintext preview:'
                          : 'Ciphertext preview:'),
                      SelectableText(
                        payload.length > 500
                            ? '${payload.substring(0, 500)}...'
                            : payload,
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(
                    const SignerPromptResult(
                      approved: false,
                      denyAlways: true,
                    ),
                  ),
                  child: const Text('Deny always'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(
                    const SignerPromptResult(approved: false),
                  ),
                  child: const Text('Deny'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(
                    const SignerPromptResult(approved: true),
                  ),
                  child: const Text('Approve'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(
                    const SignerPromptResult(
                      approved: true,
                      remember: true,
                    ),
                  ),
                  child: const Text('Approve always'),
                ),
              ],
            );
          },
        ) ??
        const SignerPromptResult(approved: false);
  }

  Future<void> _recordSignerAudit({
    required SignerPolicyDecision decision,
    required String targetUrl,
    required String method,
    required bool allowed,
    required String outcome,
    String reason = '',
    bool rememberedApproval = false,
  }) async {
    await widget.signerStore.appendAudit(
      SignerAuditEntry.create(
        pageOrigin: decision.pageOrigin,
        targetOrigin: decision.targetOrigin,
        targetUrl: targetUrl,
        method: method,
        deviceNpub: widget.config.deviceNpub,
        allowed: allowed,
        outcome: outcome,
        reason: reason,
        rememberedApproval: rememberedApproval,
      ),
    );
  }

  Future<void> _recordNip07Audit({
    required String pageOrigin,
    required String targetUrl,
    required Map<String, dynamic> event,
    required bool allowed,
    required String outcome,
    String reason = '',
    bool rememberedApproval = false,
  }) async {
    await widget.signerStore.appendAudit(
      SignerAuditEntry.create(
        pageOrigin: pageOrigin,
        targetOrigin: pageOrigin,
        targetUrl: targetUrl,
        method: 'signEvent kind ${event['kind'] ?? 'unknown'}',
        deviceNpub: widget.config.deviceNpub,
        allowed: allowed,
        outcome: outcome,
        reason: reason,
        rememberedApproval: rememberedApproval,
      ),
    );
  }

  Future<void> _recordNip44Audit({
    required String pageOrigin,
    required String peerPubkey,
    required String operation,
    required bool allowed,
    required String outcome,
    String reason = '',
    bool rememberedApproval = false,
  }) async {
    await widget.signerStore.appendAudit(
      SignerAuditEntry.create(
        pageOrigin: pageOrigin,
        targetOrigin: pageOrigin,
        targetUrl: peerPubkey,
        method: 'nip44.$operation',
        deviceNpub: widget.config.deviceNpub,
        allowed: allowed,
        outcome: outcome,
        reason: reason,
        rememberedApproval: rememberedApproval,
      ),
    );
  }

  Future<void> _resolveSignerRequest(
    BrowserTab tab,
    String id,
    Map<String, dynamic> payload,
  ) async {
    final encoded = jsonEncode(payload);
    await tab.controller.runJavaScript(
      'window.__wingmanResolve && window.__wingmanResolve(${jsonEncode(id)}, $encoded);',
    );
  }

  Future<void> _injectTabCapture(BrowserTab tab) async {
    await tab.controller.runJavaScript(_tabCaptureScript());
  }

  String _tabCaptureScript() {
    return '''
(() => {
  if (window.__wingmanTabCapture) return;
  window.__wingmanTabCapture = true;
  let seq = 0;
  function openWingmanTab(rawUrl) {
    if (!rawUrl || !window.WingmanSigner) return Promise.resolve(false);
    let href;
    try {
      href = new URL(String(rawUrl), window.location.href).href;
    } catch (_) {
      return Promise.resolve(false);
    }
    const id = `tab-\${++seq}`;
    WingmanSigner.postMessage(JSON.stringify({
      id,
      method: 'openTab',
      params: { url: href },
    }));
    return Promise.resolve(true);
  }
  const originalWindowOpen = window.open ? window.open.bind(window) : null;
  window.open = (url, target, features) => {
    const normalizedTarget = String(target || '_blank').toLowerCase();
    if (normalizedTarget !== '_self') {
      openWingmanTab(url);
      return null;
    }
    if (originalWindowOpen) return originalWindowOpen(url, target, features);
    if (url) window.location.href = String(url);
    return null;
  };
  document.addEventListener('click', (event) => {
    const target = event.target;
    const anchor = target && target.closest ? target.closest('a[href]') : null;
    if (!anchor) return;
    const linkTarget = String(anchor.getAttribute('target') || '').toLowerCase();
    if (!linkTarget || linkTarget === '_self') return;
    event.preventDefault();
    openWingmanTab(anchor.href);
  }, true);
})();
''';
  }

  String _bridgeScript(String devicePublicKeyHex) {
    final escapedPublicKey =
        devicePublicKeyHex.replaceAll('\\', '\\\\').replaceAll('"', '\\"');
    return '''
(() => {
  if (window.nostr && window.nostr.__wingman) return;
  const pending = new Map();
  let seq = 0;
  window.__wingmanResolve = (id, payload) => {
    const entry = pending.get(id);
    if (!entry) return;
    pending.delete(id);
    if (payload && payload.error) entry.reject(new Error(String(payload.error)));
    else entry.resolve(payload ? payload.result : undefined);
  };
  function callNative(method, params) {
    const id = String(++seq);
    const message = JSON.stringify({ id, method, params: params || {} });
    const promise = new Promise((resolve, reject) => {
      pending.set(id, { resolve, reject });
    });
    WingmanSigner.postMessage(message);
    return promise;
  }
  window.nostr = {
    __wingman: true,
    getPublicKey: () => callNative('getPublicKey').then((value) => value || "$escapedPublicKey"),
    signNip98: (request) => callNative('signNip98', request),
    signEvent: (event) => callNative('signEvent', event),
    getRelays: () => Promise.resolve({}),
    nip04: {
      encrypt: () => Promise.reject(new Error('nip04 encryption is not enabled in Wingman App yet')),
      decrypt: () => Promise.reject(new Error('nip04 decryption is not enabled in Wingman App yet')),
    },
    nip44: {
      encrypt: (peerPubkey, plaintext) => callNative('nip44.encrypt', { peerPubkey, payload: plaintext }),
      decrypt: (peerPubkey, ciphertext) => callNative('nip44.decrypt', { peerPubkey, payload: ciphertext }),
    },
  };
})();
''';
  }
}

class _TabReorderHandle extends StatelessWidget {
  const _TabReorderHandle({
    required this.index,
    required this.child,
  });

  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isTouchPlatform = switch (defaultTargetPlatform) {
      TargetPlatform.android || TargetPlatform.iOS => true,
      _ => false,
    };
    if (isTouchPlatform) {
      return ReorderableDelayedDragStartListener(
        index: index,
        child: child,
      );
    }
    return ReorderableDragStartListener(
      index: index,
      child: child,
    );
  }
}

class _BrowserTabButton extends StatelessWidget {
  const _BrowserTabButton({
    required this.title,
    required this.active,
    required this.fipsTransport,
    required this.closeable,
    required this.onPressed,
    required this.onClose,
    this.width = 190,
  });

  final String title;
  final bool active;
  final bool fipsTransport;
  final bool closeable;
  final VoidCallback onPressed;
  final VoidCallback onClose;
  final double width;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Material(
        color: active ? colors.surface : Colors.transparent,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
        child: InkWell(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
          onTap: onPressed,
          child: Container(
            width: width,
            height: 34,
            padding: const EdgeInsets.only(left: 12, right: 4),
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(6),
              ),
              border: active
                  ? Border.all(color: colors.outlineVariant)
                  : Border.all(color: Colors.transparent),
            ),
            child: Row(
              children: [
                Tooltip(
                  message: fipsTransport
                      ? 'Encrypted FIPS mesh transport'
                      : 'Web transport',
                  child: Icon(
                    fipsTransport ? Icons.hub_outlined : Icons.public,
                    key: fipsTransport
                        ? const ValueKey('fips-transport-indicator')
                        : null,
                    size: 16,
                    color: active ? colors.onSurface : colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color:
                          active ? colors.onSurface : colors.onSurfaceVariant,
                    ),
                  ),
                ),
                if (closeable)
                  SizedBox(
                    width: 28,
                    height: 28,
                    child: IconButton(
                      tooltip: 'Close tab',
                      padding: EdgeInsets.zero,
                      iconSize: 16,
                      onPressed: onClose,
                      icon: const Icon(Icons.close),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BrowserAvatarMenu extends StatelessWidget {
  const _BrowserAvatarMenu({
    required this.deviceNpub,
    required this.profile,
    required this.onEditProfile,
    required this.onOpenSetup,
    required this.onOpenSigner,
    required this.onOpenStatus,
    this.onLogOut,
  });

  final String deviceNpub;
  final NostrProfile profile;
  final VoidCallback onEditProfile;
  final VoidCallback onOpenSetup;
  final VoidCallback onOpenSigner;
  final VoidCallback onOpenStatus;
  final VoidCallback? onLogOut;

  @override
  Widget build(BuildContext context) {
    final label = profile.labelFor(deviceNpub);
    return PopupMenuButton<_BrowserAvatarAction>(
      tooltip: 'Profile',
      offset: const Offset(0, 8),
      child: Padding(
        padding: const EdgeInsets.only(right: 8),
        child: _BrowserProfileChip(
          label: label,
          profile: profile,
        ),
      ),
      onSelected: (action) {
        switch (action) {
          case _BrowserAvatarAction.editProfile:
            onEditProfile();
          case _BrowserAvatarAction.setup:
            onOpenSetup();
          case _BrowserAvatarAction.signer:
            onOpenSigner();
          case _BrowserAvatarAction.status:
            onOpenStatus();
          case _BrowserAvatarAction.logOut:
            onLogOut?.call();
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          enabled: false,
          child: SizedBox(
            width: 280,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: _ProfileAvatar(profile: profile, label: label),
              title: Text(
                label,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: _profileSubtitle(profile),
            ),
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: _BrowserAvatarAction.editProfile,
          child: ListTile(
            leading: Icon(Icons.person_outline),
            title: Text('Edit profile'),
          ),
        ),
        const PopupMenuItem(
          value: _BrowserAvatarAction.setup,
          child: ListTile(
            leading: Icon(Icons.tune),
            title: Text('Setup'),
          ),
        ),
        const PopupMenuItem(
          value: _BrowserAvatarAction.signer,
          child: ListTile(
            leading: Icon(Icons.shield_outlined),
            title: Text('Signer'),
          ),
        ),
        const PopupMenuItem(
          value: _BrowserAvatarAction.status,
          child: ListTile(
            leading: Icon(Icons.monitor_heart_outlined),
            title: Text('Status'),
          ),
        ),
        if (onLogOut != null) ...[
          const PopupMenuDivider(),
          const PopupMenuItem(
            value: _BrowserAvatarAction.logOut,
            child: ListTile(
              leading: Icon(Icons.logout),
              title: Text('Log out'),
            ),
          ),
        ],
      ],
    );
  }
}

class _BrowserProfileChip extends StatelessWidget {
  const _BrowserProfileChip({
    required this.label,
    required this.profile,
  });

  final String label;
  final NostrProfile profile;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      width: 34,
      height: 34,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: colors.primary, width: 1.5),
          color: colors.surface,
        ),
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: _ProfileAvatar(profile: profile, label: label, radius: 12.5),
        ),
      ),
    );
  }
}

enum _BrowserAvatarAction {
  editProfile,
  setup,
  signer,
  status,
  logOut,
}

class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar({
    required this.profile,
    required this.label,
    this.radius = 20,
  });

  final NostrProfile profile;
  final String label;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final avatarUrl = profile.avatarUrl;
    final cachedBytes = profile.cachedAvatarBytes;
    final fallback = CircleAvatar(
      radius: radius,
      child: Text(_initials(label)),
    );
    if (cachedBytes != null) {
      return ClipOval(
        child: Image.memory(
          cachedBytes,
          width: radius * 2,
          height: radius * 2,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => fallback,
        ),
      );
    }
    if (avatarUrl.isEmpty) return fallback;
    return ClipOval(
      child: Image.network(
        avatarUrl,
        width: radius * 2,
        height: radius * 2,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => fallback,
      ),
    );
  }

  String _initials(String value) {
    final words = value
        .trim()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList(growable: false);
    if (words.isEmpty) return 'W';
    if (words.length == 1) return words.first.substring(0, 1).toUpperCase();
    return '${words[0][0]}${words[1][0]}'.toUpperCase();
  }
}

Widget? _profileSubtitle(NostrProfile profile) {
  final nip05 = profile.nip05.trim();
  if (nip05.isNotEmpty) {
    return Text(nip05, overflow: TextOverflow.ellipsis);
  }
  final name = profile.name.trim();
  if (name.isNotEmpty) {
    return Text('@$name', overflow: TextOverflow.ellipsis);
  }
  return null;
}

class _EditNostrProfileDialog extends StatefulWidget {
  const _EditNostrProfileDialog({
    required this.deviceNpub,
    required this.profile,
  });

  final String deviceNpub;
  final NostrProfile profile;

  @override
  State<_EditNostrProfileDialog> createState() =>
      _EditNostrProfileDialogState();
}

class _EditNostrProfileDialogState extends State<_EditNostrProfileDialog> {
  late final TextEditingController _displayNameController;
  late final TextEditingController _nameController;
  late final TextEditingController _pictureController;
  late final TextEditingController _nip05Controller;
  late final TextEditingController _websiteController;
  late final TextEditingController _aboutController;

  @override
  void initState() {
    super.initState();
    _displayNameController =
        TextEditingController(text: widget.profile.displayName);
    _nameController = TextEditingController(text: widget.profile.name);
    _pictureController = TextEditingController(text: widget.profile.pictureUrl);
    _nip05Controller = TextEditingController(text: widget.profile.nip05);
    _websiteController = TextEditingController(text: widget.profile.website);
    _aboutController = TextEditingController(text: widget.profile.about);
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _nameController.dispose();
    _pictureController.dispose();
    _nip05Controller.dispose();
    _websiteController.dispose();
    _aboutController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final preview = _currentProfile();
    final label = preview.labelFor(widget.deviceNpub);
    return AlertDialog(
      title: const Text('Edit profile'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  _ProfileAvatar(profile: preview, label: label, radius: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        if (preview.nip05.trim().isNotEmpty)
                          Text(
                            preview.nip05.trim(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _field(
                controller: _displayNameController,
                label: 'Display name',
                icon: Icons.badge_outlined,
              ),
              _field(
                controller: _nameController,
                label: 'Username',
                icon: Icons.alternate_email,
              ),
              _field(
                controller: _pictureController,
                label: 'Avatar URL',
                icon: Icons.image_outlined,
              ),
              _field(
                controller: _nip05Controller,
                label: 'Verified address',
                icon: Icons.verified_outlined,
              ),
              _field(
                controller: _websiteController,
                label: 'Website',
                icon: Icons.link,
              ),
              _field(
                controller: _aboutController,
                label: 'About',
                icon: Icons.notes_outlined,
                maxLines: 3,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.of(context).pop(_currentProfile()),
          icon: const Icon(Icons.save_outlined),
          label: const Text('Save'),
        ),
      ],
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          border: const OutlineInputBorder(),
          prefixIcon: Icon(icon),
          labelText: label,
          isDense: true,
        ),
      ),
    );
  }

  NostrProfile _currentProfile() {
    return NostrProfile(
      displayName: _displayNameController.text.trim(),
      name: _nameController.text.trim(),
      pictureUrl: _pictureController.text.trim(),
      nip05: _nip05Controller.text.trim(),
      website: _websiteController.text.trim(),
      about: _aboutController.text.trim(),
    );
  }
}

class _BrowserTabsSnapshot {
  const _BrowserTabsSnapshot({
    required this.version,
    required this.activeIndex,
    required this.tabs,
  });

  final int version;
  final int activeIndex;
  final List<_BrowserTabSnapshot> tabs;

  Map<String, dynamic> toJson() {
    return {
      'version': version,
      'active_index': activeIndex,
      'tabs': [for (final tab in tabs) tab.toJson()],
    };
  }

  static _BrowserTabsSnapshot? tryParse(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(value);
      if (decoded is! Map<String, dynamic>) return null;
      final tabsValue = decoded['tabs'];
      if (tabsValue is! List) return null;
      final tabs = [
        for (final rawTab in tabsValue)
          if (rawTab is Map<String, dynamic>)
            _BrowserTabSnapshot.tryParse(rawTab),
      ].whereType<_BrowserTabSnapshot>().toList(growable: false);
      if (tabs.isEmpty) return null;
      return _BrowserTabsSnapshot(
        version: decoded['version'] is int ? decoded['version'] as int : 1,
        activeIndex:
            decoded['active_index'] is int ? decoded['active_index'] as int : 0,
        tabs: tabs,
      );
    } catch (_) {
      return null;
    }
  }
}

class _BrowserTabSnapshot {
  const _BrowserTabSnapshot({
    required this.title,
    required this.url,
    required this.isHome,
  });

  final String? title;
  final String? url;
  final bool isHome;

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'url': url,
      'is_home': isHome,
    };
  }

  static _BrowserTabSnapshot? tryParse(Map<String, dynamic> value) {
    final isHome = value['is_home'] == true;
    final url = value['url']?.toString().trim();
    if (!isHome && (url == null || url.isEmpty)) return null;
    return _BrowserTabSnapshot(
      title: value['title']?.toString(),
      url: url == null || url.isEmpty ? null : url,
      isHome: isHome,
    );
  }
}

class BrowserTab {
  BrowserTab({
    required this.id,
    required this.controller,
    required this.addressController,
    required this.addressFocusNode,
    required this.title,
    this.isHome = false,
  });

  final int id;
  final WebViewController controller;
  final TextEditingController addressController;
  final FocusNode addressFocusNode;
  String title;
  String? currentUrl;
  String? message;
  bool isHome;
  bool canGoBack = false;
  bool canGoForward = false;

  String get label {
    final trimmed = title.trim();
    if (trimmed.isNotEmpty) return trimmed;
    final uri = Uri.tryParse(currentUrl ?? '');
    if (uri != null && uri.host.isNotEmpty) return uri.host;
    return 'New tab';
  }

  bool get isFips {
    try {
      FipsAppTarget.parse(currentUrl ?? addressController.text);
      return true;
    } on FormatException {
      return false;
    }
  }

  void dispose() {
    addressController.dispose();
    addressFocusNode.dispose();
  }
}

class BrowserBookmarkMenuState {
  const BrowserBookmarkMenuState({
    required this.available,
    required this.bookmarked,
  });

  const BrowserBookmarkMenuState.unavailable()
      : available = false,
        bookmarked = false;

  final bool available;
  final bool bookmarked;

  @override
  bool operator ==(Object other) {
    return other is BrowserBookmarkMenuState &&
        other.available == available &&
        other.bookmarked == bookmarked;
  }

  @override
  int get hashCode => Object.hash(available, bookmarked);
}

class SignerPromptResult {
  const SignerPromptResult({
    required this.approved,
    this.remember = false,
    this.denyAlways = false,
  });

  final bool approved;
  final bool remember;
  final bool denyAlways;
}

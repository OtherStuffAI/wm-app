import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/app_config.dart';
import '../../core/native_core_bridge.dart';
import 'signer_policy.dart';
import 'signer_store.dart';

class BrowserScreen extends StatefulWidget {
  const BrowserScreen({
    required this.config,
    required this.bridge,
    required this.signerStore,
    super.key,
  });

  final AppConfig config;
  final NativeCoreBridge bridge;
  final SignerStore signerStore;

  @override
  State<BrowserScreen> createState() => _BrowserScreenState();
}

class _BrowserScreenState extends State<BrowserScreen> {
  final List<BrowserTab> _tabs = [];
  int _activeTabId = 0;
  int _nextTabId = 1;
  static const _nip44PolicyTarget = '*';

  @override
  void initState() {
    super.initState();
    _createTab(widget.config.flightDeckUrl, activate: true);
  }

  @override
  void didUpdateWidget(covariant BrowserScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.config.flightDeckUrl != widget.config.flightDeckUrl) {
      _loadConfiguredUrl();
    }
  }

  @override
  void dispose() {
    for (final tab in _tabs) {
      tab.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildTabBar(context),
        _buildAddressBar(context),
        Expanded(
          child: IndexedStack(
            index: _activeTabIndex,
            children: [
              for (final tab in _tabs)
                WebViewWidget(
                  key: ValueKey(tab.id),
                  controller: tab.controller,
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTabBar(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: SizedBox(
        height: 40,
        child: Row(
          children: [
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.only(left: 8),
                scrollDirection: Axis.horizontal,
                itemCount: _tabs.length,
                separatorBuilder: (context, index) => const SizedBox(width: 4),
                itemBuilder: (context, index) {
                  final tab = _tabs[index];
                  final active = tab.id == _activeTabId;
                  return _BrowserTabButton(
                    title: tab.label,
                    active: active,
                    closeable: _tabs.length > 1,
                    onPressed: () => _activateTab(tab.id),
                    onClose: () => _closeTab(tab.id),
                  );
                },
              ),
            ),
            IconButton(
              tooltip: 'New tab',
              onPressed: () => _createTab(widget.config.flightDeckUrl),
              icon: const Icon(Icons.add),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAddressBar(BuildContext context) {
    final tab = _activeTab;
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
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

  void _createTab(String url, {bool activate = true}) {
    final id = _nextTabId++;
    late final BrowserTab tab;
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'WingmanSigner',
        onMessageReceived: (message) => _onSignerMessage(id, message),
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (url) => _onPageFinished(id, url),
        ),
      );
    tab = BrowserTab(
      id: id,
      controller: controller,
      addressController: TextEditingController(text: url),
      title: 'New tab',
    );
    setState(() {
      _tabs.add(tab);
      if (activate) _activeTabId = id;
    });
    _loadAddressForTab(tab, url);
  }

  void _activateTab(int id) {
    if (_activeTabId == id) return;
    setState(() {
      _activeTabId = id;
    });
    _refreshNavigationState(_activeTab);
  }

  void _closeTab(int id) {
    if (_tabs.length == 1) return;
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
    removed.dispose();
  }

  void _loadConfiguredUrl() {
    _loadAddress(widget.config.flightDeckUrl);
  }

  void _reload() {
    final tab = _activeTab;
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
    _loadAddressForTab(_activeTab, value);
  }

  void _loadAddressForTab(BrowserTab tab, String value) {
    final normalized = _normalizeAddress(value);
    final uri = Uri.tryParse(normalized);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      setState(() {
        tab.message = 'Enter a valid website URL.';
      });
      return;
    }
    setState(() {
      tab.currentUrl = uri.toString();
      tab.addressController.text = tab.currentUrl!;
      tab.title = _titleForUrl(tab.currentUrl!);
      tab.message = null;
    });
    tab.controller.loadRequest(uri);
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

  Future<void> _onPageFinished(int tabId, String url) async {
    final tab = _tabById(tabId);
    if (tab == null) return;
    final title = await tab.controller.getTitle();
    setState(() {
      tab.currentUrl = url;
      tab.addressController.text = url;
      tab.title =
          title?.trim().isNotEmpty == true ? title!.trim() : _titleForUrl(url);
    });
    await _refreshNavigationState(tab);
    await _injectIfTrusted(tab);
  }

  Future<void> _injectIfTrusted(BrowserTab tab) async {
    final url = tab.currentUrl ?? widget.config.flightDeckUrl;
    final origin = SignerPolicy.normalizeOrigin(url);
    final policy = SignerPolicy.fromConfig(widget.config);
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
      if (!SignerPolicy.fromConfig(widget.config).canSignNip07(pageUrl)) {
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
      final decision = SignerPolicy.fromConfig(widget.config).validateNip98(
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
    if (!SignerPolicy.fromConfig(widget.config).canSignNip07(pageUrl)) {
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
  function openWingmanTab(rawUrl) {
    if (!rawUrl) return Promise.resolve(false);
    let href;
    try {
      href = new URL(String(rawUrl), window.location.href).href;
    } catch (_) {
      return Promise.resolve(false);
    }
    return callNative('openTab', { url: href }).catch(() => false);
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

class _BrowserTabButton extends StatelessWidget {
  const _BrowserTabButton({
    required this.title,
    required this.active,
    required this.closeable,
    required this.onPressed,
    required this.onClose,
  });

  final String title;
  final bool active;
  final bool closeable;
  final VoidCallback onPressed;
  final VoidCallback onClose;

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
            width: 190,
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
                Icon(
                  Icons.public,
                  size: 16,
                  color: active ? colors.onSurface : colors.onSurfaceVariant,
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

class BrowserTab {
  BrowserTab({
    required this.id,
    required this.controller,
    required this.addressController,
    required this.title,
  });

  final int id;
  final WebViewController controller;
  final TextEditingController addressController;
  String title;
  String? currentUrl;
  String? message;
  bool canGoBack = false;
  bool canGoForward = false;

  String get label {
    final trimmed = title.trim();
    if (trimmed.isNotEmpty) return trimmed;
    final uri = Uri.tryParse(currentUrl ?? '');
    if (uri != null && uri.host.isNotEmpty) return uri.host;
    return 'New tab';
  }

  void dispose() {
    addressController.dispose();
  }
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

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
  late final TextEditingController _addressController = TextEditingController(
    text: widget.config.flightDeckUrl,
  );
  late final WebViewController _controller = WebViewController()
    ..setJavaScriptMode(JavaScriptMode.unrestricted)
    ..addJavaScriptChannel(
      'WingmanSigner',
      onMessageReceived: _onSignerMessage,
    )
    ..setNavigationDelegate(
      NavigationDelegate(
        onPageFinished: _onPageFinished,
      ),
    );

  String? _currentUrl;
  String? _message;
  static const _nip44PolicyTarget = '*';

  @override
  void initState() {
    super.initState();
    _loadConfiguredUrl();
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
    _addressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final policy = SignerPolicy.fromConfig(widget.config);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _addressController,
                  onSubmitted: _loadAddress,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.public),
                    labelText: 'Website',
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: () => _loadAddress(_addressController.text),
                icon: const Icon(Icons.arrow_forward),
                label: const Text('Go'),
              ),
              IconButton(
                tooltip: 'Reload',
                onPressed: _reload,
                icon: const Icon(Icons.refresh),
              ),
              IconButton(
                tooltip: 'Inject signer',
                onPressed: _injectIfTrusted,
                icon: const Icon(Icons.key),
              ),
            ],
          ),
        ),
        if (_message != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
            child: Text(_message!),
          ),
        Expanded(
          child: WebViewWidget(controller: _controller),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 10, 24, 16),
          child: Text(
            'NIP-07 signer is available on http/https pages. NIP-98 targets remain restricted to trusted origins: ${policy.trustedOrigins.join(', ')}',
          ),
        ),
      ],
    );
  }

  void _loadConfiguredUrl() {
    _loadAddress(widget.config.flightDeckUrl);
  }

  void _reload() {
    final uri = Uri.tryParse(_currentUrl ?? _addressController.text);
    if (uri != null && uri.hasScheme && uri.host.isNotEmpty) {
      _controller.reload();
    } else {
      _loadAddress(_addressController.text);
    }
  }

  void _loadAddress(String value) {
    final normalized = _normalizeAddress(value);
    final uri = Uri.tryParse(normalized);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      setState(() {
        _message = 'Enter a valid website URL.';
      });
      return;
    }
    _currentUrl = uri.toString();
    _addressController.text = _currentUrl!;
    _controller.loadRequest(uri);
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

  Future<void> _onPageFinished(String url) async {
    _currentUrl = url;
    _addressController.text = url;
    await _injectIfTrusted();
  }

  Future<void> _injectIfTrusted() async {
    final url = _currentUrl ?? widget.config.flightDeckUrl;
    final origin = SignerPolicy.normalizeOrigin(url);
    final policy = SignerPolicy.fromConfig(widget.config);
    if (!policy.canInject(url)) {
      setState(() {
        _message = 'Signer withheld for unsupported page: $url';
      });
      return;
    }
    await _controller.runJavaScript(
      _bridgeScript(widget.config.devicePublicKeyHex),
    );
    setState(() {
      _message = 'window.nostr injected for $origin';
    });
  }

  Future<void> _onSignerMessage(JavaScriptMessage message) async {
    final payload = _decodeMessage(message.message);
    if (payload == null) return;
    final id = payload['id']?.toString() ?? '';
    final method = payload['method']?.toString() ?? '';
    if (id.isEmpty || method.isEmpty) return;

    if (method == 'getPublicKey') {
      await _resolveSignerRequest(
        id,
        {'result': widget.config.devicePublicKeyHex},
      );
      return;
    }

    if (method == 'signEvent') {
      final event = payload['params'] is Map<String, dynamic>
          ? payload['params'] as Map<String, dynamic>
          : <String, dynamic>{};
      final pageUrl = _currentUrl ?? widget.config.flightDeckUrl;
      final pageOrigin = SignerPolicy.normalizeOrigin(pageUrl);
      if (!SignerPolicy.fromConfig(widget.config).canSignNip07(pageUrl)) {
        final reason = 'unsupported NIP-07 page origin: $pageOrigin';
        setState(() {
          _message = 'Signer denied: $reason';
        });
        await _resolveSignerRequest(id, {'error': reason});
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
          event: event,
          allowed: false,
          outcome: 'policy_denied',
          reason: 'denied by signer policy',
          rememberedApproval: true,
        );
        await _resolveSignerRequest(id, {'error': 'denied by signer policy'});
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
          event: event,
          allowed: false,
          outcome: approval.denyAlways ? 'policy_saved_deny' : 'user_denied',
          reason: approval.denyAlways
              ? 'denied by user and saved as policy'
              : 'denied by user',
        );
        await _resolveSignerRequest(id, {'error': 'denied'});
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
          event: event,
          allowed: false,
          outcome: 'signer_error',
          reason: result.error ?? 'native signer failed',
        );
        await _resolveSignerRequest(id, {'error': result.error});
        return;
      }
      await _recordNip07Audit(
        pageOrigin: pageOrigin,
        event: event,
        allowed: true,
        outcome: remembered ? 'signed_with_policy' : 'signed',
        rememberedApproval: remembered || approval.remember,
      );
      await _resolveSignerRequest(id, {
        'result': result.json,
      });
      return;
    }

    if (method == 'nip44.encrypt' || method == 'nip44.decrypt') {
      await _handleNip44Request(
        id: id,
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
        pageUrl: _currentUrl ?? widget.config.flightDeckUrl,
        targetUrl: requestUrl,
        method: requestMethod,
        body: requestBody,
      );
      if (!decision.allowed) {
        setState(() {
          _message = 'Signer denied: ${decision.reason}';
        });
        await _recordSignerAudit(
          decision: decision,
          targetUrl: requestUrl,
          method: requestMethod,
          allowed: false,
          outcome: 'policy_denied',
          reason: decision.reason,
        );
        await _resolveSignerRequest(id, {'error': decision.reason});
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
        await _resolveSignerRequest(id, {'error': 'denied by signer policy'});
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
        await _resolveSignerRequest(id, {'error': 'denied'});
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
        await _resolveSignerRequest(id, {'error': result.error});
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
      await _resolveSignerRequest(id, {
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
    required String id,
    required String method,
    required Map<String, dynamic> params,
  }) async {
    final pageUrl = _currentUrl ?? widget.config.flightDeckUrl;
    final pageOrigin = SignerPolicy.normalizeOrigin(pageUrl);
    if (!SignerPolicy.fromConfig(widget.config).canSignNip07(pageUrl)) {
      final reason = 'unsupported NIP-44 page origin: $pageOrigin';
      setState(() {
        _message = 'Signer denied: $reason';
      });
      await _resolveSignerRequest(id, {'error': reason});
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
      await _resolveSignerRequest(id, {'error': 'denied by signer policy'});
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
      await _resolveSignerRequest(id, {'error': 'denied'});
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
      await _resolveSignerRequest(id, {'error': result.error});
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
    await _resolveSignerRequest(id, {
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
        targetUrl: _currentUrl ?? widget.config.flightDeckUrl,
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
    String id,
    Map<String, dynamic> payload,
  ) async {
    final encoded = jsonEncode(payload);
    await _controller.runJavaScript(
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

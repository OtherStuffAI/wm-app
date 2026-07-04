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
                child: Text(
                  _currentUrl ?? widget.config.flightDeckUrl,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                tooltip: 'Reload',
                onPressed: _loadConfiguredUrl,
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
          child: Text('Trusted origins: ${policy.trustedOrigins.join(', ')}'),
        ),
      ],
    );
  }

  void _loadConfiguredUrl() {
    final uri = Uri.tryParse(widget.config.flightDeckUrl);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      setState(() {
        _message = 'Configure a valid Flight Deck URL first.';
      });
      return;
    }
    _currentUrl = uri.toString();
    _controller.loadRequest(uri);
  }

  Future<void> _onPageFinished(String url) async {
    _currentUrl = url;
    await _injectIfTrusted();
  }

  Future<void> _injectIfTrusted() async {
    final url = _currentUrl ?? widget.config.flightDeckUrl;
    final origin = SignerPolicy.normalizeOrigin(url);
    final policy = SignerPolicy.fromConfig(widget.config);
    if (!policy.canInject(url)) {
      setState(() {
        _message = 'Signer withheld for untrusted origin: $origin';
      });
      return;
    }
    await _controller.runJavaScript(_bridgeScript(widget.config.deviceNpub));
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
      await _resolveSignerRequest(id, {'result': widget.config.deviceNpub});
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
      final remembered = widget.config.rememberNip98Approvals &&
          await widget.signerStore.hasApproval(
            pageOrigin: decision.pageOrigin,
            targetOrigin: decision.targetOrigin,
            deviceNpub: widget.config.deviceNpub,
          );
      final approval = remembered
          ? const SignerPromptResult(approved: true, remember: false)
          : await _confirmNip98(request, decision);
      if (!approval.approved) {
        await _recordSignerAudit(
          decision: decision,
          targetUrl: requestUrl,
          method: decision.method,
          allowed: false,
          outcome: 'user_denied',
          reason: 'denied by user',
        );
        await _resolveSignerRequest(id, {'error': 'denied'});
        return;
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

  Future<SignerPromptResult> _confirmNip98(
    Map<String, dynamic> request,
    SignerPolicyDecision decision,
  ) async {
    final url = request['url']?.toString() ?? '';
    bool remember = widget.config.rememberNip98Approvals;
    return await showDialog<SignerPromptResult>(
          context: context,
          builder: (context) {
            return StatefulBuilder(
              builder: (context, setDialogState) {
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
                      if (widget.config.rememberNip98Approvals)
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          value: remember,
                          onChanged: (value) {
                            setDialogState(() {
                              remember = value ?? false;
                            });
                          },
                          title: const Text('Remember for this origin pair'),
                        ),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(
                        const SignerPromptResult(
                          approved: false,
                          remember: false,
                        ),
                      ),
                      child: const Text('Deny'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.of(context).pop(
                        SignerPromptResult(
                          approved: true,
                          remember: remember,
                        ),
                      ),
                      child: const Text('Approve'),
                    ),
                  ],
                );
              },
            );
          },
        ) ??
        const SignerPromptResult(approved: false, remember: false);
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

  Future<void> _resolveSignerRequest(
    String id,
    Map<String, dynamic> payload,
  ) async {
    final encoded = jsonEncode(payload);
    await _controller.runJavaScript(
      'window.__wingmanResolve && window.__wingmanResolve(${jsonEncode(id)}, $encoded);',
    );
  }

  String _bridgeScript(String deviceNpub) {
    final escapedNpub =
        deviceNpub.replaceAll('\\', '\\\\').replaceAll('"', '\\"');
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
    getPublicKey: () => callNative('getPublicKey').then((value) => value || "$escapedNpub"),
    signNip98: (request) => callNative('signNip98', request),
    signEvent: () => Promise.reject(new Error('signEvent requires a later approval policy')),
  };
})();
''';
  }
}

class SignerPromptResult {
  const SignerPromptResult({
    required this.approved,
    required this.remember,
  });

  final bool approved;
  final bool remember;
}

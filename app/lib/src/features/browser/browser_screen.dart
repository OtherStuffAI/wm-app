import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/app_config.dart';
import '../../core/native_core_bridge.dart';

class BrowserScreen extends StatefulWidget {
  const BrowserScreen({
    required this.config,
    required this.bridge,
    super.key,
  });

  final AppConfig config;
  final NativeCoreBridge bridge;

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
    final trusted = widget.config.effectiveTrustedOrigins();
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
          child: Text('Trusted origins: ${trusted.join(', ')}'),
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
    final origin = _originLabel(url);
    final allowed = widget.config.effectiveTrustedOrigins().contains(origin);
    if (!allowed) {
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
      final approved = await _confirmNip98(request);
      if (!approved) {
        await _resolveSignerRequest(id, {'error': 'denied'});
        return;
      }
      final result = await widget.bridge.signNip98(
        config: widget.config,
        method: request['httpMethod']?.toString() ?? 'GET',
        url: request['url']?.toString() ?? '',
        body: request['body']?.toString(),
      );
      if (!result.ok) {
        await _resolveSignerRequest(id, {'error': result.error});
        return;
      }
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

  Future<bool> _confirmNip98(Map<String, dynamic> request) async {
    final url = request['url']?.toString() ?? '';
    final method = request['httpMethod']?.toString() ?? 'GET';
    final origin = _originLabel(url);
    return await showDialog<bool>(
          context: context,
          builder: (context) {
            return AlertDialog(
              title: const Text('Approve NIP-98 signature'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Origin: $origin'),
                  Text('Method: $method'),
                  Text('URL: $url'),
                  Text('Event kind: 27235'),
                  Text('Device: ${widget.config.deviceNpub}'),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Deny'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Approve'),
                ),
              ],
            );
          },
        ) ??
        false;
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

  String _originLabel(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return value;
    }
    if (uri.hasPort) {
      return '${uri.scheme}://${uri.host}:${uri.port}';
    }
    return '${uri.scheme}://${uri.host}';
  }

  String _bridgeScript(String deviceNpub) {
    final escapedNpub = deviceNpub.replaceAll('\\', '\\\\').replaceAll('"', '\\"');
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

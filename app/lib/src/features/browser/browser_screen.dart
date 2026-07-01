import 'package:flutter/material.dart';

import '../../core/app_config.dart';

class BrowserScreen extends StatelessWidget {
  const BrowserScreen({
    required this.config,
    super.key,
  });

  final AppConfig config;

  @override
  Widget build(BuildContext context) {
    final origin = _originLabel(config.towerUrl);
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('Browser', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 20),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.public),
          title: const Text('Flight Deck'),
          subtitle: Text(origin.isEmpty ? 'No Tower URL configured' : origin),
        ),
        const SizedBox(height: 12),
        const Text(
          'The next slice adds the embedded WebView and native signer bridge. '
          'Unknown origins must not receive window.nostr.',
        ),
      ],
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
}

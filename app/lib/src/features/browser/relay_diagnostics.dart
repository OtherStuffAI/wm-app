import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Private, bounded stage trace for a browser relay. Never pass page or relay data.
class RelayDiagnostics {
  static Future<void> _tail = Future<void>.value();

  static void record(String tab, String relay, String stage) {
    if (!RegExp(r'^[a-z0-9_]{1,40}$').hasMatch(stage)) return;
    _tail = _tail.then((_) async {
      try {
        final root = await getApplicationSupportDirectory();
        final file = File('${root.path}/wmapp-relay-diagnostics.jsonl');
        if (await file.exists() && await file.length() > 65536) {
          await file.rename('${file.path}.previous');
        }
        await file.writeAsString(
          '${jsonEncode({
                'time': DateTime.now().toUtc().toIso8601String(),
                'tab': tab,
                'relay': relay,
                'stage': stage
              })}\n',
          mode: FileMode.append,
          flush: true,
        );
      } catch (_) {
        // Diagnostics must not affect transport or signing.
      }
    });
  }
}

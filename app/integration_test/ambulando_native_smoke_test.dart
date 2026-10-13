import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';
import 'package:wingman_app/src/app.dart';
import 'package:wingman_app/src/core/app_product.dart';
import 'package:wingman_app/src/core/local_flight_deck_server.dart';
import 'package:wingman_app/src/features/browser/browser_screen.dart';

/// Runs against real WKWebView and packaged bytes, without unlocking or signing.
/// This is simulator/foreground evidence, not physical tunnel or suspension proof.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('packaged Ambulando and HTTPS load in native WebView',
      (tester) async {
    expect(AppProduct.ambulando, isTrue);
    final server = await LocalFlightDeckServer.start(
        assetPrefix: AppProduct.assetPrefix, serverPort: AppProduct.localPort);
    await tester.pumpWidget(
        WingmanApp(useSignerVault: false, localFlightDeckUrl: server.url));
    await tester.pump(const Duration(seconds: 2));
    final browser =
        tester.state<BrowserScreenState>(find.byType(BrowserScreen));
    Future<PlatformWebViewController> loaded(
        String expected, String predicate) async {
      final deadline = DateTime.now().add(const Duration(seconds: 30));
      while (DateTime.now().isBefore(deadline)) {
        await tester.pump(const Duration(milliseconds: 200));
        for (final view
            in tester.widgetList<WebViewWidget>(find.byType(WebViewWidget))) {
          final url = await view.platform.params.controller.currentUrl();
          if (url?.startsWith(expected) != true) continue;
          try {
            final ready = await view.platform.params.controller
                .runJavaScriptReturningResult(
                    "document.readyState === 'complete' && ($predicate)");
            if (ready == true || ready == 'true') {
              return view.platform.params.controller;
            }
          } catch (_) {}
        }
      }
      throw TimeoutException('Native WebView did not finish expected fixture');
    }

    final local = await loaded(
        server.url, "document.body.innerText.includes('Ambulando')");
    final product = await local.runJavaScriptReturningResult(
        "document.body.innerText.includes('Ambulando')");
    expect(product == true || product == 'true', isTrue);
    browser.openTab('https://example.com/');
    final https = await loaded(
        'https://example.com/', 'document.body.innerText.length > 0');
    final secure = await https.runJavaScriptReturningResult(
        "location.protocol === 'https:' && document.body.innerText.length > 0");
    expect(secure == true || secure == 'true', isTrue);
    await tester.pumpWidget(const SizedBox());
  });
}

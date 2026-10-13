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

    final local = await loaded(server.url,
        "window.Alpine?.store?.('chat')?.routeSyncPaused === false");
    Future<void> check(String expression) async {
      final result = await local.runJavaScriptReturningResult(expression);
      expect(result == true || result == 'true', isTrue, reason: expression);
    }

    Future<void> viewport() => check('''
Math.abs(visualViewport.scale - 1) < 0.01 &&
Math.abs(visualViewport.width - innerWidth) < 1 &&
document.documentElement.scrollWidth <= innerWidth + 1
''');
    Future<void> screenshotPhase(String phase) async {
      debugPrint('AMBULANDO_SCREENSHOT $phase');
      const hold = int.fromEnvironment('AMBULANDO_SCREENSHOT_HOLD_SECONDS');
      if (hold > 0) await tester.pump(const Duration(seconds: hold));
    }

    // Transient layout fixture only: no keys, authenticated requests or live data.
    await local.runJavaScript("""
(() => {
 const s=window.Alpine.store('chat');
 for (const key of ['startWorkspaceLiveQueries','syncRoute','performSync','requestTowerSyncFamily','scheduleStorageImageHydration']) s[key]=()=>{};
 s.openConnectModal=()=>{}; s.backendUrl='http://127.0.0.1:3100';
 s.selectedWorkspaceKey='layout-fixture';
 s.session={npub:'npub1layoutfixture'}; s.showConnectModal=false; s.showWorkspaceBootstrapModal=false;
 s.pgNavigationRecoveryPending=true; s.deckInboxEnabled=true;
 s.navSection='status'; s.selectedChannelId=null; s.pgContextSelectedChannelId=null;
 document.documentElement.classList.add('wingman-iphone-webview');
 const input=document.createElement('input');input.id='native-layout-input';
 input.setAttribute('aria-label','Keyboard layout regression');
 input.style.cssText='position:fixed;top:250px;left:20px;width:250px;height:44px;z-index:99999;font-size:14px';
 document.body.appendChild(input);
})();
""");
    await tester.pump(const Duration(seconds: 2));
    await viewport();
    await check(
        "parseFloat(getComputedStyle(document.querySelector('#native-layout-input')).fontSize) >= 16");
    await local.runJavaScript(
        "document.querySelector('#native-layout-input').focus()");
    await tester.pump(const Duration(seconds: 2));
    await check("document.activeElement.id === 'native-layout-input'");
    await viewport();
    await screenshotPhase('keyboard');
    await local.runJavaScript('document.activeElement.blur()');
    await tester.pump(const Duration(seconds: 2));
    await viewport();
    await local.runJavaScript(
        "document.querySelector('#native-layout-input').remove()");
    await screenshotPhase('portrait');
    // Assert visible controls, excluding intentionally translated closed drawers.
    await check("""
['.mobile-menu-btn', '.sol-theme-button', '.avatar-chip', '.workspace-recovery-status', '.inbox-panel-heading'].every(selector => {
 const r=document.querySelector(selector).getBoundingClientRect();
 return r.width > 0 && r.left >= -1 && r.right <= innerWidth + 1;
})
""");
    await check("""
['.mobile-menu-btn', '.sol-theme-button', '.avatar-chip'].every(selector => {
 const r=document.querySelector(selector).getBoundingClientRect();return r.width >= 44 && r.height >= 44;
})
""");
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(seconds: 2));
    await viewport();
    await screenshotPhase('resume');
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

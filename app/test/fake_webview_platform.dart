import 'package:flutter/widgets.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

final fakeLoadedHtmlStrings = <String>[];
final fakeLoadedRequestUrls = <String>[];
final fakeExecutedJavaScripts = <String>[];
int fakeClearCookieCalls = 0;
int fakeWebViewControllerCreationCount = 0;
final _fakeWebViewControllers = <_FakePlatformWebViewController>[];

Future<NavigationDecision?> submitFakeNavigationRequest({
  required int controllerIndex,
  required String url,
  required bool isMainFrame,
}) {
  return _fakeWebViewControllers[controllerIndex].requestNavigation(
    NavigationRequest(url: url, isMainFrame: isMainFrame),
  );
}

void submitFakeJavaScriptMessage({
  required int controllerIndex,
  required String channel,
  required String message,
}) {
  _fakeWebViewControllers[controllerIndex].postJavaScriptMessage(
    channel,
    message,
  );
}

void installFakeWebViewPlatform() {
  fakeLoadedHtmlStrings.clear();
  fakeLoadedRequestUrls.clear();
  fakeExecutedJavaScripts.clear();
  fakeClearCookieCalls = 0;
  fakeWebViewControllerCreationCount = 0;
  _fakeWebViewControllers.clear();
  WebViewPlatform.instance = _FakeWebViewPlatform();
}

class _FakeWebViewPlatform extends WebViewPlatform
    with MockPlatformInterfaceMixin {
  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) {
    fakeWebViewControllerCreationCount += 1;
    final controller = _FakePlatformWebViewController(params);
    _fakeWebViewControllers.add(controller);
    return controller;
  }

  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
    PlatformNavigationDelegateCreationParams params,
  ) {
    return _FakePlatformNavigationDelegate(params);
  }

  @override
  PlatformWebViewWidget createPlatformWebViewWidget(
    PlatformWebViewWidgetCreationParams params,
  ) {
    return _FakePlatformWebViewWidget(params);
  }

  @override
  PlatformWebViewCookieManager createPlatformCookieManager(
    PlatformWebViewCookieManagerCreationParams params,
  ) {
    return _FakePlatformWebViewCookieManager(params);
  }
}

class _FakePlatformWebViewController extends PlatformWebViewController
    with MockPlatformInterfaceMixin {
  _FakePlatformWebViewController(super.params) : super.implementation();

  _FakePlatformNavigationDelegate? _navigationDelegate;
  String? _currentUrl;
  final Map<String, void Function(JavaScriptMessage)> _javaScriptChannels = {};

  @override
  Future<void> setJavaScriptMode(JavaScriptMode javaScriptMode) async {}

  @override
  Future<void> addJavaScriptChannel(
    JavaScriptChannelParams javaScriptChannelParams,
  ) async {
    _javaScriptChannels[javaScriptChannelParams.name] =
        javaScriptChannelParams.onMessageReceived;
  }

  @override
  Future<void> setPlatformNavigationDelegate(
    PlatformNavigationDelegate handler,
  ) async {
    if (handler is _FakePlatformNavigationDelegate) {
      _navigationDelegate = handler;
    }
  }

  @override
  Future<void> loadRequest(LoadRequestParams params) async {
    final url = params.uri.toString();
    final decision = await _navigationDelegate?.request(
      NavigationRequest(url: url, isMainFrame: true),
    );
    if (decision == NavigationDecision.prevent) return;
    _currentUrl = url;
    fakeLoadedRequestUrls.add(url);
    _navigationDelegate?.finish(_currentUrl!);
  }

  @override
  Future<void> loadHtmlString(String html, {String? baseUrl}) async {
    fakeLoadedHtmlStrings.add(html);
    _currentUrl = baseUrl ?? 'about:blank';
    _navigationDelegate?.finish(_currentUrl!);
  }

  @override
  Future<String?> currentUrl() async => _currentUrl;

  @override
  Future<bool> canGoBack() async => false;

  @override
  Future<bool> canGoForward() async => false;

  @override
  Future<void> goBack() async {}

  @override
  Future<void> goForward() async {}

  @override
  Future<void> reload() async {}

  @override
  Future<void> clearCache() async {}

  @override
  Future<void> clearLocalStorage() async {}

  @override
  Future<void> runJavaScript(String javaScript) async {
    fakeExecutedJavaScripts.add(javaScript);
  }

  @override
  Future<String?> getTitle() async => null;

  Future<NavigationDecision?> requestNavigation(
    NavigationRequest request,
  ) async {
    return _navigationDelegate?.request(request);
  }

  void postJavaScriptMessage(String channel, String message) {
    _javaScriptChannels[channel]?.call(JavaScriptMessage(message: message));
  }
}

class _FakePlatformNavigationDelegate extends PlatformNavigationDelegate
    with MockPlatformInterfaceMixin {
  _FakePlatformNavigationDelegate(super.params) : super.implementation();

  NavigationRequestCallback? _onNavigationRequest;
  PageEventCallback? _onPageFinished;

  @override
  Future<void> setOnNavigationRequest(
    NavigationRequestCallback onNavigationRequest,
  ) async {
    _onNavigationRequest = onNavigationRequest;
  }

  @override
  Future<void> setOnPageFinished(PageEventCallback onPageFinished) async {
    _onPageFinished = onPageFinished;
  }

  Future<NavigationDecision?> request(NavigationRequest request) async {
    return _onNavigationRequest?.call(request);
  }

  void finish(String url) {
    _onPageFinished?.call(url);
  }
}

class _FakePlatformWebViewWidget extends PlatformWebViewWidget
    with MockPlatformInterfaceMixin {
  _FakePlatformWebViewWidget(super.params) : super.implementation();

  @override
  Widget build(BuildContext context) {
    return const SizedBox.expand();
  }
}

class _FakePlatformWebViewCookieManager extends PlatformWebViewCookieManager
    with MockPlatformInterfaceMixin {
  _FakePlatformWebViewCookieManager(super.params) : super.implementation();

  @override
  Future<bool> clearCookies() async {
    fakeClearCookieCalls += 1;
    return true;
  }

  @override
  Future<void> setCookie(WebViewCookie cookie) async {}

  @override
  Future<List<WebViewCookie>> getCookies(Uri url) async => [];
}

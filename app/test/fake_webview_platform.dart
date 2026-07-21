import 'package:flutter/widgets.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

void installFakeWebViewPlatform() {
  WebViewPlatform.instance = _FakeWebViewPlatform();
}

class _FakeWebViewPlatform extends WebViewPlatform
    with MockPlatformInterfaceMixin {
  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) {
    return _FakePlatformWebViewController(params);
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
}

class _FakePlatformWebViewController extends PlatformWebViewController
    with MockPlatformInterfaceMixin {
  _FakePlatformWebViewController(super.params) : super.implementation();

  _FakePlatformNavigationDelegate? _navigationDelegate;
  String? _currentUrl;

  @override
  Future<void> setJavaScriptMode(JavaScriptMode javaScriptMode) async {}

  @override
  Future<void> addJavaScriptChannel(
    JavaScriptChannelParams javaScriptChannelParams,
  ) async {}

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
    _currentUrl = params.uri.toString();
    _navigationDelegate?.finish(_currentUrl!);
  }

  @override
  Future<void> loadHtmlString(String html, {String? baseUrl}) async {
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
  Future<void> runJavaScript(String javaScript) async {}

  @override
  Future<String?> getTitle() async => null;
}

class _FakePlatformNavigationDelegate extends PlatformNavigationDelegate
    with MockPlatformInterfaceMixin {
  _FakePlatformNavigationDelegate(super.params) : super.implementation();

  PageEventCallback? _onPageFinished;

  @override
  Future<void> setOnPageFinished(PageEventCallback onPageFinished) async {
    _onPageFinished = onPageFinished;
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

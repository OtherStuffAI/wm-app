import WebKit

/// Restrict WMapp's privileged channels using native frame metadata. Other
/// plugin clients keep their existing channel behavior.
enum WingmanScriptMessagePolicy {
  static func accepts(_ message: WKScriptMessage) -> Bool {
    guard message.name == "WingmanTower" || message.name == "WingmanSigner" else {
      return true
    }
    guard message.frameInfo.isMainFrame,
      let currentURL = message.webView?.url,
      let frameURL = message.frameInfo.request.url else { return false }
    return currentURL.scheme == frameURL.scheme
      && currentURL.host == frameURL.host && currentURL.port == frameURL.port
  }
}

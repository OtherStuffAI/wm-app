import WebKit

/// Restrict WMapp's privileged channels using native frame metadata. Other
/// plugin clients keep their existing channel behavior.
enum WingmanScriptMessagePolicy {
  static func isBundledOrigin(scheme: String, host: String, port: Int,
    bundleIdentifier: String?) -> Bool {
    let expectedPort = bundleIdentifier == "com.wingmanbefree.ambulando" ? 47832 : 47831
    return scheme == "http" && host == "127.0.0.1" && port == expectedPort
  }

  static func accepts(_ message: WKScriptMessage) -> Bool {
    guard message.name == "WingmanTower" || message.name == "WingmanSigner" || message.name == "WingmanGrasp" else {
      return true
    }
    guard message.frameInfo.isMainFrame,
      let currentURL = message.webView?.url,
      let frameURL = message.frameInfo.request.url else { return false }
    if message.name == "WingmanGrasp" {
      let origin = message.frameInfo.securityOrigin
      let bundled = isBundledOrigin(scheme: origin.protocol, host: origin.host,
        port: origin.port, bundleIdentifier: Bundle.main.bundleIdentifier)
      let defaultPort = origin.protocol == "https" ? 443 : 80
      guard (origin.protocol == "https" || bundled), origin.host == currentURL.host,
        (origin.port == 0 ? defaultPort : origin.port) == (currentURL.port ?? defaultPort) else { return false }
    }
    return currentURL.scheme == frameURL.scheme
      && currentURL.host == frameURL.host && currentURL.port == frameURL.port
  }
}

import Foundation
@main
struct BundledOriginCheck {
  static func main() {
    let wmapp = "com.wingmanbefree.wingmanApp"
    let ambulando = "com.wingmanbefree.ambulando"
    func allowed(_ host: String, _ port: Int, _ bundle: String) -> Bool {
      WingmanScriptMessagePolicy.isBundledOrigin(scheme: "http", host: host,
        port: port, bundleIdentifier: bundle)
    }
    precondition(allowed("127.0.0.1", 47831, wmapp))
    precondition(allowed("127.0.0.1", 47832, ambulando))
    precondition(!allowed("127.0.0.1", 47831, ambulando))
    precondition(!allowed("127.0.0.1", 47832, wmapp))
    precondition(!allowed("localhost", 47832, ambulando))
    precondition(!allowed("127.0.0.2", 47832, ambulando))
    precondition(!allowed("127.0.0.1", 47833, ambulando))
    precondition(!WingmanScriptMessagePolicy.isBundledOrigin(scheme: "https",
      host: "127.0.0.1", port: 47832, bundleIdentifier: ambulando))
    print("PASS: bundled origin pinning, flavor isolation, host and port mismatch denial")
  }
}

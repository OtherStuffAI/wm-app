import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private static let menuChannelName = "au.com.otherstuff.wingman/menu"
  private static let showWingmanMenuMethod = "showWingmanMenu"
  private var menuChannel: FlutterMethodChannel?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    menuChannel = FlutterMethodChannel(
      name: Self.menuChannelName,
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )

    super.awakeFromNib()
  }

  @IBAction func showWingmanMenu(_ sender: Any?) {
    menuChannel?.invokeMethod(Self.showWingmanMenuMethod, arguments: nil)
  }
}

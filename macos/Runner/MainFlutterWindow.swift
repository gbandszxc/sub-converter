import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController
    self.setContentSize(NSSize(width: 1100, height: 720))
    self.center()

    RegisterGeneratedPlugins(registry: flutterViewController)

    // The Dart side asks this channel for installed fonts and the system
    // default family. `availableFontFamilies` returns the names the system
    // UI spells them with; "PingFang SC" is Apple's CJK UI face.
    let fontChannel = FlutterMethodChannel(
      name: "sub_converter/fonts",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    fontChannel.setMethodCallHandler { call, result in
      switch call.method {
      case "installedFontFamilies":
        result(NSFontManager.shared.availableFontFamilies)
      case "defaultFontFamily":
        result("PingFang SC")
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    super.awakeFromNib()
  }
}

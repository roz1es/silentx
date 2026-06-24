import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    if let visibleFrame = NSScreen.main?.visibleFrame {
      self.setFrame(visibleFrame, display: true)
    } else {
      self.setFrame(windowFrame, display: true)
    }

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}

import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    let channel = FlutterMethodChannel(
      name: "com.example.home_ai/window",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] (call, result) in
      guard let self = self else {
        result(FlutterError(code: "UNAVAILABLE", message: "Window is unavailable", details: nil))
        return
      }
      if call.method == "fullscreen" {
        if !self.styleMask.contains(.fullScreen) {
          self.toggleFullScreen(nil)
        }
        result(nil)
      } else if call.method == "windowed" {
        if self.styleMask.contains(.fullScreen) {
          self.toggleFullScreen(nil)
        }
        result(nil)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }

    if !self.styleMask.contains(.fullScreen) {
      self.toggleFullScreen(nil)
    }

    super.awakeFromNib()
  }
}

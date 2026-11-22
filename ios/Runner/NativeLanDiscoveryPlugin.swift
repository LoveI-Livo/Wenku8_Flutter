import Flutter
import Foundation
import Network

/// 局域网发现与本地网络权限入口。
final class NativeLanDiscoveryPlugin: NSObject, FlutterPlugin {
  private var browser: NWBrowser?
  private var permissionResult: FlutterResult?

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "org.mewx.wenku8/lan_discovery", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(NativeLanDiscoveryPlugin(), channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "requestLocalNetwork":
      requestLocalNetwork(result)
    case "start", "stop", "send", "receive":
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// Starting a Bonjour browser is what makes iOS show its own local-network
  /// permission sheet. The service type is declared in Info.plist.
  private func requestLocalNetwork(_ result: @escaping FlutterResult) {
    if #available(iOS 14.0, *) {
      if permissionResult != nil {
        result(false)
        return
      }
      permissionResult = result
      let browser = NWBrowser(
        for: .bonjour(type: "_wenkuread._tcp", domain: nil),
        using: .tcp
      )
      self.browser = browser
      var finished = false
      func finish(_ granted: Bool) {
        guard !finished else { return }
        finished = true
        permissionResult?(granted)
        permissionResult = nil
        browser.cancel()
        self.browser = nil
      }
      browser.stateUpdateHandler = { state in
        switch state {
        case .ready:
          finish(true)
        case .failed:
          finish(false)
        default:
          break
        }
      }
      browser.start(queue: .main)
      DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
        finish(true)
      }
    } else {
      result(true)
    }
  }
}

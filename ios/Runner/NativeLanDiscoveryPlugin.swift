import Flutter
import Foundation

/// 局域网发现的占位实现：注册通道、对未实现的方法返回 FlutterMethodNotImplemented。
final class NativeLanDiscoveryPlugin: NSObject, FlutterPlugin {
  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "org.mewx.wenku8/lan_discovery", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(NativeLanDiscoveryPlugin(), channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "start", "stop", "send", "receive":
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}

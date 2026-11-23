import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "QuranNativeGlass") else {
      return
    }
    registrar.register(QuranGlassFactory(), withId: "quran/native_glass")
    let channel = FlutterMethodChannel(name: "quran/native_glass", binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { call, result in
      guard call.method == "available" else {
        result(FlutterMethodNotImplemented)
        return
      }
      if #available(iOS 26.0, *) {
        result(!UIAccessibility.isReduceTransparencyEnabled)
      } else {
        result(false)
      }
    }
  }
}

private final class QuranGlassFactory: NSObject, FlutterPlatformViewFactory {
  func create(
    withFrame frame: CGRect,
    viewIdentifier viewId: Int64,
    arguments args: Any?
  ) -> FlutterPlatformView {
    QuranGlassView(frame: frame, options: args as? [String: Any] ?? [:])
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }
}

private final class QuranGlassView: NSObject, FlutterPlatformView {
  private let backdrop: UIVisualEffectView

  init(frame: CGRect, options: [String: Any]) {
    let dark = options["dark"] as? Bool ?? false
    let radius = options["radius"] as? Double ?? 24
    if #available(iOS 26.0, *), !UIAccessibility.isReduceTransparencyEnabled {
      backdrop = UIVisualEffectView(effect: UIGlassEffect(style: .regular))
    } else {
      backdrop = UIVisualEffectView()
      backdrop.backgroundColor = .secondarySystemBackground
    }
    backdrop.frame = frame
    backdrop.overrideUserInterfaceStyle = dark ? .dark : .light
    backdrop.layer.cornerRadius = CGFloat(radius)
    backdrop.clipsToBounds = true
    backdrop.isUserInteractionEnabled = false
    backdrop.isAccessibilityElement = false
    super.init()
  }

  func view() -> UIView {
    backdrop
  }
}

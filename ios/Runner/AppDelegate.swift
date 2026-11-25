import Flutter
import UIKit

// iOS 27 requires the UIScene lifecycle (TN3187). With scenes there's no
// window during didFinishLaunching, so the StoreKit bridge is registered once
// Flutter's implicit engine exists, and it looks up the view controller on
// each call.
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
    TeamSubscriptionBridge.register(with: engineBridge.applicationRegistrar.messenger())
  }
}

import Firebase
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Must run before any Firebase API is touched. Kept here (rather than in
    // didInitializeImplicitFlutterEngine) so it happens as early as possible.
    FirebaseApp.configure()

    // Route APNs callbacks through UNUserNotificationCenter so
    // firebase_messaging can observe delivery and taps. FlutterAppDelegate is
    // already a UNUserNotificationCenterDelegate, so `self` is correct here.
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // NOTE: plugin registration deliberately stays here and ONLY here.
  //
  // The Firebase docs tell you to add `GeneratedPluginRegistrant.register(with: self)`
  // inside didFinishLaunchingWithOptions. Do NOT do that in this project — this
  // app uses the modern FlutterImplicitEngineDelegate lifecycle, so the line
  // below already registers every plugin. Adding the documented one as well
  // registers them twice and crashes at startup.
  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}

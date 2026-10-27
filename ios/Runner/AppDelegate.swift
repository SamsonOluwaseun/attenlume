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
    // App Intents and deep links [P0-13].
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "AttenlumeShortcuts") {
      ShortcutCommandCenter.register(with: registrar)
    }
    // Free space queries [P1-12, FR-STO-01].
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "AttenlumeFreeSpace") {
      FreeSpaceChannel.register(with: registrar)
    }
  }
}

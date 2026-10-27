import Flutter
import UIKit

/// Carries shortcut triggers (App Intents, `attenlume://` deep links) to
/// Dart as URIs [P0-13, FR-HF-01, FR-HF-05].
///
/// Kept thin on purpose: Dart's `ShortcutCommand.parse` decides what a URI
/// means. A command that arrives before Dart asks is held as the initial
/// command; later ones go straight over the channel. Registered as an
/// in-app plugin so it receives scene URL events through Flutter's own
/// scene delegate (`addSceneDelegate`) without overriding it.
///
/// Not built or run yet: needs a Mac with Xcode (PLATFORM_FEASIBILITY 2.13).
final class ShortcutCommandCenter: NSObject, FlutterPlugin, FlutterSceneLifeCycleDelegate {
  static let channelName = "com.samlytics.attenlume/shortcuts"
  static let scheme = "attenlume"
  static let shared = ShortcutCommandCenter()

  private var channel: FlutterMethodChannel?
  private var initial: [String: Any]?
  private var dartAskedForInitial = false
  private var sceneEverConnected = false

  /// Dart is running and has asked for its initial command.
  var isAttached: Bool { channel != nil && dartAskedForInitial }

  static func register(with registrar: FlutterPluginRegistrar) {
    let center = ShortcutCommandCenter.shared
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "takeInitialCommand":
        center.dartAskedForInitial = true
        result(center.initial)
        center.initial = nil
      default:
        // setTileDirect: there is no tile on iOS.
        result(FlutterMethodNotImplemented)
      }
    }
    center.channel = channel
    registrar.addSceneDelegate(center)
  }

  // MARK: Scene events

  func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions?
  ) -> Bool {
    let coldStart = !sceneEverConnected
    sceneEverConnected = true
    guard let url = connectionOptions?.urlContexts.first?.url else { return false }
    return queueOrSend(url: url, coldStart: coldStart, direct: false)
  }

  func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) -> Bool {
    var handled = false
    for context in URLContexts {
      handled = queueOrSend(url: context.url, coldStart: false, direct: false) || handled
    }
    return handled
  }

  // MARK: Delivery

  /// Sends a command for an App Intent. With [direct] (the intent did not
  /// open the app) a command is only sent to a running Flutter engine and
  /// never queued, so a stale stop or bookmark cannot run on a later
  /// launch. Returns whether Dart has it or will get it.
  @discardableResult
  func sendIntent(path: String, direct: Bool) -> Bool {
    guard let url = URL(string: "\(Self.scheme)://\(path)?source=app_intent") else { return false }
    if direct && !isAttached { return false }
    return queueOrSend(url: url, coldStart: !sceneEverConnected, direct: direct)
  }

  private func queueOrSend(url: URL, coldStart: Bool, direct: Bool) -> Bool {
    guard url.scheme?.lowercased() == Self.scheme else { return false }
    let payload: [String: Any] = [
      "uri": url.absoluteString,
      "triggeredAtMs": Int(Date().timeIntervalSince1970 * 1000),
      "coldStart": coldStart,
      "appVisible": UIApplication.shared.applicationState == .active,
      "direct": direct,
    ]
    if let channel, dartAskedForInitial {
      channel.invokeMethod("command", arguments: payload)
    } else {
      initial = payload
    }
    return true
  }
}

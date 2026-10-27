import Flutter
import UIKit

/// Carries free and total volume space to Dart [P1-12, FR-STO-01].
final class FreeSpaceChannel: NSObject, FlutterPlugin {
  static let channelName = "com.samlytics.attenlume/free_space"

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: registrar.messenger())
    let instance = FreeSpaceChannel()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    if call.method == "queryFreeSpace" {
      guard let args = call.arguments as? [String: Any],
            let path = args["path"] as? String else {
        result(FlutterError(code: "INVALID_ARGUMENT", message: "Path is required", details: nil))
        return
      }

      var url = URL(fileURLWithPath: path)
      let fm = FileManager.default
      while !fm.fileExists(atPath: url.path) {
        let parent = url.deletingLastPathComponent()
        if parent.path == url.path { break }
        url = parent
      }

      if !fm.fileExists(atPath: url.path) {
        result(nil)
        return
      }

      do {
        let values = try url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey])
        if let available = values.volumeAvailableCapacityForImportantUsage,
           let total = values.volumeTotalCapacity {
          result([
            "availableBytes": available,
            "totalBytes": total
          ])
          return
        }
      } catch {}

      // Fallback to file system attributes
      do {
        let attrs = try fm.attributesOfFileSystem(forPath: url.path)
        if let freeSize = attrs[.systemFreeSize] as? NSNumber,
           let totalSize = attrs[.systemSize] as? NSNumber {
          result([
            "availableBytes": freeSize.int64Value,
            "totalBytes": totalSize.int64Value
          ])
          return
        }
      } catch {}

      result(nil)
    } else {
      result(FlutterMethodNotImplemented)
    }
  }
}

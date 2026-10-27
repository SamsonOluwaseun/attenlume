import AppIntents
import Foundation

// App Intents for Siri and Shortcuts [P0-13, FR-HF-01].
//
// Intents that need a fresh microphone recording or the camera open the app
// first (`openAppWhenRun`), because iOS does not document starting
// microphone capture from the background (BUILD_GUIDE 10.1). Stop and
// Bookmark act on a recording that is already running, so they do not open
// the app. "Start recording without opening" is the P0-13 test of that
// rule (MT-22) and is left out of the Siri phrases.
//
// Not built or run yet: needs a Mac with Xcode (PLATFORM_FEASIBILITY 2.13).

@available(iOS 16.0, *)
struct StartRecordingIntent: AppIntent {
  static let title: LocalizedStringResource = "Start recording"
  static let description = IntentDescription(
    "Opens Attenlume and starts recording the current activity.")
  static let openAppWhenRun = true

  @MainActor
  func perform() async throws -> some IntentResult {
    ShortcutCommandCenter.shared.sendIntent(path: "record/start", direct: false)
    return .result()
  }
}

@available(iOS 16.0, *)
struct StopRecordingIntent: AppIntent {
  static let title: LocalizedStringResource = "Stop recording"
  static let description = IntentDescription("Stops and saves the recording.")
  static let openAppWhenRun = false

  @MainActor
  func perform() async throws -> some IntentResult & ProvidesDialog {
    let sent = ShortcutCommandCenter.shared.sendIntent(path: "record/stop", direct: true)
    return .result(dialog: sent ? "Stopping the recording." : "Attenlume is not recording.")
  }
}

@available(iOS 16.0, *)
struct BookmarkIntent: AppIntent {
  static let title: LocalizedStringResource = "Bookmark"
  static let description = IntentDescription("Bookmarks this moment in the recording.")
  static let openAppWhenRun = false

  @MainActor
  func perform() async throws -> some IntentResult & ProvidesDialog {
    let sent = ShortcutCommandCenter.shared.sendIntent(path: "bookmark", direct: true)
    return .result(dialog: sent ? "Bookmark added." : "Attenlume is not recording.")
  }
}

@available(iOS 16.0, *)
struct NewConversationIntent: AppIntent {
  static let title: LocalizedStringResource = "New conversation"
  static let description = IntentDescription("Opens Attenlume to start a new conversation.")
  static let openAppWhenRun = true

  @MainActor
  func perform() async throws -> some IntentResult {
    ShortcutCommandCenter.shared.sendIntent(path: "conversation/new", direct: false)
    return .result()
  }
}

@available(iOS 16.0, *)
struct TakePhotoIntent: AppIntent {
  static let title: LocalizedStringResource = "Take photo"
  static let description = IntentDescription("Opens the Attenlume camera.")
  static let openAppWhenRun = true

  @MainActor
  func perform() async throws -> some IntentResult {
    ShortcutCommandCenter.shared.sendIntent(path: "photo", direct: false)
    return .result()
  }
}

/// P0-13 test only: asks a running app to start recording without opening
/// it. MT-22 records whether iOS allows it and whether the audio is silent.
@available(iOS 16.0, *)
struct StartRecordingWithoutOpeningIntent: AppIntent {
  static let title: LocalizedStringResource = "Start recording without opening (test)"
  static let description = IntentDescription(
    "Test for developers: asks Attenlume to start recording without opening it.")
  static let openAppWhenRun = false

  @MainActor
  func perform() async throws -> some IntentResult & ProvidesDialog {
    let sent = ShortcutCommandCenter.shared.sendIntent(path: "record/start", direct: true)
    return .result(dialog: sent ? "Asked Attenlume to start." : "Attenlume is not running.")
  }
}

@available(iOS 16.0, *)
struct AttenlumeShortcuts: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    AppShortcut(
      intent: StartRecordingIntent(),
      phrases: [
        "Start recording in \(.applicationName)",
        "Start session in \(.applicationName)",
      ])
    AppShortcut(
      intent: StopRecordingIntent(),
      phrases: ["Stop recording in \(.applicationName)"])
    AppShortcut(
      intent: BookmarkIntent(),
      phrases: ["Bookmark in \(.applicationName)"])
    AppShortcut(
      intent: NewConversationIntent(),
      phrases: ["New conversation in \(.applicationName)"])
    AppShortcut(
      intent: TakePhotoIntent(),
      phrases: ["Take a photo in \(.applicationName)"])
  }
}

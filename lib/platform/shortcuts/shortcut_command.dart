/// Commands that reach the app from outside its own UI: an Android Quick
/// Settings tile or launcher shortcut, an iOS App Intent, or a deep link
/// [P0-13, FR-HF-01, FR-HF-04, FR-HF-05].
///
/// Every trigger is carried as one URI, so the native side stays thin and
/// a single parser decides what it means:
///
///   attenlume://record/start      attenlume://record/stop
///   attenlume://record/toggle     attenlume://bookmark
///   attenlume://photo             attenlume://conversation/new
///
/// Optional query parameters: `source` (see [ShortcutSource]) and
/// `activity` (a UUID v4). Anything else is ignored, and a URI that does not
/// match is dropped rather than guessed at.
library;

/// The URI scheme the app registers on Android and iOS (ADR-018).
const shortcutScheme = 'attenlume';

enum ShortcutAction {
  startRecording('start'),
  stopRecording('stop'),
  toggleRecording('toggle'),
  bookmark('bookmark'),
  newConversation('new_conversation'),
  takePhoto('photo');

  const ShortcutAction(this.key);
  final String key;
}

enum ShortcutSource {
  quickSettingsTile('tile'),
  appShortcut('app_shortcut'),
  appIntent('app_intent'),
  notification('notification'),
  deepLink('deep_link');

  const ShortcutSource(this.key);
  final String key;

  static ShortcutSource fromKey(String? key) => ShortcutSource.values
      .firstWhere((s) => s.key == key, orElse: () => ShortcutSource.deepLink);
}

final _uuidV4 = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);

/// One trigger, as the native side reported it.
class ShortcutCommand {
  const ShortcutCommand({
    required this.action,
    required this.source,
    this.activityId,
    this.triggeredAt,
    this.coldStart = false,
    this.appVisibleAtTrigger,
    this.deliveredDirect = false,
  });

  final ShortcutAction action;
  final ShortcutSource source;

  /// The activity the trigger names, or null for "the current one".
  final String? activityId;

  /// When the user tapped the tile or ran the intent (UTC), if the native
  /// side recorded it. Used to measure trigger-to-recording time.
  final DateTime? triggeredAt;

  /// True when this trigger launched the app process.
  final bool coldStart;

  /// Whether an app screen was on show when the trigger fired. Null when
  /// the native side could not tell.
  final bool? appVisibleAtTrigger;

  /// True when the native side handed the command to a running app without
  /// opening it (the Android tile's direct mode, the iOS background
  /// intent). This is the cold-start question P0-13 exists to answer.
  final bool deliveredDirect;

  /// Parses [uri], or returns null when it is not one of ours.
  static ShortcutCommand? parse(
    Uri uri, {
    DateTime? triggeredAt,
    bool coldStart = false,
    bool? appVisibleAtTrigger,
    bool deliveredDirect = false,
  }) {
    if (uri.scheme.toLowerCase() != shortcutScheme) return null;
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    final action = switch ((uri.host.toLowerCase(), segments)) {
      ('record', ['start']) => ShortcutAction.startRecording,
      ('record', ['stop']) => ShortcutAction.stopRecording,
      ('record', ['toggle']) => ShortcutAction.toggleRecording,
      ('bookmark', []) => ShortcutAction.bookmark,
      ('photo', []) => ShortcutAction.takePhoto,
      ('conversation', ['new']) => ShortcutAction.newConversation,
      _ => null,
    };
    if (action == null) return null;
    final activity = uri.queryParameters['activity']?.toLowerCase();
    return ShortcutCommand(
      action: action,
      source: ShortcutSource.fromKey(uri.queryParameters['source']),
      activityId: activity != null && _uuidV4.hasMatch(activity)
          ? activity
          : null,
      triggeredAt: triggeredAt?.toUtc(),
      coldStart: coldStart,
      appVisibleAtTrigger: appVisibleAtTrigger,
      deliveredDirect: deliveredDirect,
    );
  }

  /// Parses the map the native side sends over the platform channel:
  /// `uri` (required), `triggeredAtMs` (epoch milliseconds), `coldStart`,
  /// `appVisible` and `direct`. Returns null for anything malformed.
  static ShortcutCommand? fromChannel(Object? arguments) {
    if (arguments is! Map) return null;
    final raw = arguments['uri'];
    if (raw is! String) return null;
    final uri = Uri.tryParse(raw);
    if (uri == null) return null;
    final ms = arguments['triggeredAtMs'];
    return parse(
      uri,
      triggeredAt: ms is int
          ? DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true)
          : null,
      coldStart: arguments['coldStart'] == true,
      appVisibleAtTrigger: switch (arguments['appVisible']) {
        final bool b => b,
        _ => null,
      },
      deliveredDirect: arguments['direct'] == true,
    );
  }

  /// The URI that means this command, for building shortcuts and tests.
  Uri toUri() {
    final (host, path) = switch (action) {
      ShortcutAction.startRecording => ('record', '/start'),
      ShortcutAction.stopRecording => ('record', '/stop'),
      ShortcutAction.toggleRecording => ('record', '/toggle'),
      ShortcutAction.bookmark => ('bookmark', ''),
      ShortcutAction.takePhoto => ('photo', ''),
      ShortcutAction.newConversation => ('conversation', '/new'),
    };
    return Uri(
      scheme: shortcutScheme,
      host: host,
      path: path,
      queryParameters: {'source': source.key, 'activity': ?activityId},
    );
  }

  Map<String, Object?> toJson() => {
    'action': action.key,
    'source': source.key,
    'activity_id': activityId,
    'triggered_at': triggeredAt?.toIso8601String(),
    'cold_start': coldStart,
    'app_visible_at_trigger': appVisibleAtTrigger,
    'delivered_direct': deliveredDirect,
  };

  @override
  String toString() => 'ShortcutCommand(${action.key} from ${source.key})';
}

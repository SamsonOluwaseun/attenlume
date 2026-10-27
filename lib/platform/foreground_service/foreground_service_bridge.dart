import 'dart:async';

import 'package:flutter/services.dart';

import '../../domain/services/recording_state.dart';

/// Actions triggered by the user from the persistent notification (FR-REC-10) [P1-11].
enum ForegroundServiceAction {
  pause('pause'),
  resume('resume'),
  stop('stop'),
  bookmark('bookmark'),
  photo('photo');

  const ForegroundServiceAction(this.key);
  final String key;

  static ForegroundServiceAction? fromKey(String? key) {
    if (key == null) return null;
    for (final action in ForegroundServiceAction.values) {
      if (action.key == key) return action;
    }
    return null;
  }
}

/// Metadata passed to the native platform to display and update the
/// ongoing notification [FR-REC-10].
class NotificationDetails {
  const NotificationDetails({
    required this.activityId,
    required this.title,
    required this.state,
    this.elapsed,
    this.baseTimeUtc,
    this.message,
  });

  final String activityId;
  final String title;
  final RecordingState state;
  final Duration? elapsed;
  final DateTime? baseTimeUtc;
  final String? message;

  Map<String, Object?> toMap() => {
    'activityId': activityId,
    'title': title,
    'state': state.name,
    'elapsedMs': elapsed?.inMilliseconds,
    'baseTimeMs': baseTimeUtc?.millisecondsSinceEpoch,
    'message': message,
  };

  @override
  String toString() =>
      'NotificationDetails(activity: $activityId, title: $title, state: ${state.name}, message: $message)';
}

/// Platform bridge for managing the Android foreground service and ongoing
/// notification while recording (FR-REC-10) [P1-11].
///
/// On Android, a microphone foreground service is required to continue
/// recording audio when the app is backgrounded or screen is locked (BUILD_GUIDE 10.2).
/// On other platforms (iOS, Windows), [NoopForegroundServiceBridge] is used.
abstract interface class ForegroundServiceBridge {
  /// Starts the foreground service and displays the ongoing notification.
  Future<void> startService(NotificationDetails details);

  /// Updates the notification title, status, timer, and action buttons.
  Future<void> updateNotification(NotificationDetails details);

  /// Stops the foreground service and removes the notification.
  Future<void> stopService();

  /// Stream of user action button taps from the notification.
  Stream<ForegroundServiceAction> get actions;

  /// Whether the service is currently considered running.
  bool get isRunning;
}

/// No-op implementation for non-Android platforms (Windows, iOS) or tests.
class NoopForegroundServiceBridge implements ForegroundServiceBridge {
  const NoopForegroundServiceBridge();

  @override
  bool get isRunning => false;

  @override
  Stream<ForegroundServiceAction> get actions => const Stream.empty();

  @override
  Future<void> startService(NotificationDetails details) async {}

  @override
  Future<void> updateNotification(NotificationDetails details) async {}

  @override
  Future<void> stopService() async {}
}

/// Android platform bridge connecting Dart to `RecordingForegroundService.kt`
/// via [MethodChannel] (FR-REC-10).
class MethodChannelForegroundServiceBridge implements ForegroundServiceBridge {
  MethodChannelForegroundServiceBridge({
    this.channel = const MethodChannel(channelName),
    this.onMalformed,
  }) {
    channel.setMethodCallHandler(_handleMethodCall);
  }

  static const channelName = 'com.samlytics.attenlume/foreground_service';

  final MethodChannel channel;
  final void Function(Object? arguments)? onMalformed;
  final _actions = StreamController<ForegroundServiceAction>.broadcast();
  bool _isRunning = false;

  @override
  bool get isRunning => _isRunning;

  @override
  Stream<ForegroundServiceAction> get actions => _actions.stream;

  Future<Object?> _handleMethodCall(MethodCall call) async {
    if (call.method != 'onAction') {
      throw MissingPluginException('No handler for ${call.method}');
    }
    final arguments = call.arguments;
    final actionKey = switch (arguments) {
      final Map<Object?, Object?> map => map['action'] as String?,
      final String str => str,
      _ => null,
    };
    final action = ForegroundServiceAction.fromKey(actionKey);
    if (action == null) {
      onMalformed?.call(arguments);
      return false;
    }
    _actions.add(action);
    return true;
  }

  @override
  Future<void> startService(NotificationDetails details) async {
    try {
      await channel.invokeMethod<void>('startService', details.toMap());
      _isRunning = true;
    } on MissingPluginException {
      // Platform channel not available.
    }
  }

  @override
  Future<void> updateNotification(NotificationDetails details) async {
    try {
      await channel.invokeMethod<void>('updateNotification', details.toMap());
    } on MissingPluginException {
      // Platform channel not available.
    }
  }

  @override
  Future<void> stopService() async {
    try {
      await channel.invokeMethod<void>('stopService');
    } on MissingPluginException {
      // Platform channel not available.
    } finally {
      _isRunning = false;
    }
  }

  Future<void> dispose() async {
    channel.setMethodCallHandler(null);
    await _actions.close();
  }
}

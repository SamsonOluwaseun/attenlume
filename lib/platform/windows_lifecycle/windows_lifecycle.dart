import 'dart:async';

import 'package:flutter/services.dart';

import '../../domain/services/recording_state.dart';

/// Native window lifetime follows the recorder, including paused/error states.
/// It never treats a completed stop future alone as proof of a saved recording.
class WindowsLifecycle {
  WindowsLifecycle({
    required this.status,
    required this.changes,
    required this.stop,
    this.channel = const MethodChannel(
      'com.samlytics.attenlume/windows_lifecycle',
    ),
  });

  final RecordingStatus Function() status;
  final Stream<RecordingStatus> changes;
  final Future<void> Function() stop;
  final MethodChannel channel;
  StreamSubscription<RecordingStatus>? _subscription;
  bool _quitting = false;
  bool _disposed = false;
  Future<void> _updates = Future<void>.value();

  Future<void> start() async {
    channel.setMethodCallHandler((call) async {
      if (call.method == 'saveAndQuit') await saveAndQuit();
    });
    _subscription = changes.listen(_publish);
    _publish(status());
    await _updates;
  }

  void _publish(RecordingStatus value) {
    _updates = _updates.then((_) async {
      if (_disposed) return;
      try {
        await channel.invokeMethod<void>('status', {
          'held': value.state.holdsActivity,
          // Deliberately omit activity titles and paths from the desktop tray.
          'state': value.state.name,
        });
      } on MissingPluginException {
        // Tests/older runners may not provide this optional desktop bridge.
      } on PlatformException {
        // Keep recording; native defaults to protecting the window lifetime.
      }
    });
  }

  Future<void> saveAndQuit() async {
    if (_quitting || _disposed) return;
    _quitting = true;
    try {
      if (status().state.holdsActivity) await stop();
      if (status().state.holdsActivity) {
        await _invoke('saveFailed');
        return;
      }
      await _updates;
      if (status().state.holdsActivity) {
        await _invoke('saveFailed');
        return;
      }
      if (!await _invoke('quit')) await _invoke('saveFailed');
    } on Object {
      await _invoke('saveFailed');
    } finally {
      _quitting = false;
    }
  }

  Future<bool> _invoke(String method) async {
    try {
      await channel.invokeMethod<void>(method);
      return true;
    } on MissingPluginException {
      // Optional bridge is absent: never terminate the process as a fallback.
    } on PlatformException {
      // Native exit failed: leave the app and all media available.
    }
    return false;
  }

  Future<void> dispose() async {
    _disposed = true;
    channel.setMethodCallHandler(null);
    await _subscription?.cancel();
  }
}

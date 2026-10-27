import 'dart:async';

import 'package:flutter/services.dart';

import 'shortcut_command.dart';

/// Triggers from outside the app's UI: Android tile and launcher shortcuts,
/// iOS App Intents, deep links (BUILD_GUIDE 9.3) [P0-13, FR-HF-01,
/// FR-HF-04, FR-HF-05].
///
/// The bridge only delivers commands. Deciding what they do (the one-active
/// rule, confirmation) belongs to the caller: the P0-13 spike now, the
/// Phase 2 shortcut handler later (P2-01, P2-03). Hotkeys (FR-HF-06, P2-05)
/// will arrive through the same interface on Windows.
abstract interface class ShortcutBridge {
  /// The trigger that launched or reopened the app before Dart was
  /// listening, if any. Each command is returned once.
  Future<ShortcutCommand?> takeInitialCommand();

  /// Triggers that arrive while the app is running.
  Stream<ShortcutCommand> get commands;

  /// Spike setting for the Android tile: when [direct] is true and the app
  /// is already running, a tap sends the command without opening the app.
  /// Ignored where there is no tile.
  Future<void> setTileDirect(bool direct);
}

/// For platforms with no native shortcuts yet (Windows until P2-05).
class NoShortcutBridge implements ShortcutBridge {
  const NoShortcutBridge();

  @override
  Future<ShortcutCommand?> takeInitialCommand() async => null;

  @override
  Stream<ShortcutCommand> get commands => const Stream.empty();

  @override
  Future<void> setTileDirect(bool direct) async {}
}

/// Talks to `MainActivity.kt` / `ShortcutChannel.kt` on Android and
/// `ShortcutCommandCenter.swift` on iOS.
///
/// Native to Dart: `command` with the map [ShortcutCommand.fromChannel]
/// reads. Dart to native: `takeInitialCommand` and `setTileDirect`.
class MethodChannelShortcutBridge implements ShortcutBridge {
  MethodChannelShortcutBridge({
    this.channel = const MethodChannel(channelName),
    this.onMalformed,
  }) {
    channel.setMethodCallHandler(_handle);
  }

  static const channelName = 'com.samlytics.attenlume/shortcuts';

  final MethodChannel channel;

  /// Called with any payload that is not a valid command, for logging.
  final void Function(Object? arguments)? onMalformed;
  final _commands = StreamController<ShortcutCommand>.broadcast();

  Future<Object?> _handle(MethodCall call) async {
    if (call.method != 'command') {
      throw MissingPluginException('No handler for ${call.method}');
    }
    final command = ShortcutCommand.fromChannel(call.arguments);
    if (command == null) {
      onMalformed?.call(call.arguments);
      return false;
    }
    _commands.add(command);
    return true;
  }

  @override
  Future<ShortcutCommand?> takeInitialCommand() async {
    try {
      final arguments = await channel.invokeMethod<Object?>(
        'takeInitialCommand',
      );
      if (arguments == null) return null;
      final command = ShortcutCommand.fromChannel(arguments);
      if (command == null) onMalformed?.call(arguments);
      return command;
    } on MissingPluginException {
      return null;
    }
  }

  @override
  Stream<ShortcutCommand> get commands => _commands.stream;

  @override
  Future<void> setTileDirect(bool direct) async {
    try {
      await channel.invokeMethod<void>('setTileDirect', {'direct': direct});
    } on MissingPluginException {
      // iOS has no tile.
    }
  }

  Future<void> dispose() async {
    channel.setMethodCallHandler(null);
    await _commands.close();
  }
}

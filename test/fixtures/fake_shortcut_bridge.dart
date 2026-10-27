import 'dart:async';

import 'package:attenlume/platform/shortcuts/shortcut_bridge.dart';
import 'package:attenlume/platform/shortcuts/shortcut_command.dart';

/// A [ShortcutBridge] tests drive by hand [P0-13].
class FakeShortcutBridge implements ShortcutBridge {
  final _controller = StreamController<ShortcutCommand>.broadcast();

  /// Returned once by [takeInitialCommand].
  ShortcutCommand? initial;
  final List<bool> tileDirectCalls = [];

  void send(ShortcutCommand command) => _controller.add(command);

  @override
  Future<ShortcutCommand?> takeInitialCommand() async {
    final c = initial;
    initial = null;
    return c;
  }

  @override
  Stream<ShortcutCommand> get commands => _controller.stream;

  @override
  Future<void> setTileDirect(bool direct) async => tileDirectCalls.add(direct);

  Future<void> close() => _controller.close();
}

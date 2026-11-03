import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../platform/shortcuts/shortcut_command.dart';
import 'shortcut_providers.dart';

/// Listens for shortcut triggers (launcher shortcuts, Quick Settings tile,
/// `attenlume://` deep links) and routes them through [ShortcutCoordinator]
/// [P0-13, P2-03, FR-HF-01, FR-HF-04, FR-HF-05].
class ShortcutGate extends ConsumerStatefulWidget {
  const ShortcutGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<ShortcutGate> createState() => _ShortcutGateState();
}

class _ShortcutGateState extends ConsumerState<ShortcutGate> {
  StreamSubscription<ShortcutCommand>? _subscription;

  @override
  void initState() {
    super.initState();
    final bridge = ref.read(shortcutBridgeProvider);
    _subscription = bridge.commands.listen(_handleCommand);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkInitialCommand();
    });
  }

  Future<void> _checkInitialCommand() async {
    final bridge = ref.read(shortcutBridgeProvider);
    final initial = await bridge.takeInitialCommand();
    if (initial != null && mounted) {
      await _handleCommand(initial);
    }
  }

  Future<void> _handleCommand(ShortcutCommand command) async {
    final coordinator = ref.read(shortcutCoordinatorProvider);
    await coordinator.handleCommand(command);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

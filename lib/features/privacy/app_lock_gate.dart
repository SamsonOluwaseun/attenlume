import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/tokens.dart';
import '../../domain/services/recording_state.dart';
import '../../platform/device_auth/device_authenticator.dart';
import '../../presentation/components/attenlume_button.dart';
import '../capture/recording_providers.dart';
import 'app_lock_controller.dart';

/// Puts the app lock cover over every route when locked (FR-PRI-06,
/// ADR-041). Sits in `MaterialApp.builder`, so dialogs and sheets are
/// covered too.
///
/// The screens underneath stay mounted, so a recording screen keeps its
/// state, and nothing here calls the recorder except the cover's Stop
/// button. They are hidden from screen readers and keyboard focus while
/// locked.
class AppLockGate extends ConsumerStatefulWidget {
  const AppLockGate({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends ConsumerState<AppLockGate>
    with WidgetsBindingObserver {
  late final AppLockController _lock;

  @override
  void initState() {
    super.initState();
    _lock = ref.read(appLockControllerProvider);
    WidgetsBinding.instance.addObserver(this);
    unawaited(_lock.load());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        _lock.onBackground();
      case AppLifecycleState.resumed:
        _lock.onForeground();
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        // Inactive also happens for the OS prompt, a notification shade or
        // a call banner: not a reason to lock.
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _lock,
      builder: (context, _) {
        final locked = _lock.locked;
        // Until settings are read, show nothing of the app if a lock could
        // be on. This is one frame on a normal start.
        final hide = locked || !_lock.loaded;
        return Stack(
          fit: StackFit.expand,
          children: [
            ExcludeSemantics(
              excluding: hide,
              child: ExcludeFocus(excluding: hide, child: widget.child),
            ),
            if (locked)
              AppLockCover(controller: _lock)
            else if (!_lock.loaded)
              ColoredBox(color: Theme.of(context).colorScheme.surface),
          ],
        );
      },
    );
  }
}

/// The lock cover: a plain message, an Unlock button, and, while a
/// recording is held, a strip that says so with a Stop button (FR-PRI-02).
class AppLockCover extends ConsumerStatefulWidget {
  const AppLockCover({required this.controller, super.key});

  final AppLockController controller;

  @override
  ConsumerState<AppLockCover> createState() => _AppLockCoverState();
}

class _AppLockCoverState extends ConsumerState<AppLockCover> {
  bool _stopping = false;

  @override
  void initState() {
    super.initState();
    // Ask straight away, as people expect, unless a prompt is already up.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.controller.lastResult == null) {
        unawaited(widget.controller.unlock());
      }
    });
  }

  Future<void> _stop() async {
    setState(() => _stopping = true);
    try {
      await ref.read(recordingServiceProvider).stop();
    } finally {
      if (mounted) setState(() => _stopping = false);
    }
  }

  static String? messageFor(DeviceAuthResult? result) => switch (result) {
    DeviceAuthResult.cancelled => 'Not unlocked. Tap Unlock to try again.',
    DeviceAuthResult.lockedOut =>
      'Too many tries. Wait a moment, or unlock your device first, then '
          'try again.',
    DeviceAuthResult.unavailable =>
      'This device cannot check it is you right now. Fingerprint, face, '
          'PIN or Windows Hello may have been turned off. You can turn app '
          'lock off to get back to your recordings, and turn it on again '
          'later in Privacy.',
    DeviceAuthResult.success || null => null,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lock = widget.controller;
    final status = ref.watch(recordingStatusProvider).asData?.value;
    final holdsRecording = status?.state.holdsActivity ?? false;
    final message = messageFor(lock.lastResult);

    return Material(
      key: const Key('app-lock-cover'),
      color: theme.colorScheme.surface,
      child: SafeArea(
        child: Column(
          children: [
            if (holdsRecording)
              _RecordingStrip(
                state: status!.state,
                stopping: _stopping,
                onStop: _stop,
              ),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(TokenSpace.space5),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Icon(
                          Icons.lock_outline_rounded,
                          size: 48,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(height: TokenSpace.space4),
                        Text(
                          'Attenlume is locked',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: TokenSpace.space2),
                        Text(
                          'Unlock with your fingerprint, face, device PIN '
                          'or Windows Hello.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        if (message != null) ...[
                          const SizedBox(height: TokenSpace.space4),
                          Text(
                            message,
                            key: const Key('app-lock-message'),
                            style: theme.textTheme.bodyMedium,
                            textAlign: TextAlign.center,
                          ),
                        ],
                        const SizedBox(height: TokenSpace.space5),
                        AttenlumeButton(
                          key: const Key('app-lock-unlock'),
                          label: 'Unlock',
                          leading: const Icon(Icons.lock_open_rounded),
                          onPressed: lock.authenticating
                              ? null
                              : () => unawaited(lock.unlock()),
                        ),
                        if (lock.canTurnOffWithoutCheck) ...[
                          const SizedBox(height: TokenSpace.space2),
                          AttenlumeButton(
                            key: const Key('app-lock-turn-off'),
                            label: 'Turn off app lock',
                            variant: AttenlumeButtonVariant.secondary,
                            onPressed: () =>
                                unawaited(lock.turnOffBecauseUnavailable()),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Recording is still on" with Stop, on the navy live surface. No title,
/// so the cover shows nothing about what is being recorded.
class _RecordingStrip extends StatelessWidget {
  const _RecordingStrip({
    required this.state,
    required this.stopping,
    required this.onStop,
  });

  final RecordingState state;
  final bool stopping;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = switch (state) {
      RecordingState.paused => 'Recording paused. It is safe while locked.',
      RecordingState.recording ||
      RecordingState.switchingSegment ||
      RecordingState.starting =>
        'Recording is still on. Locking does not stop it.',
      _ => 'A recording is open. Locking does not change it.',
    };
    return Semantics(
      container: true,
      liveRegion: true,
      child: Container(
        key: const Key('app-lock-recording-strip'),
        color: TokenColors.light.liveSurface,
        padding: const EdgeInsets.symmetric(
          horizontal: TokenSpace.space4,
          vertical: TokenSpace.space3,
        ),
        child: Row(
          children: [
            Icon(Icons.circle, size: 12, color: TokenColors.light.live),
            const SizedBox(width: TokenSpace.space3),
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: TokenColors.light.onLiveSurface,
                ),
              ),
            ),
            const SizedBox(width: TokenSpace.space3),
            TextButton.icon(
              key: const Key('app-lock-stop-recording'),
              onPressed: stopping ? null : onStop,
              style: TextButton.styleFrom(
                foregroundColor: TokenColors.light.onLiveSurface,
                minimumSize: const Size(TokenSize.tapMin, TokenSize.tapMin),
              ),
              icon: Icon(Icons.stop_rounded, color: TokenColors.light.stop),
              label: const Text('Stop'),
            ),
          ],
        ),
      ),
    );
  }
}

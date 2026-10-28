import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/tokens.dart';
import '../../domain/services/recording_state.dart';
import 'recording_providers.dart';
import 'recording_screen.dart';

/// Puts [RecordingBanner] above [child], so screens other than the
/// recording screen always show that a recording is held (FR-PRI-02).
class WithRecordingBanner extends StatelessWidget {
  const WithRecordingBanner({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      const RecordingBanner(),
      Expanded(child: child),
    ],
  );
}

/// "Recording" or "Paused" with Open and a quick Stop, shown while a
/// recording is held (FR-PRI-02). Nothing is shown when idle or saved.
/// There is no setting to hide it: Attenlume has no hidden recording mode.
class RecordingBanner extends ConsumerWidget {
  const RecordingBanner({super.key});

  static String labelFor(RecordingState state) => switch (state) {
    RecordingState.paused => 'Recording paused',
    RecordingState.interrupted ||
    RecordingState.recovering ||
    RecordingState.userResumeRequired => 'Recording interrupted',
    RecordingState.errorRecoverable => 'Recording needs attention',
    RecordingState.storageStop => 'Recording stopped: storage full',
    _ => 'Recording',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(recordingStatusProvider).asData?.value;
    final activityId = status?.activityId;
    if (status == null || !status.state.holdsActivity || activityId == null) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    const colors = TokenColors.light;
    final canStop = status.state != RecordingState.stopping;

    return Semantics(
      container: true,
      liveRegion: true,
      child: Material(
        key: const Key('recording-banner'),
        color: colors.liveSurface,
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: TokenSpace.space4,
              vertical: TokenSpace.space1,
            ),
            child: Row(
              children: [
                Icon(Icons.circle, size: 12, color: colors.live),
                const SizedBox(width: TokenSpace.space3),
                Expanded(
                  child: Text(
                    labelFor(status.state),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.onLiveSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                TextButton(
                  key: const Key('recording-banner-open'),
                  style: TextButton.styleFrom(
                    foregroundColor: colors.onLiveSurface,
                    minimumSize: const Size(TokenSize.tapMin, TokenSize.tapMin),
                  ),
                  onPressed: () => unawaited(
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => RecordingScreen(activityId: activityId),
                      ),
                    ),
                  ),
                  child: const Text('Open'),
                ),
                TextButton.icon(
                  key: const Key('recording-banner-stop'),
                  style: TextButton.styleFrom(
                    foregroundColor: colors.onLiveSurface,
                    minimumSize: const Size(TokenSize.tapMin, TokenSize.tapMin),
                  ),
                  onPressed: canStop
                      ? () =>
                            unawaited(ref.read(recordingServiceProvider).stop())
                      : null,
                  icon: Icon(Icons.stop_rounded, color: colors.stop),
                  label: const Text('Stop'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

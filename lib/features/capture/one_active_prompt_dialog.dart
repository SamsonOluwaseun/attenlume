import 'package:flutter/material.dart';

import '../../app/theme/tokens.dart';
import '../../domain/services/one_active_coordinator.dart';
import '../../presentation/components/attenlume_button.dart';

/// The one-active prompt (FR-REC-04, AT-REC-04) [P1-06].
///
/// "'Data Mesh Keynote' is still recording (47 min). Stop it and start a
/// new one?" with Stop it and start new / Keep it running / Cancel.
/// Dismissing counts as Cancel. Nothing is stopped unless the person picks
/// the first option.
class OneActivePromptDialog extends StatelessWidget {
  const OneActivePromptDialog({required this.conflict, super.key});

  final OneActiveConflict conflict;

  /// Shows the prompt. Returns the choice, or null if dismissed.
  static Future<OneActiveChoice?> show(
    BuildContext context,
    OneActiveConflict conflict,
  ) => showDialog<OneActiveChoice>(
    context: context,
    builder: (context) => OneActivePromptDialog(conflict: conflict),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    void choose(OneActiveChoice choice) => Navigator.of(context).pop(choice);

    return AlertDialog(
      key: const Key('one-active-dialog'),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(TokenRadius.radiusLg)),
      ),
      icon: Icon(
        Icons.mic_none_rounded,
        size: 36,
        color: theme.colorScheme.primary,
      ),
      title: Text(
        conflict.message,
        key: const Key('one-active-message'),
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.bold,
        ),
        textAlign: TextAlign.center,
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Only one activity records at a time. Stopping saves '
              'everything recorded so far.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: TokenSpace.space4),
            AttenlumeButton(
              key: const Key('one-active-stop-and-start'),
              label: 'Stop it and start new',
              leading: const Icon(Icons.stop_circle_outlined),
              onPressed: () => choose(OneActiveChoice.stopAndStartNew),
            ),
            const SizedBox(height: TokenSpace.space2),
            AttenlumeButton(
              key: const Key('one-active-keep'),
              label: conflict.isPaused ? 'Keep it paused' : 'Keep it running',
              variant: AttenlumeButtonVariant.secondary,
              onPressed: () => choose(OneActiveChoice.keepRunning),
            ),
          ],
        ),
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        TextButton(
          key: const Key('one-active-cancel'),
          onPressed: () => choose(OneActiveChoice.cancel),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

/// Starts [activityId] from a button in the app, asking with
/// [OneActivePromptDialog] if another activity is recording.
Future<RecordRequestResult> startRecordingFromUi(
  BuildContext context,
  OneActiveCoordinator coordinator,
  String activityId,
) => coordinator.requestStart(
  activityId,
  trigger: RecordingTrigger.ui,
  prompt: (conflict) async {
    if (!context.mounted) return OneActiveChoice.cancel;
    return OneActivePromptDialog.show(context, conflict);
  },
);

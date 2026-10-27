import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/tokens.dart';
import '../../domain/services/crash_recovery_service.dart';
import '../../presentation/components/attenlume_button.dart';
import 'one_active_prompt_dialog.dart';
import 'recording_providers.dart';

/// Tells the person what crash recovery found and offers to carry on
/// recording (FR-REC-08, AT-REC-03) [P1-08].
///
/// Recovery has already marked every unfinished part `recovered` or
/// `damaged` and kept every file. This only reports and offers a restart.
class CrashRecoveryDialog extends StatelessWidget {
  const CrashRecoveryDialog({required this.report, super.key});

  final RecoveryReport report;

  /// Shows the dialog. Returns the activity to carry on recording, or null.
  static Future<String?> show(BuildContext context, RecoveryReport report) =>
      showDialog<String>(
        context: context,
        builder: (context) => CrashRecoveryDialog(report: report),
      );

  /// The one activity that was recording, which may carry on. Null when
  /// several were open or none was recording.
  String? get _carryOnId {
    final recording = report.activities.where((a) => a.wasRecording);
    return recording.length == 1 ? recording.single.activityId : null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final carryOn = _carryOnId;
    final unlinked = report.unlinkedFiles.length;

    return AlertDialog(
      key: const Key('crash-recovery-dialog'),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(TokenRadius.radiusLg)),
      ),
      icon: Icon(
        Icons.restore_rounded,
        size: 36,
        color: theme.colorScheme.primary,
      ),
      title: Text(
        'Your recording was recovered',
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.bold,
        ),
        textAlign: TextAlign.center,
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final activity in report.activities) ...[
                Text(
                  activity.message,
                  key: Key('crash-recovery-${activity.activityId}'),
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: TokenSpace.space2),
              ],
              if (unlinked > 0)
                Text(
                  unlinked == 1
                      ? 'One audio file is not linked to any activity. It is '
                            'kept in the app folder.'
                      : '$unlinked audio files are not linked to any '
                            'activity. They are kept in the app folder.',
                  key: const Key('crash-recovery-unlinked'),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              if (carryOn != null) ...[
                const SizedBox(height: TokenSpace.space4),
                AttenlumeButton(
                  key: const Key('crash-recovery-carry-on'),
                  label: 'Carry on recording',
                  leading: const Icon(Icons.mic_none_rounded),
                  onPressed: () => Navigator.of(context).pop(carryOn),
                ),
              ],
            ],
          ),
        ),
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        TextButton(
          key: const Key('crash-recovery-ok'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(carryOn != null ? 'Not now' : 'OK'),
        ),
      ],
    );
  }
}

/// Shows [CrashRecoveryDialog] once, when [crashRecoveryReportProvider]
/// finds something on app start. [child] shows straight away.
class CrashRecoveryGate extends ConsumerStatefulWidget {
  const CrashRecoveryGate({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<CrashRecoveryGate> createState() => _CrashRecoveryGateState();
}

class _CrashRecoveryGateState extends ConsumerState<CrashRecoveryGate> {
  bool _shown = false;

  @override
  void initState() {
    super.initState();
    ref.listenManual(crashRecoveryReportProvider, (_, next) {
      final report = next.value;
      if (_shown || report == null || !report.needsPrompt) return;
      _shown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _prompt(report));
    }, fireImmediately: true);
  }

  Future<void> _prompt(RecoveryReport report) async {
    if (!mounted) return;
    final carryOn = await CrashRecoveryDialog.show(context, report);
    if (carryOn == null || !mounted) return;
    await startRecordingFromUi(
      context,
      ref.read(oneActiveCoordinatorProvider),
      carryOn,
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

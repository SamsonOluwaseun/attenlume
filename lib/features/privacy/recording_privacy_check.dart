import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';

import '../../app/theme/tokens.dart';
import '../../data/local_database/app_database.dart';
import '../../data/local_database/builtin_activity_types.dart';
import '../../data/repositories/activity_repository.dart';
import '../../data/repositories/conference_repository.dart';
import '../../domain/models/enums.dart';
import '../../presentation/components/attenlume_button.dart';
import '../activities/consent_check_dialog.dart';
import '../onboarding/welcome_screen.dart';

/// The recording policy reminder (FR-PRI-01, FR-CONF-06): shown before the
/// first recording in a conference whose policy was never acknowledged.
class PolicyReminderDialog extends StatelessWidget {
  const PolicyReminderDialog({super.key});

  /// True when the person acknowledged, false or null otherwise.
  static Future<bool?> show(BuildContext context) => showDialog<bool>(
    context: context,
    builder: (context) => const PolicyReminderDialog(),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      key: const Key('policy-reminder-dialog'),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(TokenRadius.radiusLg)),
      ),
      icon: Icon(
        Icons.info_outline_rounded,
        size: 36,
        color: theme.colorScheme.primary,
      ),
      title: Text(
        'Before you record',
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
              WelcomeScreen.policyNotice,
              style: theme.textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: TokenSpace.space4),
            AttenlumeButton(
              key: const Key('policy-reminder-acknowledge'),
              label: 'I will record only when permitted',
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ],
        ),
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        TextButton(
          key: const Key('policy-reminder-cancel'),
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Not now'),
        ),
      ],
    );
  }
}

/// Why a start was held back by [checkRecordingPrivacy].
enum RecordingPrivacyCheck {
  /// Fine to start.
  proceed,

  /// The person closed a prompt. Nothing was recorded or changed.
  cancelled,

  /// The person said the other person does not know: no audio.
  notRecordingAudio,
}

/// Runs the privacy prompts a recording start needs (FR-PRI-01):
///
/// 1. the conference's recording policy, once, if never acknowledged;
/// 2. for conversations and networking, the awareness check (FR-ACT-07),
///    if it has not been answered (the type may have changed since, or the
///    activity was made elsewhere).
///
/// Answers are saved so each prompt is shown only once.
Future<RecordingPrivacyCheck> checkRecordingPrivacy(
  BuildContext context, {
  required ConferenceRepository conferences,
  required ActivityRepository activities,
  required String activityId,
}) async {
  final activity = await activities.get(activityId);
  if (activity == null) return RecordingPrivacyCheck.proceed;
  final conference = await conferences.get(activity.conferenceId);

  if (conference != null && conference.policyAcknowledgedAt == null) {
    if (!context.mounted) return RecordingPrivacyCheck.cancelled;
    final ok = await PolicyReminderDialog.show(context);
    if (ok != true) return RecordingPrivacyCheck.cancelled;
    await conferences.acknowledgePolicy(conference.id);
  }

  if (activity.recordingPermissionStatus == RecordingPermissionStatus.unknown) {
    final types = await activities.types();
    final type = types.where((t) => t.id == activity.typeId).firstOrNull;
    if (type != null && consentCheckTypeKeys.contains(type.key)) {
      if (!context.mounted) return RecordingPrivacyCheck.cancelled;
      final answer = await ConsentCheckDialog.show(context);
      if (answer == null) return RecordingPrivacyCheck.cancelled;
      await activities.update(
        activity.id,
        ActivitiesCompanion(recordingPermissionStatus: Value(answer)),
      );
      if (answer == RecordingPermissionStatus.notPermitted) {
        return RecordingPrivacyCheck.notRecordingAudio;
      }
    }
  }
  return RecordingPrivacyCheck.proceed;
}

import 'package:flutter/material.dart';

import '../../app/theme/tokens.dart';
import '../../domain/models/enums.dart';
import '../../presentation/components/attenlume_button.dart';

/// Modal dialog showing the consent awareness check for conversations and
/// networking activities (FR-ACT-07, FR-PRI-01, J3).
///
/// Prompts: "Does the other person know you are recording?"
/// Options:
/// - "Yes" -> [RecordingPermissionStatus.participantAware]
/// - "Not recording audio" -> [RecordingPermissionStatus.notPermitted]
/// - Cancel / Dismiss -> null
class ConsentCheckDialog extends StatelessWidget {
  const ConsentCheckDialog({super.key});

  /// Shows the consent check dialog. Returns the selected [RecordingPermissionStatus],
  /// or null if dismissed or cancelled.
  static Future<RecordingPermissionStatus?> show(BuildContext context) {
    return showDialog<RecordingPermissionStatus>(
      context: context,
      barrierDismissible: true,
      builder: (context) => const ConsentCheckDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      key: const Key('consent-check-dialog'),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(TokenRadius.radiusLg)),
      ),
      icon: Icon(
        Icons.privacy_tip_outlined,
        size: 36,
        color: theme.colorScheme.primary,
      ),
      title: Text(
        'Does the other person know you are recording?',
        key: const Key('consent-check-title'),
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
              'Business conversations and networking carry privacy expectations. '
              'If you are not recording audio, you can still take notes, '
              'take photos and record contact details.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: TokenSpace.space4),
            AttenlumeButton(
              key: const Key('consent-check-yes'),
              label: 'Yes',
              leading: const Icon(Icons.check_circle_outline_rounded),
              onPressed: () =>
                  Navigator.of(context)
                      .pop(RecordingPermissionStatus.participantAware),
            ),
            const SizedBox(height: TokenSpace.space2),
            AttenlumeButton(
              key: const Key('consent-check-no-audio'),
              label: 'Not recording audio',
              variant: AttenlumeButtonVariant.secondary,
              leading: const Icon(Icons.mic_off_outlined),
              onPressed: () =>
                  Navigator.of(context)
                      .pop(RecordingPermissionStatus.notPermitted),
            ),
          ],
        ),
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        TextButton(
          key: const Key('consent-check-cancel'),
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

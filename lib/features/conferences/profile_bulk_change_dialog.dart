import 'package:flutter/material.dart';

import '../../app/theme/tokens.dart';
import '../../domain/models/enums.dart';

/// Asks whether a new conference default should also apply to activities
/// not yet recorded (FR-QUAL-03) [P1-09].
///
/// Returns true for "Change them too", false for "New activities only" and
/// null when cancelled. Recorded activities and explicit overrides are
/// never changed either way.
Future<bool?> showProfileBulkChangeDialog(
  BuildContext context, {
  required int unrecordedCount,
  required RecordingProfile profile,
}) => showDialog<bool>(
  context: context,
  barrierDismissible: false,
  builder: (context) {
    final theme = Theme.of(context);
    final those = unrecordedCount == 1
        ? 'One activity that has not been recorded yet uses'
        : '$unrecordedCount activities that have not been recorded yet use';
    return AlertDialog(
      key: const Key('profile-bulk-change-dialog'),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(TokenRadius.radiusLg)),
      ),
      title: Text(
        'Change activities not yet recorded?',
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.bold,
        ),
      ),
      content: Text(
        '$those the conference default. Do you want them to use '
        '${profile.label} too? Recorded activities and activities with '
        'their own setting stay as they are.',
        style: theme.textTheme.bodyMedium,
      ),
      actions: [
        TextButton(
          key: const Key('profile-bulk-cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          key: const Key('profile-bulk-new-only'),
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('New activities only'),
        ),
        FilledButton(
          key: const Key('profile-bulk-include'),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Change them too'),
        ),
      ],
    );
  },
);

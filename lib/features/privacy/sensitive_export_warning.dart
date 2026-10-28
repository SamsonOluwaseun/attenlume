import 'package:flutter/material.dart';

import '../../app/theme/tokens.dart';
import '../../presentation/components/attenlume_button.dart';

/// The warning before anything leaves the device (FR-PRI-05).
///
/// Export (P1-21) and cloud upload (Phase 1.5) call [show] before they
/// start and go ahead only on true. The text never says the export is
/// "compliant" or "safe": the app does not replace the person's own legal
/// obligations and must not claim to.
class SensitiveExportWarning extends StatelessWidget {
  const SensitiveExportWarning({this.isUpload = false, super.key});

  /// Wording for a cloud upload rather than a local export.
  final bool isUpload;

  static const sensitiveKinds = [
    'People who can be identified: voices, faces, names or contact details',
    'Unpublished research',
    'Commercial or confidential business information',
    'Medical or financial information',
  ];

  static const obligationsNote =
      'Attenlume cannot tell what is sensitive and does not replace your own '
      'legal obligations, for example under UK GDPR, or the rules of the '
      'event. Check you are allowed to share this before you do.';

  /// True when the person chose to continue.
  static Future<bool> show(
    BuildContext context, {
    bool isUpload = false,
  }) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => SensitiveExportWarning(isUpload: isUpload),
      ) ??
      false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final verb = isUpload ? 'upload' : 'export';
    return AlertDialog(
      key: const Key('sensitive-export-warning'),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(TokenRadius.radiusLg)),
      ),
      icon: Icon(
        Icons.privacy_tip_outlined,
        size: 36,
        color: theme.colorScheme.primary,
      ),
      title: Text(
        'Check before you $verb',
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.bold,
        ),
        textAlign: TextAlign.center,
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                isUpload
                    ? 'This copy will leave your device. It may include:'
                    : 'This copy can be shared beyond this device. It may '
                          'include:',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: TokenSpace.space2),
              for (final kind in sensitiveKinds)
                Padding(
                  padding: const EdgeInsets.only(bottom: TokenSpace.space1),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('•  '),
                      Expanded(
                        child: Text(kind, style: theme.textTheme.bodyMedium),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: TokenSpace.space3),
              Text(
                obligationsNote,
                key: const Key('sensitive-export-obligations'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: TokenSpace.space4),
              AttenlumeButton(
                key: const Key('sensitive-export-continue'),
                label: isUpload ? 'Continue to upload' : 'Continue to export',
                onPressed: () => Navigator.of(context).pop(true),
              ),
            ],
          ),
        ),
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        TextButton(
          key: const Key('sensitive-export-cancel'),
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

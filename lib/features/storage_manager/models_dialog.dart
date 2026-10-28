import 'package:flutter/material.dart';

import '../../app/theme/tokens.dart';
import '../../presentation/components/attenlume_button.dart';

/// Informational sheet/dialog for managing offline models (FR-STO-06) [P1-20].
class ModelsDialog extends StatelessWidget {
  const ModelsDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.graphic_eq_rounded),
          SizedBox(width: TokenSpace.space2),
          Text('Manage offline models'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(TokenRadius.radiusPill),
            ),
            child: Text(
              'Phase 2 Feature',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
          ),
          const SizedBox(height: TokenSpace.space3),
          Text(
            'Attenlume is strictly offline-first. No cloud account or external AI service is required.\n\nIn Phase 2, optional speech-to-text models (such as Whisper or Vosk) can be downloaded on demand for transcription. Each model will display its exact storage size and RAM requirements before downloading.\n\nCurrently, no offline models are downloaded, and 0 B of local storage is used.',
            style: theme.textTheme.bodyMedium,
          ),
        ],
      ),
      actions: [
        AttenlumeButton(
          key: const Key('close-models-dialog-button'),
          label: 'Close',
          variant: AttenlumeButtonVariant.secondary,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

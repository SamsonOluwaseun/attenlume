import 'package:flutter/material.dart';

import '../../app/theme/tokens.dart';
import '../../presentation/components/attenlume_button.dart';
import '../../shared/utilities/date_formatters.dart';

/// Confirms "Clear safe temporary files" (FR-STO-06, ADR-038, ADR-047)
/// [P1-20]. Pops `true` to clear.
class ClearTempDialog extends StatelessWidget {
  const ClearTempDialog({
    super.key,
    required this.temporaryExportBytes,
    required this.orphanWaveformBytes,
    required this.recoveryBytes,
  });

  final int temporaryExportBytes;
  final int orphanWaveformBytes;
  final int recoveryBytes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget row(String label, int bytes) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(formatStorageBytes(bytes)),
        ],
      ),
    );
    return AlertDialog(
      title: const Text('Clear safe temporary files'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'This removes leftovers that nothing needs. Recordings, photos, '
              'notes and your exports are not touched.',
            ),
            const SizedBox(height: TokenSpace.space3),
            row('Unfinished export copies', temporaryExportBytes),
            row('Waveforms of deleted recordings', orphanWaveformBytes),
            if (recoveryBytes > 0) ...[
              const SizedBox(height: TokenSpace.space3),
              Text(
                'Unfinished recordings (${formatStorageBytes(recoveryBytes)}) '
                'are kept: the app offers to recover them.',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        AttenlumeButton(
          key: const Key('confirm-clear-temp-button'),
          label: 'Clear',
          variant: AttenlumeButtonVariant.secondary,
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    );
  }
}

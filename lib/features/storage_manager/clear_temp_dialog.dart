import 'package:flutter/material.dart';

import '../../app/theme/tokens.dart';
import '../../presentation/components/attenlume_button.dart';
import '../../shared/utilities/date_formatters.dart';

/// Dialog to confirm clearing safe temporary files and optionally kept originals
/// (FR-STO-06, ADR-034, ADR-037) [P1-20].
class ClearTempDialog extends StatefulWidget {
  const ClearTempDialog({
    super.key,
    required this.safeTemporaryBytes,
    required this.keptOriginalsBytes,
    required this.keptOriginalsCount,
    required this.onConfirm,
  });

  final int safeTemporaryBytes;
  final int keptOriginalsBytes;
  final int keptOriginalsCount;
  final Future<void> Function(bool includeKeptOriginals) onConfirm;

  @override
  State<ClearTempDialog> createState() => _ClearTempDialogState();
}

class _ClearTempDialogState extends State<ClearTempDialog> {
  bool _includeKeptOriginals = false;
  bool _isCleaning = false;

  Future<void> _handleConfirm() async {
    setState(() => _isCleaning = true);
    try {
      await widget.onConfirm(_includeKeptOriginals);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _isCleaning = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to clear temporary files: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final totalToFree =
        widget.safeTemporaryBytes +
        (_includeKeptOriginals ? widget.keptOriginalsBytes : 0);

    return AlertDialog(
      title: const Text('Clear safe temporary files'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Safe temporary files include derived waveform summaries and export scratch files. These can be removed at any time without losing original recordings or photos.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: TokenSpace.space3),
            Container(
              padding: const EdgeInsets.all(TokenSpace.space3),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.5,
                ),
                borderRadius: BorderRadius.circular(TokenRadius.radiusMd),
                border: Border.all(color: theme.colorScheme.outlineVariant),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Derived & scratch files:'),
                  Text(
                    formatStorageBytes(widget.safeTemporaryBytes),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            if (widget.keptOriginalsCount > 0) ...[
              const SizedBox(height: TokenSpace.space3),
              CheckboxListTile(
                key: const Key('include-kept-originals-checkbox'),
                contentPadding: EdgeInsets.zero,
                title: Text(
                  'Also remove kept originals (${formatStorageBytes(widget.keptOriginalsBytes)})',
                ),
                subtitle: Text(
                  '${widget.keptOriginalsCount} full recording(s) retained when permanent trims were applied. No current activity references them.',
                ),
                value: _includeKeptOriginals,
                onChanged: _isCleaning
                    ? null
                    : (val) =>
                          setState(() => _includeKeptOriginals = val ?? false),
              ),
            ],
            const SizedBox(height: TokenSpace.space3),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Total space to reclaim:',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  formatStorageBytes(totalToFree),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isCleaning ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        AttenlumeButton(
          key: const Key('confirm-clear-temp-button'),
          label: _isCleaning ? 'Clearing…' : 'Clear temporary files',
          variant: AttenlumeButtonVariant.secondary,
          onPressed: _isCleaning ? null : _handleConfirm,
        ),
      ],
    );
  }
}

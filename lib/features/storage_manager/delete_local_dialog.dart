import 'package:flutter/material.dart';

import '../../app/theme/tokens.dart';
import '../../domain/models/storage_breakdown.dart';
import '../../presentation/components/attenlume_button.dart';
import '../../shared/utilities/date_formatters.dart';

/// Confirmation dialog with preview for deleting local copies of recorded media
/// after verified export (FR-STO-06, FR-STO-07, US-15) [P1-20].
class DeleteLocalDialog extends StatefulWidget {
  const DeleteLocalDialog({
    super.key,
    required this.preview,
    required this.onConfirm,
  });

  final DeleteLocalPreview preview;
  final Future<void> Function(bool keepLightweightIndex) onConfirm;

  @override
  State<DeleteLocalDialog> createState() => _DeleteLocalDialogState();
}

class _DeleteLocalDialogState extends State<DeleteLocalDialog> {
  late bool _keepIndex;
  bool _isDeleting = false;

  @override
  void initState() {
    super.initState();
    _keepIndex = widget.preview.keepLightweightIndex;
  }

  Future<void> _handleConfirm() async {
    setState(() => _isDeleting = true);
    try {
      await widget.onConfirm(_keepIndex);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _isDeleting = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed to delete: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = widget.preview;
    final isActivity = p.activityId != null;
    final targetName = isActivity
        ? '${p.activityTitle ?? 'Activity'} (${p.conferenceName})'
        : p.conferenceName;

    return AlertDialog(
      title: const Text('Delete local copies'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'A verified backup has been confirmed. You can now safely free storage on this device for:\n$targetName',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: TokenSpace.space4),

            // Preview card
            Container(
              padding: const EdgeInsets.all(TokenSpace.space3),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.5,
                ),
                borderRadius: BorderRadius.circular(TokenRadius.radiusMd),
                border: Border.all(color: theme.colorScheme.outlineVariant),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Files to delete:',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: TokenSpace.space2),
                  if (p.audioFilesCount > 0)
                    _itemRow(
                      'Audio recordings',
                      '${p.audioFilesCount} files • ${formatStorageBytes(p.audioBytes)}',
                    ),
                  if (p.keptOriginalsCount > 0)
                    _itemRow(
                      'Kept originals',
                      '${p.keptOriginalsCount} files • ${formatStorageBytes(p.keptOriginalsBytes)}',
                    ),
                  if (p.photoFilesCount > 0)
                    _itemRow(
                      'Photos',
                      '${p.photoFilesCount} files • ${formatStorageBytes(p.photoBytes)}',
                    ),
                  if (p.derivedFilesCount > 0)
                    _itemRow(
                      'Waveforms & derived',
                      '${p.derivedFilesCount} files • ${formatStorageBytes(p.derivedBytes)}',
                    ),
                  if (p.sharedFilesPreservedCount > 0) ...[
                    const Divider(height: TokenSpace.space3),
                    Row(
                      children: [
                        const Icon(
                          Icons.info_outline,
                          size: 16,
                          color: Colors.blueGrey,
                        ),
                        const SizedBox(width: TokenSpace.space2),
                        Expanded(
                          child: Text(
                            '${p.sharedFilesPreservedCount} shared audio file(s) preserved (used by other sessions).',
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const Divider(height: TokenSpace.space3),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Total space to free:',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        formatStorageBytes(p.totalBytesToFree),
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

            const SizedBox(height: TokenSpace.space4),

            // Lightweight archived index checkbox (FR-STO-07)
            CheckboxListTile(
              key: const Key('keep-lightweight-index-checkbox'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Keep lightweight archived index'),
              subtitle: const Text(
                'Retain notes, bookmarks and small thumbnails so you can browse sessions offline without keeping large audio files.',
              ),
              value: _keepIndex,
              onChanged: _isDeleting
                  ? null
                  : (val) => setState(() => _keepIndex = val ?? false),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isDeleting ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        AttenlumeButton(
          key: const Key('confirm-delete-local-button'),
          label: _isDeleting ? 'Deleting…' : 'Delete local copies',
          variant: AttenlumeButtonVariant.danger,
          onPressed: _isDeleting ? null : _handleConfirm,
        ),
      ],
    );
  }

  Widget _itemRow(String label, String detail) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 13)),
          Text(
            detail,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}

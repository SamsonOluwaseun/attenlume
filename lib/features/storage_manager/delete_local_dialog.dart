import 'package:flutter/material.dart';

import '../../app/theme/tokens.dart';
import '../../domain/models/storage_breakdown.dart';
import '../../presentation/components/attenlume_button.dart';
import '../../shared/utilities/date_formatters.dart';

/// Step 1 of "Delete local copies": the preview of what goes and what
/// stays (FR-STO-06, ADR-047) [P1-20]. Continue pops `true`.
class DeleteLocalDialog extends StatelessWidget {
  const DeleteLocalDialog({super.key, required this.preview});

  final DeleteLocalPreview preview;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = preview;
    final what = p.activityId == null
        ? 'the conference "${p.conferenceName}" and its '
              '${p.activityTitles.length} '
              '${p.activityTitles.length == 1 ? 'activity' : 'activities'}'
        : 'the activity "${p.activityTitles.single}"';

    Widget row(String label, int files, int bytes) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(
            '$files ${files == 1 ? 'file' : 'files'}, '
            '${formatStorageBytes(bytes)}',
          ),
        ],
      ),
    );

    return AlertDialog(
      title: const Text('Delete local copies'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'A verified export holds everything below. This removes $what '
              'from this device, with its notes and bookmarks '
              '(${p.bookmarkCount}). Your export is not changed.',
            ),
            const SizedBox(height: TokenSpace.space3),
            Text('Files to delete:', style: theme.textTheme.titleSmall),
            const SizedBox(height: TokenSpace.space1),
            row('Audio recordings', p.audioFiles, p.audioBytes),
            row('Photos and thumbnails', p.photoFiles, p.photoBytes),
            row('Kept originals and waveforms', p.otherFiles, p.otherBytes),
            const Divider(),
            row('Total', p.totalFiles, p.totalBytes),
            if (p.sharedFilesKept > 0) ...[
              const SizedBox(height: TokenSpace.space2),
              Text(
                '${p.sharedFilesKept} '
                '${p.sharedFilesKept == 1 ? 'file stays' : 'files stay'} '
                'because another activity still uses '
                '${p.sharedFilesKept == 1 ? 'it' : 'them'}.',
                key: const Key('delete-local-shared-note'),
              ),
            ],
            if (p.recoveryFilesKept > 0) ...[
              const SizedBox(height: TokenSpace.space2),
              Text(
                '${p.recoveryFilesKept} unfinished or unlinked '
                '${p.recoveryFilesKept == 1 ? 'recording stays' : 'recordings stay'} '
                'for recovery.',
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
          key: const Key('continue-delete-local-button'),
          label: 'Continue',
          variant: AttenlumeButtonVariant.secondary,
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    );
  }
}

/// Step 2: the separate confirmation (FR-STO-06). Delete pops `true`.
class DeleteLocalConfirmDialog extends StatelessWidget {
  const DeleteLocalConfirmDialog({super.key, required this.preview});

  final DeleteLocalPreview preview;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Delete for good?'),
      content: Text(
        'This deletes ${preview.totalFiles} '
        '${preview.totalFiles == 1 ? 'file' : 'files'} '
        '(${formatStorageBytes(preview.totalBytes)}) and '
        '${preview.activityTitles.length == 1 ? 'the activity' : 'the activities'} '
        'from this device. It cannot be undone.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        AttenlumeButton(
          key: const Key('confirm-delete-local-button'),
          label: 'Delete',
          variant: AttenlumeButtonVariant.danger,
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    );
  }
}

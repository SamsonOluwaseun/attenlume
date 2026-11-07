import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../app/theme/tokens.dart';
import '../../domain/services/audio_import_service.dart';
import '../../presentation/components/attenlume_button.dart';

/// Shows the audio import progress dialog with a progress bar, file name,
/// and Cancel button (FR-TRN-03) [P2-13].
Future<AudioImportOutcome> showAudioImportDialog({
  required BuildContext context,
  required AudioImportService importService,
  required String conferenceId,
  XFile? sourceFileOverride,
}) async {
  // Refuse immediately if recording is already active
  if (importService.isRecordingActive?.call() == true) {
    return const AudioImportFailure(AudioImportFailureReason.recordingActive);
  }

  // 1. Pick audio file
  final picked = sourceFileOverride ?? await importService.picker.pickAudio();
  if (picked == null) {
    return const AudioImportCancelled();
  }

  if (!context.mounted) {
    return const AudioImportCancelled();
  }

  final fileName = picked.name.isNotEmpty
      ? picked.name
      : p.basename(picked.path);

  // 2. Show modal progress dialog with Cancel button
  final outcome = await showDialog<AudioImportOutcome>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => AudioImportProgressDialog(
      importService: importService,
      conferenceId: conferenceId,
      sourceFile: picked,
      fileName: fileName,
    ),
  );

  return outcome ?? const AudioImportCancelled();
}

/// Dialog displaying audio import copy progress and a Cancel button.
class AudioImportProgressDialog extends StatefulWidget {
  const AudioImportProgressDialog({
    super.key,
    required this.importService,
    required this.conferenceId,
    required this.sourceFile,
    required this.fileName,
  });

  final AudioImportService importService;
  final String conferenceId;
  final XFile sourceFile;
  final String fileName;

  @override
  State<AudioImportProgressDialog> createState() =>
      _AudioImportProgressDialogState();
}

class _AudioImportProgressDialogState extends State<AudioImportProgressDialog> {
  bool _cancelled = false;
  bool _canPop = false;
  double _fraction = 0.0;
  int _bytesTotal = 0;

  @override
  void initState() {
    super.initState();
    _startImport();
  }

  Future<void> _startImport() async {
    AudioImportOutcome outcome;
    try {
      outcome = await widget.importService.importAudio(
        conferenceId: widget.conferenceId,
        sourceFileOverride: widget.sourceFile,
        onProgress: (p) {
          if (mounted) {
            setState(() {
              _bytesTotal = p.bytesTotal;
              _fraction = p.fraction;
            });
          }
        },
        isCancelled: () => _cancelled,
      );
    } catch (e) {
      outcome = AudioImportFailure(
        AudioImportFailureReason.unreadableFile,
        details: 'The audio file could not be read: $e',
      );
    }

    _canPop = true;
    if (mounted) {
      Navigator.of(context).pop(outcome);
    }
  }

  void _onCancel() {
    if (_cancelled) return;
    setState(() {
      _cancelled = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PopScope(
      canPop: _canPop,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _onCancel();
      },
      child: AlertDialog(
        key: const Key('audio-import-progress-dialog'),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(TokenRadius.radiusLg)),
        ),
        icon: Icon(
          Icons.file_download_outlined,
          size: 36,
          color: theme.colorScheme.primary,
        ),
        title: const Text(
          'Importing audio',
          key: Key('audio-import-dialog-title'),
          textAlign: TextAlign.center,
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.fileName,
                key: const Key('audio-import-progress-filename'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: TokenSpace.space3),
              LinearProgressIndicator(
                key: const Key('audio-import-progress-bar'),
                value: _bytesTotal > 0 ? _fraction : null,
              ),
              const SizedBox(height: TokenSpace.space2),
              Text(
                _cancelled
                    ? 'Cancelling…'
                    : (_bytesTotal > 0
                          ? '${(_fraction * 100).toInt()}%'
                          : 'Preparing…'),
                key: const Key('audio-import-progress-percent'),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: TokenSpace.space4),
              AttenlumeButton(
                key: const Key('audio-import-cancel-button'),
                label: 'Cancel',
                variant: AttenlumeButtonVariant.secondary,
                onPressed: _cancelled ? null : _onCancel,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

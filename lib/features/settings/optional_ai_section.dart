import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/tokens.dart';
import '../ai/language_model_providers.dart';

/// Optional AI section in Settings (P3-10, FR-AI-01).
///
/// Features:
/// - Off by default: model is never downloaded automatically.
/// - Clearly states model name (Gemma 4 E2B, Fast), size (2.65 GB), licence (Apache 2.0).
/// - Shows 'Runs on this device. Nothing you record is sent anywhere.'
/// - Confirmation dialog with size and Wi-Fi note before any network activity.
/// - Preflight free-space check (model size + 1 GB warning margin).
/// - In-flight progress with Cancel.
/// - Verified on-disk confirmation and Delete model action.
///
/// Summaries are off on iOS for now, so iOS never offers the download and
/// never touches model storage.
class OptionalAiSection extends ConsumerWidget {
  const OptionalAiSection({super.key, this.isIos});

  /// Overrides the platform check in tests.
  final bool? isIos;

  static const iosUnavailableMessage =
      'On-device AI summaries are not available on iPhone and iPad yet. '
      'Recording and transcription still work.';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    if (isIos ?? Platform.isIOS) {
      return const Padding(
        padding: EdgeInsets.symmetric(
          horizontal: TokenSpace.space4,
          vertical: TokenSpace.space2,
        ),
        child: Text(
          iosUnavailableMessage,
          key: Key('optional-ai-ios-unavailable'),
        ),
      );
    }
    final controllerAsync = ref.watch(languageModelControllerProvider);

    return controllerAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(TokenSpace.space4),
        // Storage discovery may remain pending (for example while a platform
        // directory lookup is unavailable). It must not keep Settings animating.
        child: Text('Checking installed model…'),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: TokenSpace.space4,
          vertical: TokenSpace.space2,
        ),
        child: Card(
          color: theme.colorScheme.errorContainer,
          child: Padding(
            padding: const EdgeInsets.all(TokenSpace.space4),
            child: Text(
              'Could not load model settings: $e',
              style: TextStyle(color: theme.colorScheme.onErrorContainer),
            ),
          ),
        ),
      ),
      data: (controller) => ListenableBuilder(
        listenable: controller,
        builder: (context, _) => _OptionalAiCard(controller: controller),
      ),
    );
  }
}

class _OptionalAiCard extends StatelessWidget {
  const _OptionalAiCard({required this.controller});

  final LanguageModelController controller;

  Future<void> _confirmDownload(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Download Gemma 4 E2B?'),
        content: const Text(
          'The model download is 2.65 GB. We recommend using Wi-Fi for this download.\n\n'
          'Runs on this device. Nothing you record is sent anywhere.',
        ),
        actions: [
          TextButton(
            key: const Key('optional-ai-confirm-cancel'),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('optional-ai-confirm-download'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Download'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await controller.startDownload();
    }
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete model?'),
        content: const Text(
          'This will remove the 2.65 GB Gemma 4 E2B model from this device. '
          'You can download it again at any time.',
        ),
        actions: [
          TextButton(
            key: const Key('optional-ai-delete-cancel'),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep model'),
          ),
          FilledButton(
            key: const Key('optional-ai-delete-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete model'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await controller.deleteModel();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = controller.state;
    final desc = controller.descriptor;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: TokenSpace.space4,
        vertical: TokenSpace.space2,
      ),
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(TokenRadius.radiusMd),
          side: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.all(TokenSpace.space4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.auto_awesome,
                    color: theme.colorScheme.primary,
                    size: TokenSize.iconMd,
                  ),
                  const SizedBox(width: TokenSpace.space3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          desc.name,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: TokenSpace.space1),
                        Wrap(
                          spacing: TokenSpace.space2,
                          runSpacing: TokenSpace.space1,
                          children: [
                            Text(
                              desc.sizeLabel,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            Text(
                              '·',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            Text(
                              desc.licence,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: TokenSpace.space3),
              Text(
                desc.deviceNotice,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface,
                ),
              ),
              if (state.isError && state.errorMessage != null) ...[
                const SizedBox(height: TokenSpace.space3),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(TokenSpace.space3),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(TokenRadius.radiusSm),
                  ),
                  child: Text(
                    state.errorMessage!,
                    key: const Key('optional-ai-error-message'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onErrorContainer,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: TokenSpace.space4),
              if (state.status == LanguageModelStatus.checkingInstalled) ...[
                const Text('Checking installed model…'),
              ] else if (state.isDownloading) ...[
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LinearProgressIndicator(
                      key: const Key('optional-ai-progress-bar'),
                      value: state.progress.clamp(0.0, 1.0),
                    ),
                    const SizedBox(height: TokenSpace.space2),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          state.progress > 0
                              ? '${(state.progress * 100).toInt()}%'
                              : 'Downloading...',
                          key: const Key('optional-ai-progress-text'),
                          style: theme.textTheme.bodySmall,
                        ),
                        OutlinedButton(
                          key: const Key('optional-ai-cancel-button'),
                          onPressed: () =>
                              unawaited(controller.cancelDownload()),
                          child: const Text('Cancel'),
                        ),
                      ],
                    ),
                  ],
                ),
              ] else if (state.isInstalled) ...[
                Wrap(
                  spacing: TokenSpace.space3,
                  runSpacing: TokenSpace.space2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.check_circle_outline_rounded,
                          color: theme.colorScheme.primary,
                          size: 20,
                        ),
                        const SizedBox(width: TokenSpace.space1),
                        Flexible(
                          child: Text(
                            'Installed and verified',
                            key: const Key('optional-ai-installed-label'),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    OutlinedButton(
                      key: const Key('optional-ai-delete-button'),
                      onPressed: () => unawaited(_confirmDelete(context)),
                      child: const Text('Delete model'),
                    ),
                  ],
                ),
              ] else ...[
                Wrap(
                  spacing: TokenSpace.space3,
                  runSpacing: TokenSpace.space2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    FilledButton.icon(
                      key: const Key('optional-ai-download-button'),
                      onPressed: () => unawaited(_confirmDownload(context)),
                      icon: const Icon(Icons.download_rounded),
                      label: const Text('Download'),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/tokens.dart';
import '../../platform/ai/language_model_descriptor.dart';
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
        builder: (context, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ModelChoice(
              active: controller.descriptor,
              locked: controller.state.isDownloading,
            ),
            _OptionalAiCard(controller: controller),
          ],
        ),
      ),
    );
  }
}

/// Choose between the models in the catalogue (P3-11). The recommendation
/// comes from the device's memory where known; nothing is downloaded here.
class _ModelChoice extends ConsumerWidget {
  const _ModelChoice({required this.active, required this.locked});

  final LanguageModelDescriptor active;
  final bool locked;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final recommended = ref.watch(recommendedLanguageModelProvider).value;
    return RadioGroup<String>(
      groupValue: active.id,
      onChanged: (id) {
        final model = LanguageModelDescriptor.byId(id);
        if (locked || model == null || model.id == active.id) return;
        unawaited(chooseLanguageModel(ref, model));
      },
      child: Column(
        children: [
          for (final model in LanguageModelDescriptor.catalogue)
            RadioListTile<String>(
              key: Key('optional-ai-choice-${model.id}'),
              value: model.id,
              enabled: !locked,
              title: Text('${model.name} · ${model.sizeLabel}'),
              subtitle: Text(
                [
                  model.suitedTo,
                  if (recommended?.id == model.id)
                    'Recommended for this device.',
                ].join(' '),
                style: theme.textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }
}

class _OptionalAiCard extends StatelessWidget {
  const _OptionalAiCard({required this.controller});

  final LanguageModelController controller;

  Future<void> _confirmDownload(BuildContext context) async {
    final desc = controller.descriptor;
    final terms = desc.termsLinks.map((link) => link.$1).join(' and the ');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Download ${desc.name}?'),
        content: Text(
          'The model download is ${desc.sizeLabel}. We recommend using Wi-Fi '
          'for this download.\n\n'
          'Runs on this device. Nothing you record is sent anywhere.'
          '${terms.isEmpty ? '' : '\n\nBy downloading you agree to the $terms.'}',
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
        content: Text(
          'This will remove the ${controller.descriptor.sizeLabel} '
          '${controller.descriptor.name} model from this device. '
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
              // Gemma Terms models: the user sees the terms before download.
              for (final (label, url) in desc.termsLinks)
                Padding(
                  padding: const EdgeInsets.only(top: TokenSpace.space2),
                  child: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: TokenSpace.space2,
                    children: [
                      SelectableText('$label: $url'),
                      TextButton(
                        key: Key('optional-ai-copy-$url'),
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(text: url));
                          if (!context.mounted) return;
                          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                            SnackBar(content: Text('$label link copied.')),
                          );
                        },
                        child: const Text('Copy link'),
                      ),
                    ],
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

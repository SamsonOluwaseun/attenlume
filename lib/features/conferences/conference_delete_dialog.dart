import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/tokens.dart';
import '../../data/repositories/repository_providers.dart';
import '../../domain/models/conference.dart';

/// Confirmation dialog showing what will be removed when deleting a conference
/// (FR-CONF-08, PRODUCT_SPEC 4.3).
class ConferenceDeleteDialog extends ConsumerWidget {
  const ConferenceDeleteDialog({super.key, required this.conference});

  final Conference conference;

  static Future<bool> show(
    BuildContext context, {
    required Conference conference,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => ConferenceDeleteDialog(conference: conference),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(conferenceRepositoryProvider);
    final theme = Theme.of(context);

    return FutureBuilder<ConferenceDeletionSummary>(
      future: repo.deletionSummary(conference.id),
      builder: (context, snapshot) {
        final summary = snapshot.data;
        final audioMb = summary == null
            ? 0.0
            : (summary.audioBytes / (1024 * 1024));
        final photoMb = summary == null
            ? 0.0
            : (summary.photoBytes / (1024 * 1024));

        return AlertDialog(
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(
              Radius.circular(TokenRadius.radiusMd),
            ),
          ),
          title: Text(
            'Delete ${conference.name}?',
            style: theme.textTheme.titleLarge,
          ),
          content: snapshot.connectionState == ConnectionState.waiting
              ? const SizedBox(
                  height: 100,
                  child: Center(child: CircularProgressIndicator()),
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'This will permanently delete this conference and its records from the database:',
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: TokenSpace.space3),
                    _itemRow(
                      context,
                      'Activities',
                      '${summary?.activities ?? 0}',
                    ),
                    _itemRow(
                      context,
                      'Recording segments',
                      '${summary?.segments ?? 0} (${audioMb.toStringAsFixed(1)} MB)',
                    ),
                    _itemRow(
                      context,
                      'Photos',
                      '${summary?.photos ?? 0} (${photoMb.toStringAsFixed(1)} MB)',
                    ),
                    _itemRow(
                      context,
                      'Bookmarks',
                      '${summary?.bookmarks ?? 0}',
                    ),
                    const SizedBox(height: TokenSpace.space3),
                    Text(
                      'This action cannot be undone. Source recordings and photos on disk are not removed automatically.',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: theme.colorScheme.error,
                foregroundColor: theme.colorScheme.onError,
              ),
              onPressed: snapshot.connectionState == ConnectionState.waiting
                  ? null
                  : () async {
                      await repo.delete(conference.id);
                      if (context.mounted) {
                        Navigator.of(context).pop(true);
                      }
                    },
              child: const Text('Delete conference'),
            ),
          ],
        );
      },
    );
  }

  Widget _itemRow(BuildContext context, String label, String value) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: theme.textTheme.bodyMedium),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

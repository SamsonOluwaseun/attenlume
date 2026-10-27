import 'package:flutter/material.dart';

import '../../app/theme/tokens.dart';
import '../../domain/models/media.dart';
import '../../shared/utilities/date_formatters.dart';

/// Trim, cut and split controls under the player, and the list of cuts
/// in effect (FR-REV-04, FR-REV-05) [P1-18].
///
/// Every action works on the playhead. Cuts only hide audio: the files
/// are not changed (NFR-07).
class TrimPanel extends StatelessWidget {
  const TrimPanel({
    super.key,
    required this.positionMs,
    required this.audioEndMs,
    required this.cuts,
    required this.enabled,
    required this.markedStartMs,
    required this.onTrimStart,
    required this.onTrimEnd,
    required this.onMarkCut,
    required this.onCancelMark,
    required this.onSplit,
    required this.onRemoveCut,
    required this.onSeek,
  });

  final int positionMs;
  final int audioEndMs;

  /// Active cut rows, in timeline order.
  final List<CutRange> cuts;

  /// False while the activity is still recording or has no audio.
  final bool enabled;

  /// Where a middle cut starts, once the first end is marked.
  final int? markedStartMs;
  final VoidCallback onTrimStart;
  final VoidCallback onTrimEnd;
  final VoidCallback onMarkCut;
  final VoidCallback onCancelMark;
  final VoidCallback onSplit;
  final ValueChanged<CutRange> onRemoveCut;
  final ValueChanged<int> onSeek;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final inside = positionMs > 0 && positionMs < audioEndMs;
    final marking = markedStartMs != null;
    Widget action(
      String key,
      String label,
      IconData icon,
      VoidCallback? onPressed,
    ) => OutlinedButton.icon(
      key: Key(key),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(TokenSize.tapMin, TokenSize.tapMin),
      ),
      onPressed: enabled ? onPressed : null,
      icon: Icon(icon, size: 20),
      label: Text(label),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Trim and split',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: TokenSpace.space2),
        Wrap(
          spacing: TokenSpace.space2,
          runSpacing: TokenSpace.space2,
          children: [
            action(
              'trim-start',
              'Trim start to here',
              Icons.first_page_rounded,
              positionMs > 0 ? onTrimStart : null,
            ),
            action(
              'trim-end',
              'Trim end from here',
              Icons.last_page_rounded,
              positionMs < audioEndMs ? onTrimEnd : null,
            ),
            action(
              'trim-mark-cut',
              marking ? 'End cut here' : 'Start cut here',
              Icons.content_cut_rounded,
              marking && markedStartMs == positionMs ? null : onMarkCut,
            ),
            if (marking)
              TextButton(
                key: const Key('trim-cancel-cut'),
                style: TextButton.styleFrom(
                  minimumSize: const Size(TokenSize.tapMin, TokenSize.tapMin),
                ),
                onPressed: onCancelMark,
                child: const Text('Cancel cut'),
              ),
            action(
              'trim-split',
              'Split here',
              Icons.call_split_rounded,
              inside && !marking ? onSplit : null,
            ),
          ],
        ),
        if (marking) ...[
          const SizedBox(height: TokenSpace.space2),
          Text(
            'Cut starts at ${formatOffset(markedStartMs!)}. Move the playhead '
            'to where it ends, then tap End cut here.',
            key: const Key('trim-marking-hint'),
            style: muted,
          ),
        ],
        const SizedBox(height: TokenSpace.space3),
        if (cuts.isEmpty)
          Text(
            'No cuts. Cuts only hide audio when you play or export; the '
            'recording itself is not changed.',
            style: muted,
          ),
        for (final c in cuts)
          ListTile(
            key: Key('trim-cut-${c.id}'),
            contentPadding: EdgeInsets.zero,
            minTileHeight: TokenSize.tapMin,
            leading: const Icon(Icons.content_cut_rounded),
            title: Text(
              '${formatOffset(c.startOffsetMs)} to '
              '${formatOffset(c.endOffsetMs)}',
              style: theme.textTheme.bodyLarge?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            subtitle: c.reason == null ? null : Text(c.reason!),
            onTap: () => onSeek(c.startOffsetMs),
            trailing: IconButton(
              key: Key('trim-remove-${c.id}'),
              tooltip: 'Remove cut',
              onPressed: enabled ? () => onRemoveCut(c) : null,
              icon: const Icon(Icons.close_rounded),
            ),
          ),
      ],
    );
  }
}

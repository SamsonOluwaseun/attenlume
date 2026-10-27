import 'package:flutter/material.dart';

import '../../app/theme/tokens.dart';
import '../../domain/models/activity.dart';
import '../../domain/models/enums.dart';
import '../../presentation/components/activity_card.dart';
import '../../presentation/components/status_pill.dart';
import '../../shared/utilities/date_formatters.dart';

/// Modal bottom sheet displaying detailed activity metadata and captured assets (FR-ACT-03).
class ActivityDetailSheet extends StatelessWidget {
  const ActivityDetailSheet({
    super.key,
    required this.summary,
    required this.timezone,
  });

  final ActivitySummary summary;
  final String timezone;

  /// Shows the activity detail sheet.
  static Future<void> show(
    BuildContext context, {
    required ActivitySummary summary,
    required String timezone,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(TokenRadius.radiusLg),
        ),
      ),
      builder: (context) =>
          ActivityDetailSheet(summary: summary, timezone: timezone),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final act = summary.activity;
    final inkMuted = theme.colorScheme.onSurfaceVariant;

    final startTimeUtc = act.actualStart ?? act.plannedStart ?? act.createdAt;
    final timeStr = formatTimeOfDayInTimezone(startTimeUtc, timezone);
    final durationStr = formatDuration(summary.duration);
    final storageStr = formatStorageBytes(
      summary.audioBytes + summary.photoBytes,
    );

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(TokenSpace.space4),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header Row: Type and Status
              Row(
                children: [
                  Icon(
                    activityTypeIconData(summary.type.icon),
                    size: 20,
                    color: inkMuted,
                  ),
                  const SizedBox(width: TokenSpace.space2),
                  Text(
                    summary.type.label,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: inkMuted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  StatusPill(status: summary.statusPillStatus),
                ],
              ),

              const SizedBox(height: TokenSpace.space3),

              // Title
              Text(
                act.title,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: TokenSpace.space2),

              // Privacy Notice
              if (act.isPrivate) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: TokenSpace.space3,
                    vertical: TokenSpace.space2,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainer,
                    borderRadius: const BorderRadius.all(
                      Radius.circular(TokenRadius.radiusSm),
                    ),
                    border: Border.all(color: theme.colorScheme.outlineVariant),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.lock_outline_rounded, size: 16),
                      const SizedBox(width: TokenSpace.space2),
                      Expanded(
                        child: Text(
                          'Private activity · Excluded from exports by default',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: inkMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: TokenSpace.space3),
              ],

              // Metadata Cards
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(TokenSpace.space3),
                  child: Column(
                    children: [
                      _buildMetaRow(
                        theme,
                        icon: Icons.access_time_rounded,
                        label: 'Time',
                        value: '$timeStr ($timezone)',
                      ),
                      const Divider(height: TokenSpace.space3),
                      _buildMetaRow(
                        theme,
                        icon: Icons.timer_outlined,
                        label: 'Recorded duration',
                        value: durationStr,
                      ),
                      const Divider(height: TokenSpace.space3),
                      _buildMetaRow(
                        theme,
                        icon: Icons.sd_storage_outlined,
                        label: 'Storage used',
                        value: storageStr,
                      ),
                      const Divider(height: TokenSpace.space3),
                      _buildMetaRow(
                        theme,
                        icon: Icons.graphic_eq_rounded,
                        label: 'Recording profile',
                        value: summary.effectiveProfile.label,
                      ),
                      if (act.room != null && act.room!.isNotEmpty) ...[
                        const Divider(height: TokenSpace.space3),
                        _buildMetaRow(
                          theme,
                          icon: Icons.meeting_room_outlined,
                          label: 'Room',
                          value: act.room!,
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              const SizedBox(height: TokenSpace.space3),

              // Assets Counts Row
              Row(
                children: [
                  Expanded(
                    child: _buildCountTile(
                      theme,
                      icon: Icons.camera_alt_outlined,
                      count: summary.photoCount,
                      label: 'Photos',
                    ),
                  ),
                  const SizedBox(width: TokenSpace.space2),
                  Expanded(
                    child: _buildCountTile(
                      theme,
                      icon: Icons.bookmark_outline_rounded,
                      count: summary.bookmarkCount,
                      label: 'Bookmarks',
                    ),
                  ),
                  const SizedBox(width: TokenSpace.space2),
                  Expanded(
                    child: _buildCountTile(
                      theme,
                      icon: Icons.audio_file_outlined,
                      count: summary.segmentCount,
                      label: 'Segments',
                    ),
                  ),
                ],
              ),

              if (act.speakerNames.isNotEmpty) ...[
                const SizedBox(height: TokenSpace.space3),
                Text(
                  'Speakers: ${act.speakerNames.join(", ")}',
                  style: theme.textTheme.bodyMedium,
                ),
              ],

              if (act.notesMd != null && act.notesMd!.isNotEmpty) ...[
                const SizedBox(height: TokenSpace.space3),
                Text(
                  'Notes',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: TokenSpace.space1),
                Text(act.notesMd!, style: theme.textTheme.bodyMedium),
              ],

              const SizedBox(height: TokenSpace.space4),

              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMetaRow(
    ThemeData theme, {
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      children: [
        Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: TokenSpace.space2),
        Text(label, style: theme.textTheme.bodyMedium),
        const Spacer(),
        Text(
          value,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildCountTile(
    ThemeData theme, {
    required IconData icon,
    required int count,
    required String label,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(
        vertical: TokenSpace.space3,
        horizontal: TokenSpace.space2,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: const BorderRadius.all(
          Radius.circular(TokenRadius.radiusMd),
        ),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.primary),
          const SizedBox(height: TokenSpace.space1),
          Text(
            '$count',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(label, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

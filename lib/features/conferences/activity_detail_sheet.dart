import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/tokens.dart';
import '../../data/local_database/app_database.dart';
import '../../data/repositories/repository_providers.dart';
import '../../domain/models/activity.dart';
import '../../domain/models/enums.dart';
import '../../domain/services/recording_service.dart';
import '../../domain/services/recording_state.dart';
import '../../presentation/components/activity_card.dart';
import '../../presentation/components/attenlume_button.dart';
import '../../presentation/components/status_pill.dart';
import '../../shared/utilities/date_formatters.dart';
import '../activities/activity_editor_screen.dart';
import '../bookmarks/activity_bookmarks_section.dart';
import '../bookmarks/activity_notes_section.dart';
import '../capture/recording_profile_selector.dart';
import '../capture/recording_providers.dart';
import '../capture/recording_screen.dart';
import '../photos/activity_photos_section.dart';
import '../playback_review/review_screen.dart';

/// Modal bottom sheet displaying detailed activity metadata, contact details,
/// and captured assets (FR-ACT-03, FR-ACT-04, FR-ACT-08).
class ActivityDetailSheet extends ConsumerStatefulWidget {
  const ActivityDetailSheet({
    super.key,
    required this.summary,
    required this.timezone,
  });

  final ActivitySummary summary;
  final String timezone;

  /// Shows the activity detail sheet.
  static Future<dynamic> show(
    BuildContext context, {
    required ActivitySummary summary,
    required String timezone,
  }) {
    return showModalBottomSheet<dynamic>(
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
  ConsumerState<ActivityDetailSheet> createState() =>
      _ActivityDetailSheetState();
}

class _ActivityDetailSheetState extends ConsumerState<ActivityDetailSheet> {
  late ActivitySummary _summary;

  @override
  void initState() {
    super.initState();
    _summary = widget.summary;
  }

  Future<void> _refreshSummary() async {
    final actRepo = ref.read(activityRepositoryProvider);
    final fresh = await actRepo.getSummary(_summary.activity.id);
    if (fresh != null && mounted) {
      setState(() => _summary = fresh);
    }
  }

  Future<void> _handleEdit() async {
    final result = await Navigator.of(context).push<dynamic>(
      MaterialPageRoute(
        builder: (context) =>
            ActivityEditorScreen(activityId: _summary.activity.id),
      ),
    );

    if (!mounted) return;

    if (result is Map && result['deleted'] == true) {
      Navigator.of(context).pop({'deleted': true});
    } else if (result is Activity) {
      await _refreshSummary();
    }
  }

  Future<void> _handleDelete() async {
    final act = _summary.activity;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete "${act.title}"?'),
        content: const Text(
          'This will permanently delete this activity and all its recordings, '
          'photos and bookmarks. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete permanently'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final actRepo = ref.read(activityRepositoryProvider);
    await actRepo.delete(act.id);

    if (mounted) {
      Navigator.of(context).pop({'deleted': true});
    }
  }

  /// Quality selector (FR-UI-08) [P1-09]: live while this activity is
  /// recording, editable before its first segment, hidden once recorded
  /// (the metadata row still names the profile).
  List<Widget> _buildProfileSelector() {
    final act = _summary.activity;
    if (_summary.hasActiveRecording || act.status == ActivityStatus.active) {
      final status = ref.watch(recordingStatusProvider).asData?.value;
      final live =
          status != null &&
          status.activityId == act.id &&
          status.profile != null &&
          (status.state == RecordingState.recording ||
              status.state == RecordingState.paused);
      if (!live) return const [];
      return [
        RecordingProfileSelector(
          selected: status.profile!,
          live: true,
          onChanged: _changeLiveProfile,
        ),
        const SizedBox(height: TokenSpace.space3),
      ];
    }
    if (_summary.segmentCount > 0) return const [];
    return [
      RecordingProfileSelector(
        selected: _summary.effectiveProfile,
        onChanged: _setProfileOverride,
      ),
      const SizedBox(height: TokenSpace.space3),
    ];
  }

  Future<void> _setProfileOverride(RecordingProfile profile) async {
    await ref
        .read(activityRepositoryProvider)
        .update(
          _summary.activity.id,
          ActivitiesCompanion(recordingProfileOverride: Value(profile)),
        );
    await _refreshSummary();
  }

  /// FR-QUAL-04: a new segment with the new profile, or a reason why not.
  Future<void> _changeLiveProfile(RecordingProfile profile) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final result = await ref
        .read(recordingServiceProvider)
        .changeProfile(profile);
    final message = switch (result.outcome) {
      ProfileChangeOutcome.changed =>
        'Recording quality is now ${profile.label}.',
      ProfileChangeOutcome.alreadyInUse ||
      ProfileChangeOutcome.notRecording => null,
      ProfileChangeOutcome.declined ||
      ProfileChangeOutcome.failed => result.reason,
    };
    if (message != null) {
      messenger?.showSnackBar(SnackBar(content: Text(message)));
    }
  }

  String _formatPermissionStatus(RecordingPermissionStatus status) {
    switch (status) {
      case RecordingPermissionStatus.unknown:
        return 'Not specified';
      case RecordingPermissionStatus.permitted:
        return 'Permitted';
      case RecordingPermissionStatus.participantAware:
        return 'Participant aware';
      case RecordingPermissionStatus.notPermitted:
        return 'Not permitted (No audio)';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final act = _summary.activity;
    final inkMuted = theme.colorScheme.onSurfaceVariant;

    final startTimeUtc = act.actualStart ?? act.plannedStart ?? act.createdAt;
    final timeStr = formatTimeOfDayInTimezone(startTimeUtc, widget.timezone);
    final durationStr = formatDuration(_summary.duration);
    final storageStr = formatStorageBytes(
      _summary.audioBytes + _summary.photoBytes,
    );

    final hasContactInfo =
        (act.contactName != null && act.contactName!.isNotEmpty) ||
        (act.contactDetails != null && act.contactDetails!.isNotEmpty) ||
        (act.followUpText != null && act.followUpText!.isNotEmpty);

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
                    activityTypeIconData(_summary.type.icon),
                    size: 20,
                    color: inkMuted,
                  ),
                  const SizedBox(width: TokenSpace.space2),
                  Text(
                    _summary.type.label,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: inkMuted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  StatusPill(status: _summary.statusPillStatus),
                  const SizedBox(width: TokenSpace.space2),
                  IconButton(
                    key: const Key('edit-activity-detail-button'),
                    icon: const Icon(Icons.edit_outlined, size: 20),
                    tooltip: 'Edit activity',
                    onPressed: _handleEdit,
                  ),
                ],
              ),

              const SizedBox(height: TokenSpace.space3),

              // Title
              Text(
                act.title,
                key: const Key('activity-detail-title'),
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

              // Metadata Card
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(TokenSpace.space3),
                  child: Column(
                    children: [
                      _buildMetaRow(
                        theme,
                        icon: Icons.access_time_rounded,
                        label: 'Time',
                        value: '$timeStr (${widget.timezone})',
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
                        value: _summary.effectiveProfile.label,
                      ),
                      const Divider(height: TokenSpace.space3),
                      _buildMetaRow(
                        theme,
                        icon: Icons.rule_rounded,
                        label: 'Permission status',
                        value: _formatPermissionStatus(
                          act.recordingPermissionStatus,
                        ),
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
                      if (act.organisation != null &&
                          act.organisation!.isNotEmpty) ...[
                        const Divider(height: TokenSpace.space3),
                        _buildMetaRow(
                          theme,
                          icon: Icons.business_outlined,
                          label: 'Organisation',
                          value: act.organisation!,
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              const SizedBox(height: TokenSpace.space3),

              ..._buildProfileSelector(),

              // Contact Details Card (FR-ACT-08)
              if (hasContactInfo) ...[
                Card(
                  key: const Key('activity-contact-card'),
                  color: theme.colorScheme.surfaceContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(TokenSpace.space3),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.badge_outlined, size: 18),
                            const SizedBox(width: TokenSpace.space2),
                            Text(
                              'Contact & follow-up',
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        if (act.contactName != null &&
                            act.contactName!.isNotEmpty) ...[
                          const SizedBox(height: TokenSpace.space2),
                          Row(
                            children: [
                              Icon(
                                Icons.person_rounded,
                                size: 16,
                                color: inkMuted,
                              ),
                              const SizedBox(width: TokenSpace.space2),
                              Text(
                                act.contactName!,
                                key: const Key('detail-contact-name'),
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ],
                        if (act.contactDetails != null &&
                            act.contactDetails!.isNotEmpty) ...[
                          const SizedBox(height: TokenSpace.space1),
                          Row(
                            children: [
                              Icon(
                                Icons.contact_mail_outlined,
                                size: 16,
                                color: inkMuted,
                              ),
                              const SizedBox(width: TokenSpace.space2),
                              Expanded(
                                child: Text(
                                  act.contactDetails!,
                                  key: const Key('detail-contact-details'),
                                  style: theme.textTheme.bodyMedium,
                                ),
                              ),
                            ],
                          ),
                        ],
                        if (act.followUpText != null &&
                            act.followUpText!.isNotEmpty) ...[
                          const Divider(height: TokenSpace.space3),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.task_alt_rounded,
                                size: 16,
                                color: theme.colorScheme.primary,
                              ),
                              const SizedBox(width: TokenSpace.space2),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Follow-up action',
                                      style: theme.textTheme.labelSmall
                                          ?.copyWith(color: inkMuted),
                                    ),
                                    Text(
                                      act.followUpText!,
                                      key: const Key('detail-follow-up'),
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w500,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: TokenSpace.space3),
              ],

              // Assets Counts Row
              Row(
                children: [
                  Expanded(
                    child: _buildCountTile(
                      theme,
                      icon: Icons.camera_alt_outlined,
                      count: _summary.photoCount,
                      label: 'Photos',
                    ),
                  ),
                  const SizedBox(width: TokenSpace.space2),
                  Expanded(
                    child: _buildCountTile(
                      theme,
                      icon: Icons.bookmark_outline_rounded,
                      count: _summary.bookmarkCount,
                      label: 'Bookmarks',
                    ),
                  ),
                  const SizedBox(width: TokenSpace.space2),
                  Expanded(
                    child: _buildCountTile(
                      theme,
                      icon: Icons.audio_file_outlined,
                      count: _summary.segmentCount,
                      label: 'Segments',
                    ),
                  ),
                ],
              ),

              if (act.speakerNames.isNotEmpty) ...[
                const SizedBox(height: TokenSpace.space3),
                Text(
                  'Speakers: ${act.speakerNames.join(", ")}',
                  key: const Key('detail-speakers'),
                  style: theme.textTheme.bodyMedium,
                ),
              ],

              if (act.tags.isNotEmpty) ...[
                const SizedBox(height: TokenSpace.space2),
                Wrap(
                  spacing: TokenSpace.space1,
                  children: [
                    for (final tag in act.tags)
                      Chip(
                        label: Text(tag),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
              ],

              const SizedBox(height: TokenSpace.space3),
              ActivityNotesSection(
                activityId: act.id,
                notesMd: act.notesMd,
                onChanged: _refreshSummary,
              ),

              const SizedBox(height: TokenSpace.space3),
              ActivityBookmarksSection(
                // Reloads when bookmarks were added on the recording screen.
                key: ValueKey('bookmarks-${_summary.bookmarkCount}'),
                activityId: act.id,
                timezone: widget.timezone,
                onChanged: _refreshSummary,
              ),

              const SizedBox(height: TokenSpace.space3),
              ActivityPhotosSection(
                activityId: act.id,
                timezone: widget.timezone,
                onChanged: _refreshSummary,
              ),

              const SizedBox(height: TokenSpace.space4),

              if (_summary.segmentCount > 0 &&
                  !_summary.hasActiveRecording) ...[
                AttenlumeButton(
                  key: const Key('activity-detail-review-button'),
                  label: 'Play and review',
                  leading: const Icon(Icons.play_arrow_rounded),
                  onPressed: () => openReview(context, act.id),
                ),
                const SizedBox(height: TokenSpace.space3),
              ],

              AttenlumeButton(
                key: const Key('activity-detail-record-button'),
                label: _summary.hasActiveRecording
                    ? 'Open recording screen'
                    : 'Open recorder',
                leading: const Icon(Icons.mic_rounded),
                onPressed: () {
                  Navigator.of(context)
                      .push(
                        MaterialPageRoute<void>(
                          builder: (context) =>
                              RecordingScreen(activityId: act.id),
                        ),
                      )
                      .then((_) => _refreshSummary());
                },
              ),

              const SizedBox(height: TokenSpace.space3),

              Row(
                children: [
                  Expanded(
                    child: AttenlumeButton(
                      key: const Key('activity-detail-edit-button'),
                      label: 'Edit',
                      variant: AttenlumeButtonVariant.secondary,
                      leading: const Icon(Icons.edit_outlined),
                      onPressed: _handleEdit,
                    ),
                  ),
                  const SizedBox(width: TokenSpace.space3),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Close'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: TokenSpace.space2),
              Center(
                child: TextButton.icon(
                  key: const Key('activity-detail-delete-button'),
                  style: TextButton.styleFrom(
                    foregroundColor: theme.colorScheme.error,
                  ),
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Delete activity'),
                  onPressed: _handleDelete,
                ),
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

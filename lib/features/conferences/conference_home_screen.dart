import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/tokens.dart';
import '../../data/local_database/builtin_activity_types.dart';
import '../../data/repositories/repository_providers.dart';
import '../../domain/models/activity.dart';
import '../../domain/models/conference.dart';
import '../../domain/models/enums.dart';
import '../../presentation/components/activity_card.dart';
import '../../presentation/components/attenlume_button.dart';
import '../../shared/utilities/date_formatters.dart';
import '../activities/consent_check_dialog.dart';
import '../capture/recording_banner.dart';
import '../capture/recording_screen.dart';
import '../export/export_sheet.dart';
import '../storage_manager/storage_manager_screen.dart';
import 'activity_detail_sheet.dart';
import 'conference_delete_dialog.dart';
import 'conference_wizard_screen.dart';
import 'start_activity_sheet.dart';

/// Conference Home landing screen (FR-ACT-01, FR-ACT-02, FR-ACT-03).
///
/// Shows conference details, activity counts, total recorded time, local
/// storage used, dominant "Start activity" action, quick-start type buttons,
/// chronological activity list, and conference goals/outputs.
class ConferenceHomeScreen extends ConsumerStatefulWidget {
  const ConferenceHomeScreen({
    super.key,
    required this.conferenceId,
    this.openRecorder,
  });

  final String conferenceId;

  /// Opens the recording screen for a newly started activity (J2 step 2).
  /// Tests replace it to avoid the capture platform.
  final Future<void> Function(BuildContext context, Activity activity)?
  openRecorder;

  @override
  ConsumerState<ConferenceHomeScreen> createState() =>
      _ConferenceHomeScreenState();
}

class _ConferenceHomeScreenState extends ConsumerState<ConferenceHomeScreen> {
  Conference? _conference;
  List<Goal> _goals = [];
  ConferenceStats _stats = ConferenceStats.zero;
  List<ActivitySummary> _activities = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadConference();
  }

  Future<void> _loadConference() async {
    final confRepo = ref.read(conferenceRepositoryProvider);
    final actRepo = ref.read(activityRepositoryProvider);

    final conf = await confRepo.get(widget.conferenceId);
    if (conf == null) {
      if (mounted) {
        Navigator.of(context).pop();
      }
      return;
    }

    final goals = await confRepo.goalsFor(widget.conferenceId);
    final stats = await confRepo.stats(widget.conferenceId);
    final activities = await actRepo.listSummariesForConference(
      widget.conferenceId,
    );

    if (mounted) {
      setState(() {
        _conference = conf;
        _goals = goals;
        _stats = stats;
        _activities = activities;
        _isLoading = false;
      });
    }
  }

  Future<void> _openEdit() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) =>
            ConferenceWizardScreen(conferenceId: widget.conferenceId),
      ),
    );
    await _loadConference();
  }

  Future<void> _handleDelete() async {
    final conf = _conference;
    if (conf == null) return;

    final deleted = await ConferenceDeleteDialog.show(
      context,
      conference: conf,
    );

    if (deleted && mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  Future<void> _handleArchiveToggle() async {
    final conf = _conference;
    if (conf == null) return;
    final repo = ref.read(conferenceRepositoryProvider);

    if (conf.isArchived) {
      await repo.unarchive(conf.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Conference unarchived')));
    } else {
      await repo.archive(conf.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Conference archived')));
    }
    await _loadConference();
  }

  Future<void> _quickStartActivity(String typeKey) async {
    final actRepo = ref.read(activityRepositoryProvider);
    final type = await actRepo.typeByKey(typeKey);
    if (type == null || !mounted) return;

    RecordingPermissionStatus permissionStatus =
        RecordingPermissionStatus.unknown;
    if (consentCheckTypeKeys.contains(typeKey)) {
      final consent = await ConsentCheckDialog.show(context);
      if (consent == null || !mounted) return;
      permissionStatus = consent;
    }

    try {
      final activity = await actRepo.create(
        conferenceId: widget.conferenceId,
        typeId: type.id,
        recordingPermissionStatus: permissionStatus,
      );
      if (!mounted) return;
      await _loadConference();
      if (!mounted) return;
      await _openRecorder(activity);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not start activity: $e')));
    }
  }

  Future<void> _openStartActivitySheet() async {
    final created = await StartActivitySheet.show(
      context,
      conferenceId: widget.conferenceId,
    );
    if (created != null && mounted) {
      await _loadConference();
      if (!mounted) return;
      await _openRecorder(created);
    }
  }

  /// A started activity goes straight to its recording screen, where the
  /// quality can be chosen before tapping Record (PRODUCT_SPEC J2).
  Future<void> _openRecorder(Activity activity) async {
    final open = widget.openRecorder;
    if (open != null) {
      await open(context, activity);
    } else {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (context) => RecordingScreen(activityId: activity.id),
        ),
      );
    }
    if (mounted) await _loadConference();
  }

  Future<void> _openActivityDetails(ActivitySummary summary) async {
    final res = await ActivityDetailSheet.show(
      context,
      summary: summary,
      timezone: _conference?.timezone ?? 'Europe/London',
    );
    if (!mounted) return;
    await _loadConference();
    if (!mounted) return;
    if (res is Map && res['deleted'] == true) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Activity deleted')));
    }
  }

  Future<void> _openStorageManager() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) =>
            StorageManagerScreen(initialConferenceId: widget.conferenceId),
      ),
    );
    if (!mounted) return;
    await _loadConference();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final attenlume = theme.extension<AttenlumeColors>();

    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final conf = _conference;
    if (conf == null) {
      return const Scaffold(body: Center(child: Text('Conference not found')));
    }

    final dateText = formatDateRange(conf.startDate, conf.endDate);

    return Scaffold(
      appBar: AppBar(
        title: Text(conf.name),
        actions: [
          IconButton(
            key: const Key('export-conference-button'),
            icon: const Icon(Icons.ios_share_rounded),
            tooltip: 'Export conference',
            onPressed: () => ExportSheet.show(context, conferenceId: conf.id),
          ),
          IconButton(
            key: const Key('edit-conference-button'),
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit conference',
            onPressed: _openEdit,
          ),
          PopupMenuButton<String>(
            key: const Key('conference-menu-button'),
            onSelected: (val) {
              if (val == 'storage') {
                _openStorageManager();
              } else if (val == 'archive') {
                _handleArchiveToggle();
              } else if (val == 'delete') {
                _handleDelete();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'storage',
                child: Row(
                  children: [
                    Icon(Icons.storage_outlined, size: 20),
                    SizedBox(width: TokenSpace.space2),
                    Text('Storage manager'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'archive',
                child: Row(
                  children: [
                    Icon(
                      conf.isArchived
                          ? Icons.unarchive_outlined
                          : Icons.archive_outlined,
                      size: 20,
                    ),
                    const SizedBox(width: TokenSpace.space2),
                    Text(
                      conf.isArchived
                          ? 'Unarchive conference'
                          : 'Archive conference',
                    ),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(Icons.delete_outline, size: 20),
                    SizedBox(width: TokenSpace.space2),
                    Text('Delete conference'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: WithRecordingBanner(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(TokenSpace.space4),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (conf.isArchived) ...[
                      Container(
                        padding: const EdgeInsets.all(TokenSpace.space3),
                        margin: const EdgeInsets.only(
                          bottom: TokenSpace.space4,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainer,
                          borderRadius: const BorderRadius.all(
                            Radius.circular(TokenRadius.radiusMd),
                          ),
                          border: Border.all(color: theme.colorScheme.outline),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.archive_outlined),
                            const SizedBox(width: TokenSpace.space3),
                            Expanded(
                              child: Text(
                                'This conference is archived.',
                                style: theme.textTheme.bodyMedium,
                              ),
                            ),
                            TextButton(
                              onPressed: _handleArchiveToggle,
                              child: const Text('Unarchive'),
                            ),
                          ],
                        ),
                      ),
                    ],

                    // Conference Header Card (FR-ACT-01)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(TokenSpace.space4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              conf.name,
                              style: theme.textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: TokenSpace.space2),
                            Row(
                              children: [
                                const Icon(Icons.calendar_today, size: 16),
                                const SizedBox(width: TokenSpace.space2),
                                Text(
                                  dateText,
                                  style: theme.textTheme.bodyMedium,
                                ),
                              ],
                            ),
                            if (conf.venue != null &&
                                conf.venue!.isNotEmpty) ...[
                              const SizedBox(height: TokenSpace.space1),
                              Row(
                                children: [
                                  const Icon(
                                    Icons.location_on_outlined,
                                    size: 16,
                                  ),
                                  const SizedBox(width: TokenSpace.space2),
                                  Expanded(
                                    child: Text(
                                      conf.venue!,
                                      style: theme.textTheme.bodyMedium,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                            const SizedBox(height: TokenSpace.space1),
                            Row(
                              children: [
                                const Icon(Icons.access_time, size: 16),
                                const SizedBox(width: TokenSpace.space2),
                                Text(
                                  conf.timezone,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                            if (conf.description != null &&
                                conf.description!.isNotEmpty) ...[
                              const SizedBox(height: TokenSpace.space3),
                              Text(
                                conf.description!,
                                style: theme.textTheme.bodyMedium,
                              ),
                            ],
                            const SizedBox(height: TokenSpace.space3),
                            Wrap(
                              spacing: TokenSpace.space2,
                              runSpacing: TokenSpace.space2,
                              children: [
                                Chip(
                                  label: Text(
                                    'Profile: ${conf.defaultRecordingProfile.label}',
                                  ),
                                ),
                                if (conf.roleType != null)
                                  Chip(
                                    label: Text(
                                      conf.roleText != null &&
                                              conf.roleText!.isNotEmpty
                                          ? '${conf.roleType!.label}: ${conf.roleText}'
                                          : conf.roleType!.label,
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: TokenSpace.space4),

                    // Conference Stats Card (FR-ACT-01: activity count, recorded time, storage used)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: TokenSpace.space4,
                          horizontal: TokenSpace.space3,
                        ),
                        child: Row(
                          children: [
                            _buildStatColumn(
                              theme,
                              attenlume,
                              label: 'Activities',
                              value: '${_stats.activityCount}',
                            ),
                            Container(
                              width: 1,
                              height: 36,
                              color: theme.colorScheme.outlineVariant,
                            ),
                            _buildStatColumn(
                              theme,
                              attenlume,
                              label: 'Recorded',
                              value: formatDuration(
                                _stats.totalRecordedDuration,
                              ),
                            ),
                            Container(
                              width: 1,
                              height: 36,
                              color: theme.colorScheme.outlineVariant,
                            ),
                            _buildStatColumn(
                              theme,
                              attenlume,
                              label: 'Storage used',
                              value: formatStorageBytes(
                                _stats.totalStorageBytes,
                              ),
                              onTap: _openStorageManager,
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: TokenSpace.space4),

                    // Dominant Start Activity Action (FR-ACT-01)
                    AttenlumeButton(
                      key: const Key('start-activity-button'),
                      variant: AttenlumeButtonVariant.primary,
                      label: 'Start activity',
                      leading: const Icon(Icons.mic_rounded, size: 24),
                      onPressed: _openStartActivitySheet,
                    ),

                    const SizedBox(height: TokenSpace.space4),

                    // Quick-start buttons (FR-ACT-02: Session, Conversation, Exhibit, Reflection)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Quick start',
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: TokenSpace.space2),
                        Wrap(
                          spacing: TokenSpace.space2,
                          runSpacing: TokenSpace.space2,
                          children: [
                            _buildQuickStartButton(
                              label: 'Session',
                              icon: Icons.slideshow_rounded,
                              keyName: 'quick-start-session',
                              typeKey: 'session',
                            ),
                            _buildQuickStartButton(
                              label: 'Conversation',
                              icon: Icons.handshake_rounded,
                              keyName: 'quick-start-conversation',
                              typeKey: 'business_conversation',
                            ),
                            _buildQuickStartButton(
                              label: 'Exhibit',
                              icon: Icons.store_rounded,
                              keyName: 'quick-start-exhibit',
                              typeKey: 'exhibit',
                            ),
                            _buildQuickStartButton(
                              label: 'Reflection',
                              icon: Icons.lightbulb_rounded,
                              keyName: 'quick-start-reflection',
                              typeKey: 'personal_reflection',
                            ),
                          ],
                        ),
                      ],
                    ),

                    const SizedBox(height: TokenSpace.space4),

                    // Chronological Activity List (FR-ACT-03)
                    if (_activities.isEmpty) ...[
                      Container(
                        padding: const EdgeInsets.all(TokenSpace.space6),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainer,
                          borderRadius: const BorderRadius.all(
                            Radius.circular(TokenRadius.radiusMd),
                          ),
                          border: Border.all(
                            color: theme.colorScheme.outlineVariant,
                          ),
                        ),
                        child: Column(
                          children: [
                            Icon(
                              Icons.mic_none_rounded,
                              size: 40,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(height: TokenSpace.space3),
                            Text(
                              'Nothing captured yet. Start your first activity when the session begins.',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ] else ...[
                      Row(
                        children: [
                          Text(
                            'Activities',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: TokenSpace.space2),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primaryContainer,
                              borderRadius: const BorderRadius.all(
                                Radius.circular(TokenRadius.radiusPill),
                              ),
                            ),
                            child: Text(
                              '${_activities.length}',
                              style: theme.textTheme.labelSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: TokenSpace.space3),
                      for (final summary in _activities)
                        Padding(
                          padding: const EdgeInsets.only(
                            bottom: TokenSpace.space3,
                          ),
                          child: ActivityCard.fromSummary(
                            key: Key('activity-card-${summary.activity.id}'),
                            summary: summary,
                            formattedStartTime: formatTimeOfDayInTimezone(
                              summary.activity.actualStart ??
                                  summary.activity.plannedStart ??
                                  summary.activity.createdAt,
                              conf.timezone,
                            ),
                            formattedDuration: formatDuration(summary.duration),
                            onOpen: () => _openActivityDetails(summary),
                          ),
                        ),
                    ],

                    const SizedBox(height: TokenSpace.space4),

                    // Goals Section (FR-CONF-04)
                    if (_goals.isNotEmpty) ...[
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(TokenSpace.space4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Conference goals',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: TokenSpace.space2),
                              for (final goal in _goals)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: TokenSpace.space1,
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      if (goal.priority != null)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2,
                                          ),
                                          margin: const EdgeInsets.only(
                                            right: TokenSpace.space2,
                                            top: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: theme
                                                .colorScheme
                                                .primaryContainer,
                                            borderRadius:
                                                const BorderRadius.all(
                                                  Radius.circular(
                                                    TokenRadius.radiusPill,
                                                  ),
                                                ),
                                          ),
                                          child: Text(
                                            'P${goal.priority}',
                                            style: theme.textTheme.labelSmall
                                                ?.copyWith(
                                                  fontWeight: FontWeight.bold,
                                                  color:
                                                      theme.colorScheme.primary,
                                                ),
                                          ),
                                        )
                                      else
                                        const Padding(
                                          padding: EdgeInsets.only(
                                            right: TokenSpace.space2,
                                            top: 4,
                                          ),
                                          child: Icon(Icons.circle, size: 6),
                                        ),
                                      Expanded(
                                        child: Text(
                                          goal.goalText,
                                          style: theme.textTheme.bodyMedium,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: TokenSpace.space4),
                    ],

                    // Expected Outputs Section (FR-CONF-05)
                    if (conf.requestedOutputs.isNotEmpty) ...[
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(TokenSpace.space4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Expected outputs',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: TokenSpace.space2),
                              Wrap(
                                spacing: TokenSpace.space2,
                                runSpacing: TokenSpace.space2,
                                children: conf.requestedOutputs
                                    .map((out) => Chip(label: Text(out.label)))
                                    .toList(),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatColumn(
    ThemeData theme,
    AttenlumeColors? attenlume, {
    required String label,
    required String value,
    VoidCallback? onTap,
  }) {
    final col = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          value,
          style:
              attenlume?.stat ??
              theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: TokenSpace.space1),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );

    return Expanded(
      child: onTap != null
          ? InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(TokenRadius.radiusSm),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: col,
              ),
            )
          : col,
    );
  }

  Widget _buildQuickStartButton({
    required String label,
    required IconData icon,
    required String keyName,
    required String typeKey,
  }) {
    return OutlinedButton.icon(
      key: Key(keyName),
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, TokenSize.tapMin),
        padding: const EdgeInsets.symmetric(
          horizontal: TokenSpace.space3,
          vertical: TokenSpace.space2,
        ),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(
            Radius.circular(TokenRadius.radiusPill),
          ),
        ),
      ),
      onPressed: () => _quickStartActivity(typeKey),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/tokens.dart';
import '../../data/repositories/repository_providers.dart';
import '../../domain/models/conference.dart';
import '../../domain/models/enums.dart';
import '../../shared/utilities/date_formatters.dart';
import 'conference_delete_dialog.dart';
import 'conference_wizard_screen.dart';

/// Conference Home landing screen (FR-ACT-01, FR-CONF-01, FR-CONF-08).
///
/// Shows conference details, role, goals, outputs, and the dominant
/// "Start activity" action.
class ConferenceHomeScreen extends ConsumerStatefulWidget {
  const ConferenceHomeScreen({super.key, required this.conferenceId});

  final String conferenceId;

  @override
  ConsumerState<ConferenceHomeScreen> createState() =>
      _ConferenceHomeScreenState();
}

class _ConferenceHomeScreenState extends ConsumerState<ConferenceHomeScreen> {
  Conference? _conference;
  List<Goal> _goals = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadConference();
  }

  Future<void> _loadConference() async {
    final repo = ref.read(conferenceRepositoryProvider);
    final conf = await repo.get(widget.conferenceId);
    if (conf == null) {
      if (mounted) {
        Navigator.of(context).pop();
      }
      return;
    }
    final goals = await repo.goalsFor(widget.conferenceId);
    if (mounted) {
      setState(() {
        _conference = conf;
        _goals = goals;
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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
            key: const Key('edit-conference-button'),
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit conference',
            onPressed: _openEdit,
          ),
          PopupMenuButton<String>(
            key: const Key('conference-menu-button'),
            onSelected: (val) {
              if (val == 'archive') {
                _handleArchiveToggle();
              } else if (val == 'delete') {
                _handleDelete();
              }
            },
            itemBuilder: (context) => [
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
      body: SafeArea(
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
                      margin: const EdgeInsets.only(bottom: TokenSpace.space4),
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

                  // Conference Header Card
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
                              Text(dateText, style: theme.textTheme.bodyMedium),
                            ],
                          ),
                          if (conf.venue != null && conf.venue!.isNotEmpty) ...[
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

                  // Dominant Start Activity Action (FR-ACT-01)
                  FilledButton.icon(
                    key: const Key('start-activity-button'),
                    icon: const Icon(Icons.mic, size: 24),
                    label: const Text('Start activity'),
                    onPressed: () {
                      // Activity start flow arrives in P1-02.
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Activity capture will be enabled in P1-02.',
                          ),
                        ),
                      );
                    },
                  ),

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
                                  crossAxisAlignment: CrossAxisAlignment.start,
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
                                          borderRadius: const BorderRadius.all(
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
    );
  }
}

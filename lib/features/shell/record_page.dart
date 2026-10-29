import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/tokens.dart';
import '../../data/repositories/repository_providers.dart';
import '../../domain/models/activity.dart';
import '../../domain/models/conference.dart';
import '../../shared/utilities/date_formatters.dart';
import '../capture/recording_banner.dart';
import '../capture/recording_providers.dart';
import '../capture/recording_screen.dart';
import '../conferences/conference_home_screen.dart';
import '../conferences/conference_wizard_screen.dart';
import '../conferences/start_activity_sheet.dart';

/// The Record destination (FR-UI-11, ADR-052) [P1-39].
///
/// Recordings belong to an activity in a conference, so Record is not a
/// separate recorder. It returns to a recording that is held, otherwise it
/// starts an activity in the most recent conference with the same sheet
/// and recording screen as conference home. With no conference yet, it
/// offers to create one.
class RecordPage extends ConsumerWidget {
  const RecordPage({super.key, this.openRecorder});

  /// Opens the recording screen for a started activity. Tests replace it
  /// to avoid the capture platform.
  final Future<void> Function(BuildContext context, Activity activity)?
  openRecorder;

  Future<void> _record(BuildContext context, Activity activity) async {
    final open = openRecorder;
    if (open != null) return open(context, activity);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RecordingScreen(activityId: activity.id),
      ),
    );
  }

  Future<void> _start(
    BuildContext context,
    WidgetRef ref,
    Conference conference,
  ) async {
    final created = await StartActivitySheet.show(
      context,
      conferenceId: conference.id,
    );
    if (created == null || !context.mounted) return;
    await _record(context, created);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final muted = theme.colorScheme.onSurfaceVariant;
    final status = ref.watch(recordingStatusProvider).asData?.value;
    final heldId = status != null && status.state.holdsActivity
        ? status.activityId
        : null;
    final recent = ref.watch(recentConferencesProvider);

    final List<Widget> content;
    if (heldId != null) {
      content = [
        Text(
          'A recording is in progress.',
          key: const Key('record-held'),
          style: text.titleLarge,
        ),
        const SizedBox(height: TokenSpace.space2),
        Text(
          'Only one recording runs at a time. Open it to pause, stop or add '
          'photos and bookmarks.',
          style: text.bodyLarge?.copyWith(color: muted),
        ),
        const SizedBox(height: TokenSpace.space5),
        FilledButton.icon(
          key: const Key('record-open-recording'),
          onPressed: () => unawaited(
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => RecordingScreen(activityId: heldId),
              ),
            ),
          ),
          icon: const Icon(Icons.mic),
          label: const Text('Open recording'),
        ),
      ];
    } else if (recent.isLoading) {
      content = const [Center(child: CircularProgressIndicator())];
    } else {
      final list = recent.asData?.value ?? const <Conference>[];
      final conference = list.isEmpty ? null : list.first;
      if (conference == null) {
        content = [
          Text(
            'Create a conference first.',
            key: const Key('record-no-conference'),
            style: text.titleLarge,
          ),
          const SizedBox(height: TokenSpace.space2),
          Text(
            'Recordings, photos and bookmarks are kept by conference and '
            'activity.',
            style: text.bodyLarge?.copyWith(color: muted),
          ),
          const SizedBox(height: TokenSpace.space5),
          FilledButton.icon(
            key: const Key('record-new-conference'),
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const ConferenceWizardScreen(),
                ),
              );
              ref.invalidate(recentConferencesProvider);
            },
            icon: const Icon(Icons.add),
            label: const Text('New conference'),
          ),
        ];
      } else {
        final venue = conference.venue?.trim() ?? '';
        content = [
          Text('Record in', style: text.bodyLarge?.copyWith(color: muted)),
          const SizedBox(height: TokenSpace.space1),
          Semantics(
            header: true,
            child: Text(
              conference.name,
              key: const Key('record-conference-name'),
              style: text.headlineSmall,
            ),
          ),
          const SizedBox(height: TokenSpace.space1),
          Text(
            [
              if (venue.isNotEmpty) venue,
              formatDateRange(conference.startDate, conference.endDate),
            ].join(' · '),
            style: text.bodyMedium?.copyWith(color: muted),
          ),
          const SizedBox(height: TokenSpace.space5),
          FilledButton.icon(
            key: const Key('record-start-activity'),
            onPressed: () => unawaited(_start(context, ref, conference)),
            icon: const Icon(Icons.mic),
            label: const Text('Start an activity'),
          ),
          const SizedBox(height: TokenSpace.space3),
          OutlinedButton(
            key: const Key('record-open-conference'),
            onPressed: () => unawaited(
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      ConferenceHomeScreen(conferenceId: conference.id),
                ),
              ),
            ),
            child: const Text('Open conference'),
          ),
          const SizedBox(height: TokenSpace.space4),
          Text(
            'To record in another conference, open it from Conferences.',
            style: text.bodyMedium?.copyWith(color: muted),
          ),
        ];
      }
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Record')),
      body: WithRecordingBanner(
        child: ListView(
          padding: const EdgeInsets.all(TokenSpace.space4),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: content,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

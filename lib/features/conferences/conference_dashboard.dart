import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/tokens.dart';
import '../../data/repositories/repository_providers.dart';
import '../../domain/models/activity.dart';
import '../../domain/models/conference.dart';
import '../../presentation/components/activity_card.dart';
import '../../shared/utilities/date_formatters.dart';
import '../export/export_sheet.dart';
import 'activity_detail_sheet.dart';

/// Shares the list's refresh boundary so returning from Record, import or an
/// editor also refreshes the selected conference's local summaries [P1-39].
final conferenceDashboardProvider = FutureProvider.autoDispose
    .family<List<ActivitySummary>, String>((ref, id) {
      ref.watch(allConferencesFutureProvider);
      return ref
          .watch(activityRepositoryProvider)
          .listSummariesForConference(id);
    });

/// Wide-screen overview built from the same local summaries as conference home.
/// Activities retain their existing details/review flow; no separate media store.
class ConferenceDashboard extends ConsumerStatefulWidget {
  const ConferenceDashboard({
    super.key,
    required this.conference,
    required this.onOpenConference,
    required this.onChanged,
  });

  final Conference conference;
  final VoidCallback onOpenConference;
  final VoidCallback onChanged;

  @override
  ConsumerState<ConferenceDashboard> createState() =>
      _ConferenceDashboardState();
}

class _ConferenceDashboardState extends ConsumerState<ConferenceDashboard> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _openActivity(ActivitySummary summary) async {
    await ActivityDetailSheet.show(
      context,
      summary: summary,
      timezone: widget.conference.timezone,
    );
    if (mounted) widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final conference = widget.conference;
    final data = ref.watch(conferenceDashboardProvider(conference.id));
    return ListView(
      key: const Key('conference-dashboard'),
      padding: const EdgeInsets.fromLTRB(
        TokenSpace.space5,
        TokenSpace.space4,
        TokenSpace.space5,
        TokenSpace.space7 + TokenSpace.space6,
      ),
      children: [
        Semantics(
          header: true,
          child: Text(
            'Conference overview',
            style: theme.textTheme.titleMedium,
          ),
        ),
        const SizedBox(height: TokenSpace.space3),
        Text(conference.name, style: theme.textTheme.headlineSmall),
        const SizedBox(height: TokenSpace.space2),
        Text(
          [
            if (conference.venue?.trim().isNotEmpty ?? false) conference.venue!,
            formatDateRange(conference.startDate, conference.endDate),
          ].join(' \u00b7 '),
          style: theme.textTheme.bodyMedium,
        ),
        if (conference.isArchived) ...[
          const SizedBox(height: TokenSpace.space2),
          const Text('Archived conference'),
        ],
        const SizedBox(height: TokenSpace.space3),
        Wrap(
          spacing: TokenSpace.space2,
          runSpacing: TokenSpace.space2,
          children: [
            OutlinedButton.icon(
              key: const Key('dashboard-open-conference'),
              icon: const Icon(Icons.open_in_new),
              label: const Text('Open conference'),
              onPressed: widget.onOpenConference,
            ),
            OutlinedButton.icon(
              key: const Key('dashboard-export-conference'),
              icon: const Icon(Icons.ios_share_rounded),
              label: const Text('Export conference'),
              onPressed: () =>
                  ExportSheet.show(context, conferenceId: conference.id),
            ),
          ],
        ),
        const SizedBox(height: TokenSpace.space5),
        if (data.isLoading)
          const Center(child: CircularProgressIndicator())
        else if (data.hasError)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Could not load the conference overview.'),
              TextButton.icon(
                key: const Key('dashboard-retry'),
                icon: const Icon(Icons.refresh),
                label: const Text('Try again'),
                onPressed: () =>
                    ref.invalidate(conferenceDashboardProvider(conference.id)),
              ),
            ],
          )
        else
          ..._overview(context, data.value ?? const []),
      ],
    );
  }

  List<Widget> _overview(
    BuildContext context,
    List<ActivitySummary> activities,
  ) {
    final theme = Theme.of(context);
    final photos = activities.fold(0, (n, a) => n + a.photoCount);
    final bookmarks = activities.fold(0, (n, a) => n + a.bookmarkCount);
    final bytes = activities.fold(0, (n, a) => n + a.audioBytes + a.photoBytes);
    final duration = activities.fold(Duration.zero, (n, a) => n + a.duration);
    final query = _query.trim().toLowerCase();
    final shown = activities.where((summary) {
      final activity = summary.activity;
      return [
        activity.title,
        activity.room ?? '',
        ...activity.speakerNames,
      ].any((text) => text.toLowerCase().contains(query));
    }).toList();

    return [
      Semantics(
        header: true,
        child: Text('Conference summary', style: theme.textTheme.titleMedium),
      ),
      const SizedBox(height: TokenSpace.space3),
      LayoutBuilder(
        builder: (context, constraints) {
          // Wrap by available width and text size instead of fixed-height tiles.
          final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
          final columns = constraints.maxWidth >= 560 * scale ? 4 : 2;
          final width =
              (constraints.maxWidth - TokenSpace.space2 * (columns - 1)) /
              columns;
          return Wrap(
            spacing: TokenSpace.space2,
            runSpacing: TokenSpace.space2,
            children: [
              _stat(
                context,
                width,
                Icons.event_note_outlined,
                'Activities',
                '${activities.length}',
              ),
              _stat(
                context,
                width,
                Icons.photo_library_outlined,
                'Photos',
                '$photos',
              ),
              _stat(
                context,
                width,
                Icons.bookmark_border,
                'Bookmarks',
                '$bookmarks',
              ),
              _stat(
                context,
                width,
                Icons.storage_outlined,
                'Storage used',
                formatStorageBytes(bytes),
              ),
            ],
          );
        },
      ),
      const SizedBox(height: TokenSpace.space3),
      Text(
        '${formatDuration(duration)} recorded',
        style: theme.textTheme.bodyMedium,
      ),
      const SizedBox(height: TokenSpace.space5),
      Semantics(
        header: true,
        child: Text('Activities', style: theme.textTheme.titleMedium),
      ),
      const SizedBox(height: TokenSpace.space3),
      if (activities.isNotEmpty) ...[
        TextField(
          key: const Key('dashboard-activity-search'),
          controller: _search,
          decoration: InputDecoration(
            labelText: 'Search activities',
            hintText: 'Title, speaker or room',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _query.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear activity search',
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      _search.clear();
                      setState(() => _query = '');
                    },
                  ),
          ),
          onChanged: (value) => setState(() => _query = value),
        ),
        const SizedBox(height: TokenSpace.space3),
      ],
      if (activities.isEmpty)
        const Text(
          'Nothing captured yet. Open this conference to start your first activity.',
        )
      else if (shown.isEmpty)
        const Text('No activities match your search.')
      else
        for (final summary in shown)
          Padding(
            padding: const EdgeInsets.only(bottom: TokenSpace.space3),
            child: ActivityCard.fromSummary(
              key: Key('dashboard-activity-${summary.activity.id}'),
              summary: summary,
              formattedStartTime: formatTimeOfDayInTimezone(
                summary.activity.actualStart ??
                    summary.activity.plannedStart ??
                    summary.activity.createdAt,
                widget.conference.timezone,
              ),
              formattedDuration: formatDuration(summary.duration),
              onOpen: () => _openActivity(summary),
            ),
          ),
    ];
  }

  Widget _stat(
    BuildContext context,
    double width,
    IconData icon,
    String label,
    String value,
  ) {
    final theme = Theme.of(context);
    return SizedBox(
      key: ValueKey('dashboard-stat-$label'),
      width: width,
      child: Semantics(
        label: '$value $label',
        excludeSemantics: true,
        child: Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(TokenSpace.space3),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(height: TokenSpace.space2),
                Text(value, style: theme.textTheme.titleLarge),
                Text(label, style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

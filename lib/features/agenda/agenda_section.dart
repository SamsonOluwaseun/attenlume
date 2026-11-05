import 'package:flutter/material.dart';

import '../../app/theme/tokens.dart';
import '../../domain/models/planned_session.dart';
import '../../domain/services/agenda_import.dart';
import 'agenda_providers.dart';

/// One planned session: title, time in the conference time zone, speakers
/// and room, and "On now" when it is (ADR-082) [P2-07]. Text wraps, so it
/// holds at 200% text (NFR-09).
class PlannedSessionTile extends StatelessWidget {
  const PlannedSessionTile({
    super.key,
    required this.session,
    required this.timezone,
    required this.nowUtc,
    this.onTap,
    this.selected = false,
    this.actionHint,
  });

  final PlannedSession session;
  final String timezone;
  final DateTime nowUtc;
  final VoidCallback? onTap;
  final bool selected;

  /// What tapping does, read by screen readers ("Start from this session").
  final String? actionHint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onNow = isPlannedSessionOnNow(session, nowUtc);
    final time = formatAgendaTime(
      startUtc: session.startUtc,
      endUtc: session.endUtc,
      allDay: session.allDay,
      timezone: timezone,
    );
    final details = agendaDetailsLine(session.speakerNames, session.room);
    return Semantics(
      hint: actionHint,
      child: ListTile(
        key: Key('planned-session-${session.id}'),
        selected: selected,
        selectedTileColor: theme.colorScheme.primaryContainer,
        selectedColor: theme.colorScheme.onPrimaryContainer,
        minTileHeight: TokenSize.tapMin,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: TokenSpace.space2,
        ),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(TokenRadius.radiusSm)),
        ),
        leading: Icon(
          selected ? Icons.check_circle_rounded : Icons.event_note_outlined,
        ),
        title: Text(session.title),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(onNow ? 'On now · $time' : time),
            if (details.isNotEmpty) Text(details),
          ],
        ),
        onTap: onTap,
      ),
    );
  }
}

/// The agenda on the conference page: the sessions near now, all of them
/// on request, and Import and Clear actions (ADR-082) [P2-07].
class AgendaSection extends StatefulWidget {
  const AgendaSection({
    super.key,
    required this.sessions,
    required this.timezone,
    required this.nowUtc,
    required this.onImport,
    required this.onClear,
    required this.onStart,
    this.onDownloadTemplate,
  });

  /// In time order.
  final List<PlannedSession> sessions;
  final String timezone;
  final DateTime nowUtc;
  final VoidCallback onImport;
  final VoidCallback onClear;
  final ValueChanged<PlannedSession> onStart;

  /// Saves the CSV template (FR-ACT-10) [P2-07a], given the button's
  /// bounds for the iPad share popover. No button when null.
  final ValueChanged<Rect?>? onDownloadTemplate;

  /// Sessions shown before "Show all".
  static const collapsedCount = 5;

  @override
  State<AgendaSection> createState() => _AgendaSectionState();
}

class _AgendaSectionState extends State<AgendaSection> {
  bool _showAll = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sessions = widget.sessions;
    final many = sessions.length > AgendaSection.collapsedCount;
    // Collapsed: the sessions nearest now, shown in time order.
    final shown = _showAll || !many
        ? sessions
        : (orderByNearNow(
              sessions,
              widget.nowUtc,
            ).take(AgendaSection.collapsedCount).toList()
            ..sort((a, b) => a.startUtc.compareTo(b.startUtc)));
    return Card(
      key: const Key('agenda-section'),
      child: Padding(
        padding: const EdgeInsets.all(TokenSpace.space4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(
                sessions.isEmpty
                    ? 'Agenda'
                    : 'Agenda (${sessions.length} planned)',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: TokenSpace.space2),
            if (sessions.isEmpty)
              Text(
                'Import the agenda from a CSV or calendar (ICS) file, then '
                'start sessions with their title, speaker and room filled in. '
                'For a spreadsheet, start from the CSV template.',
                style: theme.textTheme.bodyMedium,
              )
            else ...[
              if (many && !_showAll)
                Text(
                  'Sessions near now:',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              for (final s in shown)
                PlannedSessionTile(
                  session: s,
                  timezone: widget.timezone,
                  nowUtc: widget.nowUtc,
                  actionHint: 'Start an activity from this session',
                  onTap: () => widget.onStart(s),
                ),
              if (many)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton(
                    key: const Key('agenda-show-all-button'),
                    onPressed: () => setState(() => _showAll = !_showAll),
                    child: Text(
                      _showAll
                          ? 'Show sessions near now'
                          : 'Show all ${sessions.length} sessions',
                    ),
                  ),
                ),
            ],
            const SizedBox(height: TokenSpace.space2),
            Wrap(
              spacing: TokenSpace.space2,
              runSpacing: TokenSpace.space2,
              children: [
                OutlinedButton.icon(
                  key: const Key('agenda-import-button'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, TokenSize.tapMin),
                  ),
                  icon: const Icon(Icons.file_open_outlined, size: 18),
                  label: Text(
                    sessions.isEmpty ? 'Import agenda' : 'Import more',
                  ),
                  onPressed: widget.onImport,
                ),
                if (widget.onDownloadTemplate case final onDownload?)
                  Builder(
                    builder: (buttonContext) => TextButton.icon(
                      key: const Key('agenda-template-button'),
                      style: TextButton.styleFrom(
                        minimumSize: const Size(0, TokenSize.tapMin),
                      ),
                      icon: const Icon(Icons.download_outlined, size: 18),
                      label: const Text('Download CSV template'),
                      onPressed: () {
                        final box =
                            buttonContext.findRenderObject() as RenderBox?;
                        onDownload(
                          box == null || !box.hasSize
                              ? null
                              : box.localToGlobal(Offset.zero) & box.size,
                        );
                      },
                    ),
                  ),
                if (sessions.isNotEmpty)
                  TextButton.icon(
                    key: const Key('agenda-clear-button'),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(0, TokenSize.tapMin),
                    ),
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('Clear agenda'),
                    onPressed: widget.onClear,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

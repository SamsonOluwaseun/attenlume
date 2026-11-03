import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/tokens.dart';
import '../../data/repositories/repository_providers.dart';
import '../../domain/models/conference.dart';
import '../../domain/services/agenda_import.dart';
import '../../domain/services/agenda_parser.dart';
import '../../presentation/components/attenlume_button.dart';
import 'agenda_providers.dart';

/// Import a conference agenda from a CSV or ICS file on the device, with a
/// preview before anything is saved (ADR-082) [P2-07]. Pops with the number
/// of sessions saved, or null.
class AgendaImportScreen extends ConsumerStatefulWidget {
  const AgendaImportScreen({super.key, required this.conference});

  final Conference conference;

  static Future<int?> open(BuildContext context, Conference conference) =>
      Navigator.of(context).push<int>(
        MaterialPageRoute(
          builder: (_) => AgendaImportScreen(conference: conference),
        ),
      );

  @override
  ConsumerState<AgendaImportScreen> createState() => _AgendaImportScreenState();
}

/// Rows shown per list in the preview; the rest are counted.
const _previewRows = 100;

class _AgendaImportScreenState extends ConsumerState<AgendaImportScreen> {
  AgendaImportPreview? _preview;
  String? _error;
  bool _busy = false;

  /// A time with no date uses the conference day, but only when the
  /// conference is one day long; otherwise the row is skipped.
  DateTime? get _defaultDate {
    final c = widget.conference;
    final start = c.startDate;
    if (start == null) return null;
    final end = c.endDate;
    if (end != null && !_sameDay(start, end)) return null;
    return start;
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  Future<void> _choose() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final picked = await ref
          .read(agendaFilePickerProvider)
          .pick(maxBytes: maxAgendaFileBytes);
      if (picked == null) {
        if (mounted) setState(() => _busy = false);
        return;
      }
      if (picked.tooLarge) {
        throw const AgendaFormatException(
          'This file is larger than 2 MB, which is too big for an agenda. '
          'Choose a CSV or ICS file with just the sessions.',
        );
      }
      final result = parseAgendaFile(
        fileName: picked.name,
        bytes: picked.bytes,
        timezone: widget.conference.timezone,
        defaultDate: _defaultDate,
      );
      final existing = await ref
          .read(plannedSessionRepositoryProvider)
          .listFor(widget.conference.id);
      if (!mounted) return;
      setState(() {
        _preview = buildAgendaPreview(
          fileName: picked.name,
          result: result,
          existing: existing,
        );
        _busy = false;
      });
    } on AgendaFormatException catch (e) {
      if (mounted) {
        setState(() {
          _preview = null;
          _error = e.message;
          _busy = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _preview = null;
          _error = 'The file could not be read. Check it is a CSV or ICS file.';
          _busy = false;
        });
      }
    }
  }

  Future<void> _save() async {
    final preview = _preview;
    if (preview == null || preview.toSave.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      final saved = await ref
          .read(plannedSessionRepositoryProvider)
          .addAll(
            widget.conference.id,
            preview.toSave,
            source: preview.result.format,
          );
      if (mounted) Navigator.of(context).pop(saved);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'The sessions could not be saved. Nothing was changed.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final preview = _preview;
    return Scaffold(
      appBar: AppBar(title: const Text('Import agenda')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(TokenSpace.space4),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (preview == null) ...[
                    Text(
                      'Add the sessions of ${widget.conference.name} from a '
                      'CSV or calendar (ICS) file on this device. Nothing is '
                      'uploaded.',
                      style: theme.textTheme.bodyLarge,
                    ),
                    const SizedBox(height: TokenSpace.space3),
                    Text(
                      'A CSV file needs a first row that names the columns, '
                      'such as title, speaker, room, start, end and type. '
                      'Times without a time zone use the conference time '
                      'zone (${widget.conference.timezone}).',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: TokenSpace.space4),
                  ],
                  if (_error case final error?) ...[
                    _ErrorBox(message: error),
                    const SizedBox(height: TokenSpace.space4),
                  ],
                  if (preview != null) ...[
                    _PreviewBody(
                      preview: preview,
                      timezone: widget.conference.timezone,
                    ),
                    const SizedBox(height: TokenSpace.space4),
                    AttenlumeButton(
                      key: const Key('agenda-save-button'),
                      label: preview.toSave.isEmpty
                          ? 'Nothing new to save'
                          : preview.toSave.length == 1
                          ? 'Save 1 session'
                          : 'Save ${preview.toSave.length} sessions',
                      leading: const Icon(Icons.check_rounded),
                      onPressed: preview.toSave.isEmpty || _busy ? null : _save,
                    ),
                    const SizedBox(height: TokenSpace.space3),
                  ],
                  AttenlumeButton(
                    key: const Key('agenda-choose-file-button'),
                    label: preview == null
                        ? 'Choose a file'
                        : 'Choose another file',
                    variant: preview == null
                        ? AttenlumeButtonVariant.primary
                        : AttenlumeButtonVariant.secondary,
                    leading: const Icon(Icons.file_open_outlined),
                    onPressed: _busy ? null : _choose,
                  ),
                  if (_busy) ...[
                    const SizedBox(height: TokenSpace.space4),
                    const Center(child: CircularProgressIndicator()),
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

class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(TokenSpace.space3),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainer,
          borderRadius: const BorderRadius.all(
            Radius.circular(TokenRadius.radiusMd),
          ),
          border: Border.all(color: theme.colorScheme.error),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline, color: theme.colorScheme.error),
            const SizedBox(width: TokenSpace.space3),
            Expanded(child: Text(message, style: theme.textTheme.bodyMedium)),
          ],
        ),
      ),
    );
  }
}

class _PreviewBody extends StatelessWidget {
  const _PreviewBody({required this.preview, required this.timezone});

  final AgendaImportPreview preview;
  final String timezone;

  String _count(int n, String one, String many) =>
      n == 1 ? '1 $one' : '$n $many';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final found = _count(preview.found, 'session', 'sessions');
    final skippedText = _count(
      preview.skipped.length,
      'row skipped',
      'rows skipped',
    );
    final dupText = _count(
      preview.duplicates.length,
      'already on the agenda',
      'already on the agenda',
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text('Preview', style: theme.textTheme.titleLarge),
        ),
        const SizedBox(height: TokenSpace.space2),
        Semantics(
          liveRegion: true,
          child: Text(
            '$found found in ${preview.fileName}. '
            '${preview.toSave.length} new, $dupText, $skippedText.',
            key: const Key('agenda-preview-summary'),
            style: theme.textTheme.bodyLarge,
          ),
        ),
        if (preview.warnings.isNotEmpty) ...[
          const SizedBox(height: TokenSpace.space3),
          for (final w in preview.warnings)
            Padding(
              padding: const EdgeInsets.only(bottom: TokenSpace.space2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline, size: 20),
                  const SizedBox(width: TokenSpace.space2),
                  Expanded(child: Text(w, style: theme.textTheme.bodyMedium)),
                ],
              ),
            ),
        ],
        _Section(
          title: 'New sessions (${preview.toSave.length})',
          children: [
            for (final e in preview.toSave.take(_previewRows))
              _EntryRow(entry: e, timezone: timezone),
            if (preview.toSave.length > _previewRows)
              Text('And ${preview.toSave.length - _previewRows} more.'),
          ],
        ),
        if (preview.duplicates.isNotEmpty)
          _Section(
            title:
                'Already on the agenda (${preview.duplicates.length}), '
                'not saved again',
            children: [
              for (final d in preview.duplicates.take(_previewRows))
                _EntryRow(entry: d.entry, timezone: timezone),
              if (preview.duplicates.length > _previewRows)
                Text('And ${preview.duplicates.length - _previewRows} more.'),
            ],
          ),
        if (preview.skipped.isNotEmpty)
          _Section(
            title: 'Skipped (${preview.skipped.length})',
            children: [
              for (final s in preview.skipped.take(_previewRows))
                Padding(
                  padding: const EdgeInsets.only(bottom: TokenSpace.space2),
                  child: Text(
                    'Line ${s.line}: ${s.reason}',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              if (preview.skipped.length > _previewRows)
                Text('And ${preview.skipped.length - _previewRows} more.'),
            ],
          ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: TokenSpace.space5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: TokenSpace.space2),
          ...children,
        ],
      ),
    );
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({required this.entry, required this.timezone});

  final AgendaEntry entry;
  final String timezone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final details = agendaDetailsLine(entry.speakerNames, entry.room);
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.only(bottom: TokenSpace.space3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              entry.title,
              style: theme.textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              formatAgendaTime(
                startUtc: entry.startUtc,
                endUtc: entry.endUtc,
                allDay: entry.allDay,
                timezone: timezone,
              ),
              style: theme.textTheme.bodyMedium,
            ),
            if (details.isNotEmpty)
              Text(
                details,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

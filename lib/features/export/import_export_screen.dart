import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/tokens.dart';
import '../../data/filesystem/export_import_source.dart';
import '../../domain/services/export_import_service.dart';
import '../../presentation/components/attenlume_button.dart';
import 'export_providers.dart';

/// "Import an export" (FR-EXP-11, ADR-049) [P1-23]: pick an export folder
/// or ZIP, see what it holds and whether every file matches its checksum,
/// then import it as a conference. Pops with the new conference's ID when
/// the user chooses "Open conference".
class ImportExportScreen extends ConsumerStatefulWidget {
  const ImportExportScreen({super.key});

  static Future<String?> open(BuildContext context) => Navigator.of(
    context,
  ).push<String>(MaterialPageRoute(builder: (_) => const ImportExportScreen()));

  @override
  ConsumerState<ImportExportScreen> createState() => _ImportExportScreenState();
}

enum _Stage { choose, checking, preview, importing, done }

class _ImportExportScreenState extends ConsumerState<ImportExportScreen> {
  _Stage _stage = _Stage.choose;
  ImportProgress? _progress;
  PreparedImport? _prepared;
  ImportSummary? _summary;
  String? _error;
  bool _asCopy = false;
  bool _cancelled = false;

  late final ExportImportService _service;

  bool get _busy => _stage == _Stage.checking || _stage == _Stage.importing;

  @override
  void initState() {
    super.initState();
    _service = ref.read(exportImportServiceProvider);
  }

  @override
  void dispose() {
    // Staged copies only; the export is never touched.
    final prepared = _prepared;
    if (prepared != null && _summary == null) {
      unawaited(_service.discard(prepared));
    }
    super.dispose();
  }

  Future<void> _pick({required bool zip}) async {
    final picker = ref.read(importPickerProvider);
    final String? path;
    try {
      path = zip ? await picker.pickZip() : await picker.pickFolder();
    } on Object {
      setState(() => _error = 'The file picker could not be opened.');
      return;
    }
    if (path == null || !mounted) return;
    setState(() {
      _stage = _Stage.checking;
      _error = null;
      _progress = null;
      _cancelled = false;
    });
    try {
      final prepared = await _service.prepare(
        path,
        isCancelled: () => _cancelled,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      if (!mounted) {
        unawaited(_service.discard(prepared));
        return;
      }
      setState(() {
        _prepared = prepared;
        _asCopy = false;
        _stage = _Stage.preview;
      });
    } on ExportImportException catch (e) {
      if (mounted) {
        setState(() {
          _stage = _Stage.choose;
          _error = e.message;
        });
      }
    } on Object {
      if (mounted) {
        setState(() {
          _stage = _Stage.choose;
          _error =
              'The export could not be read. Nothing was imported, and the '
              'export was not changed.';
        });
      }
    }
  }

  Future<void> _import() async {
    final prepared = _prepared;
    if (prepared == null) return;
    setState(() {
      _stage = _Stage.importing;
      _progress = null;
    });
    try {
      final summary = await _service.commit(
        prepared,
        asCopy: _asCopy,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      if (!mounted) return;
      setState(() {
        _summary = summary;
        _stage = _Stage.done;
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _stage = _Stage.preview;
        _error = e is ExportImportException
            ? e.message
            : 'The import did not finish. Nothing was added, and the export '
                  'was not changed.';
      });
    }
  }

  Future<void> _startAgain() async {
    final prepared = _prepared;
    _prepared = null;
    if (prepared != null) {
      await _service.discard(prepared);
    }
    if (mounted) {
      setState(() {
        _stage = _Stage.choose;
        _error = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Import an export'),
          automaticallyImplyLeading: !_busy,
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(
                padding: const EdgeInsets.all(TokenSpace.space4),
                children: switch (_stage) {
                  _Stage.choose => _choose(context),
                  _Stage.checking => _working(
                    context,
                    'Copying and checking every file...',
                    cancellable: true,
                  ),
                  _Stage.preview => _preview(context),
                  _Stage.importing => _working(
                    context,
                    'Importing...',
                    cancellable: false,
                  ),
                  _Stage.done => _done(context),
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _errorBox(BuildContext context, String message) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      key: const Key('import-error'),
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(TokenSpace.space4),
        child: Text(message, style: TextStyle(color: scheme.onErrorContainer)),
      ),
    );
  }

  List<Widget> _choose(BuildContext context) {
    final theme = Theme.of(context);
    return [
      Text(
        'Bring an Attenlume export back into the app, for example on a new '
        'device or after deleting local copies. Choose the ZIP file or the '
        'export folder. Every file is checked against checksums.sha256 '
        'before anything is imported, and nothing already in the app is '
        'changed.',
        style: theme.textTheme.bodyLarge,
      ),
      const SizedBox(height: TokenSpace.space4),
      if (_error != null) ...[
        _errorBox(context, _error!),
        const SizedBox(height: TokenSpace.space4),
      ],
      AttenlumeButton(
        key: const Key('import-pick-zip'),
        label: 'Choose a ZIP file',
        leading: const Icon(Icons.folder_zip_outlined),
        onPressed: () => _pick(zip: true),
      ),
      const SizedBox(height: TokenSpace.space3),
      if (!ref.read(importPickerProvider).canPickFolder)
        Text(
          'On a phone or tablet, import the ZIP.',
          key: const Key('import-zip-only'),
          style: theme.textTheme.bodyMedium,
        )
      else
        AttenlumeButton(
          key: const Key('import-pick-folder'),
          label: 'Choose an export folder',
          variant: AttenlumeButtonVariant.secondary,
          leading: const Icon(Icons.folder_open_outlined),
          onPressed: () => _pick(zip: false),
        ),
    ];
  }

  List<Widget> _working(
    BuildContext context,
    String label, {
    required bool cancellable,
  }) {
    final progress = _progress;
    final detail = progress == null || progress.total <= 0
        ? null
        : progress.phase == ImportPhase.checking
        ? '${_size(progress.done)} of ${_size(progress.total)}'
        : '${progress.done} of ${progress.total} files';
    return [
      Text(label, style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: TokenSpace.space3),
      LinearProgressIndicator(
        key: const Key('import-progress'),
        value: progress?.fraction,
      ),
      if (detail != null) ...[
        const SizedBox(height: TokenSpace.space2),
        Text(detail),
      ],
      if (cancellable) ...[
        const SizedBox(height: TokenSpace.space4),
        AttenlumeButton(
          key: const Key('import-cancel-check'),
          label: 'Cancel',
          variant: AttenlumeButtonVariant.secondary,
          onPressed: _cancelled
              ? null
              : () => setState(() => _cancelled = true),
        ),
      ],
    ];
  }

  List<Widget> _preview(BuildContext context) {
    final theme = Theme.of(context);
    final preview = _prepared!.preview;
    final check = preview.check;
    final scheme = theme.colorScheme;
    final contentLabel = switch (preview.content) {
      'audio_only' => 'Audio only',
      'photos_only' => 'Photos only',
      'text_only' => 'Notes and details only',
      'everything' => 'Everything',
      _ => 'Not stated',
    };
    final audioLabel = switch (preview.audioMode) {
      'trimmed' => 'Trimmed copies (imported as the recordings)',
      'original_with_cuts' => 'Originals with cuts.json (cuts restored)',
      'original' => 'Originals',
      _ => 'None',
    };
    return [
      Text(
        preview.conferenceName,
        key: const Key('import-conference-name'),
        style: theme.textTheme.headlineSmall,
      ),
      const SizedBox(height: TokenSpace.space2),
      Text(
        '${preview.activities.length} '
        '${preview.activities.length == 1 ? 'activity' : 'activities'}, '
        '${preview.fileCount} files, ${_size(preview.totalBytes)}. '
        'Contents: $contentLabel. Audio: $audioLabel.',
      ),
      const SizedBox(height: TokenSpace.space4),
      Card(
        key: Key(check.ok ? 'import-check-ok' : 'import-check-failed'),
        color: check.ok ? scheme.secondaryContainer : scheme.errorContainer,
        child: Padding(
          padding: const EdgeInsets.all(TokenSpace.space4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                check.ok
                    ? 'All ${check.checked} files match checksums.sha256.'
                    : 'This export cannot be imported: some files are '
                          'missing or do not match checksums.sha256. It may '
                          'be incomplete or damaged.',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: check.ok
                      ? scheme.onSecondaryContainer
                      : scheme.onErrorContainer,
                ),
              ),
              for (final f in check.mismatched.take(10))
                Text('Does not match: $f'),
              for (final f in check.missing.take(10)) Text('Missing: $f'),
              if (check.unlisted.isNotEmpty)
                Text(
                  '${check.unlisted.length} '
                  '${check.unlisted.length == 1 ? 'file is' : 'files are'} '
                  'not in checksums.sha256 and will be left out.',
                ),
            ],
          ),
        ),
      ),
      if (preview.alreadyExists) ...[
        const SizedBox(height: TokenSpace.space3),
        Text(
          'This conference is already in the app. It will be imported as a '
          'copy with new IDs, named "${preview.conferenceName} (imported '
          'copy)". Nothing already in the app is changed.',
          key: const Key('import-copy-notice'),
        ),
      ] else
        SwitchListTile(
          key: const Key('import-as-copy'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Import as a copy'),
          subtitle: const Text(
            'Gives the conference new IDs, so it can sit beside the '
            'original if that is imported later.',
          ),
          value: _asCopy,
          onChanged: (v) => setState(() => _asCopy = v),
        ),
      for (final w in preview.warnings) ...[
        const SizedBox(height: TokenSpace.space2),
        Text(w),
      ],
      const SizedBox(height: TokenSpace.space4),
      for (final a in preview.activities)
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(a.isPrivate ? '${a.title} (private)' : a.title),
          subtitle: Text(
            [
              a.typeLabel,
              _count(a.segments, 'recording'),
              _count(a.photos, 'photo'),
              _count(a.bookmarks, 'bookmark'),
              if (a.hasNotes) 'notes',
              if (a.cuts > 0) _count(a.cuts, 'cut'),
              _size(a.bytes),
            ].where((s) => s.isNotEmpty).join(' · '),
          ),
        ),
      if (_error != null) ...[
        const SizedBox(height: TokenSpace.space3),
        _errorBox(context, _error!),
      ],
      const SizedBox(height: TokenSpace.space4),
      AttenlumeButton(
        key: const Key('import-start'),
        label: 'Import',
        leading: const Icon(Icons.download_rounded),
        disabled: !preview.canImport,
        disabledReason: preview.canImport ? null : 'The checksum check failed',
        onPressed: _import,
      ),
      const SizedBox(height: TokenSpace.space3),
      AttenlumeButton(
        key: const Key('import-choose-another'),
        label: 'Choose another export',
        variant: AttenlumeButtonVariant.secondary,
        onPressed: _startAgain,
      ),
    ];
  }

  List<Widget> _done(BuildContext context) {
    final theme = Theme.of(context);
    final s = _summary!;
    return [
      Text(
        'Imported "${s.conferenceName}"',
        key: const Key('import-done'),
        style: theme.textTheme.headlineSmall,
      ),
      const SizedBox(height: TokenSpace.space2),
      Text(
        [
          _count(s.activities, 'activity', 'activities'),
          _count(s.segments, 'recording'),
          _count(s.photos, 'photo'),
          _count(s.bookmarks, 'bookmark'),
          if (s.notes > 0) _count(s.notes, 'set of notes', 'sets of notes'),
          if (s.cuts > 0) _count(s.cuts, 'cut range'),
          _size(s.bytes),
        ].where((x) => x.isNotEmpty).join(', '),
        key: const Key('import-summary'),
      ),
      if (s.asCopy) ...[
        const SizedBox(height: TokenSpace.space2),
        const Text(
          'Imported as a copy with new IDs. Nothing already in the app was '
          'changed.',
        ),
      ],
      for (final w in s.warnings) ...[
        const SizedBox(height: TokenSpace.space2),
        Text(w),
      ],
      const SizedBox(height: TokenSpace.space2),
      const Text('The export itself was not changed.'),
      const SizedBox(height: TokenSpace.space4),
      AttenlumeButton(
        key: const Key('import-open-conference'),
        label: 'Open conference',
        onPressed: () => Navigator.of(context).pop(s.conferenceId),
      ),
      const SizedBox(height: TokenSpace.space3),
      AttenlumeButton(
        key: const Key('import-close'),
        label: 'Done',
        variant: AttenlumeButtonVariant.secondary,
        onPressed: () => Navigator.of(context).pop(),
      ),
    ];
  }
}

String _count(int n, String one, [String? many]) =>
    '$n ${n == 1 ? one : (many ?? '${one}s')}';

String _size(int bytes) {
  if (bytes < 1024) return '$bytes bytes';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../app/theme/tokens.dart';
import '../../data/filesystem/export_space.dart';
import '../../data/filesystem/export_writer.dart';
import '../../data/repositories/repository_providers.dart';
import '../../domain/models/activity.dart';
import '../../domain/models/enums.dart';
import '../../domain/services/export_service.dart';
import '../../presentation/components/attenlume_button.dart';
import '../../shared/utilities/date_formatters.dart';
import '../privacy/sensitive_export_warning.dart';
import 'export_providers.dart';

enum _Scope { conference, day, activities }

/// The export sheet (BUILD_GUIDE section 11 screen 7; FR-EXP-01 to 05,
/// FR-EXP-10, ADR-040) [P1-21]: scope, what to include, folder or ZIP,
/// audio option, the private toggle, the size and space check, progress
/// and where the export was saved. On Android and iOS a ZIP is the default
/// and the result offers the system share sheet (ADR-042). Every platform's
/// result offers "Copy AI prompt" (FR-EXP-08, ADR-046).
class ExportSheet extends ConsumerStatefulWidget {
  const ExportSheet({super.key, required this.conferenceId, this.activityId});

  final String conferenceId;

  /// Starts with only this activity selected.
  final String? activityId;

  static Future<void> show(
    BuildContext context, {
    required String conferenceId,
    String? activityId,
  }) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    // Dragging down pops the route directly, past PopScope, so it is off;
    // the Close button and Back still work while no export runs.
    enableDrag: false,
    builder: (_) =>
        ExportSheet(conferenceId: conferenceId, activityId: activityId),
  );

  @override
  ConsumerState<ExportSheet> createState() => _ExportSheetState();
}

class _ExportSheetState extends ConsumerState<ExportSheet> {
  _Scope _scope = _Scope.conference;
  ExportContent _content = ExportContent.everything;
  ExportFormat _format = ExportFormat.folder;
  ExportAudioMode _audioMode = ExportAudioMode.original;
  bool _includePrivate = false;
  List<DateTime> _days = const [];
  DateTime? _day;
  List<Activity> _activities = const [];
  final Set<String> _selected = {};
  String? _destination;

  ExportPreflightReport? _report;
  bool _checking = false;
  int _checkSeq = 0;

  bool _running = false;
  ExportWriteProgress? _progress;
  Completer<void>? _cancel;
  ExportOutcome? _outcome;
  String? _error;

  /// Android and iOS: exports land in private app storage, so the result
  /// offers the share sheet and ZIP is the default (ADR-042).
  late final bool _canShare = ref.read(exportSharerProvider).canShare;

  /// The format of [_outcome], fixed when the export started.
  ExportFormat? _outcomeFormat;
  bool _sharing = false;

  @override
  void dispose() {
    // Safety net: if the sheet goes while an export runs, stop the export
    // cleanly rather than leave it running unseen (FR-EXP-05).
    final cancel = _cancel;
    if (_running && cancel != null && !cancel.isCompleted) cancel.complete();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // One file is what share targets and AI apps accept (ADR-042).
    if (_canShare) _format = ExportFormat.zip;
    if (widget.activityId != null) {
      _scope = _Scope.activities;
      _selected.add(widget.activityId!);
    }
    unawaited(_load());
  }

  Future<void> _load() async {
    final service = ref.read(exportServiceProvider);
    final activities = await ref
        .read(activityRepositoryProvider)
        .listForConference(widget.conferenceId);
    final days = await service.activityDays(widget.conferenceId);
    final destination = await ref
        .read(exportDestinationsProvider)
        .defaultFolder();
    if (!mounted) return;
    setState(() {
      _activities = activities;
      _days = days;
      _day = days.isEmpty ? null : days.first;
      _destination = destination;
    });
    await _check();
  }

  ExportRequest get _request => ExportRequest(
    conferenceId: widget.conferenceId,
    selection: switch (_scope) {
      _Scope.conference => const WholeConference(),
      _Scope.day => OneDay(_day ?? DateTime.now()),
      _Scope.activities => SelectedActivities({..._selected}),
    },
    content: _content,
    format: _format,
    audioMode: _audioMode,
    includePrivate: _includePrivate,
  );

  void _change(VoidCallback update) {
    setState(() {
      update();
      _outcome = null;
      _error = null;
    });
    unawaited(_check());
  }

  Future<void> _check() async {
    final seq = ++_checkSeq;
    setState(() => _checking = true);
    try {
      final service = ref.read(exportServiceProvider);
      final report = _destination == null
          ? ExportPreflightReport(
              plan: await service.plan(_request),
              destination: const ExportPreflight(
                requiredBytes: 0,
                availableBytes: null,
                reserveBytes: 0,
              ),
            )
          : await service.preflight(_request, _destination!);
      if (!mounted || seq != _checkSeq) return;
      setState(() {
        _report = report;
        _checking = false;
      });
    } catch (e) {
      if (!mounted || seq != _checkSeq) return;
      setState(() {
        _report = null;
        _checking = false;
        _error = 'Couldn\'t work out the export size. Try again.';
      });
    }
  }

  Future<void> _chooseFolder() async {
    final folder = await ref.read(exportDestinationsProvider).choose();
    if (folder == null || !mounted) return;
    _change(() => _destination = folder);
  }

  Future<void> _export() async {
    final destination = _destination;
    if (destination == null || _running) return;
    // FR-PRI-05, ADR-041: warn before anything can leave the device.
    final proceed = await SensitiveExportWarning.show(context);
    if (!proceed || !mounted) return;
    final cancel = Completer<void>();
    final format = _format;
    setState(() {
      _running = true;
      _progress = null;
      _outcome = null;
      _error = null;
      _cancel = cancel;
    });
    String? error;
    ExportOutcome? outcome;
    try {
      outcome = await ref
          .read(exportServiceProvider)
          .run(
            _request,
            destinationParent: destination,
            cancel: cancel.future,
            onProgress: (p) {
              if (mounted) setState(() => _progress = p);
            },
          );
    } on ExportCancelledException {
      error = 'Export cancelled. Nothing was left behind.';
    } on InsufficientSpaceException catch (e) {
      error =
          'Not enough space. Free ${formatStorageBytes(e.preflight.shortfallBytes)} '
          'or choose another folder.';
    } on ExportOutOfSpaceException {
      error =
          'The disk filled up during the export. The partial copy was '
          'removed and your recordings are safe.';
    } on ExportException catch (e) {
      error = e.message;
    } catch (_) {
      error =
          'The export stopped. The partial copy was removed and your '
          'recordings are safe. Try again.';
    }
    if (!mounted) return;
    setState(() {
      _running = false;
      _cancel = null;
      _outcome = outcome;
      _outcomeFormat = outcome == null ? null : format;
      _error = error;
    });
    if (outcome == null) unawaited(_check());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final media = MediaQuery.of(context);
    // While an export runs, Back and a tap outside do nothing: the sheet
    // holds the progress, Cancel and the result.
    return PopScope(
      canPop: !_running,
      child: Padding(
        padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: media.size.height * 0.92),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(TokenSpace.space4),
            child: Column(
              key: const Key('export-sheet'),
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text('Export', style: theme.textTheme.titleLarge),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      icon: const Icon(Icons.close_rounded),
                      onPressed: _running
                          ? null
                          : () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                if (_outcome != null)
                  ..._result(theme, _outcome!)
                else ...[
                  ..._options(theme),
                  const SizedBox(height: TokenSpace.space4),
                  ..._footer(theme),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _label(ThemeData theme, String text) => Padding(
    padding: const EdgeInsets.only(
      top: TokenSpace.space4,
      bottom: TokenSpace.space2,
    ),
    child: Text(text, style: theme.textTheme.titleSmall),
  );

  Widget _chips<T>(
    List<(T, String)> options,
    T value,
    ValueChanged<T> onChanged,
  ) => Wrap(
    spacing: TokenSpace.space2,
    runSpacing: TokenSpace.space2,
    children: [
      for (final (option, label) in options)
        ChoiceChip(
          key: Key('export-option-$label'),
          label: Text(label),
          selected: option == value,
          onSelected: _running
              ? null
              : (_) {
                  if (option != value) _change(() => onChanged(option));
                },
        ),
    ],
  );

  List<Widget> _options(ThemeData theme) {
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return [
      _label(theme, 'What to export'),
      _chips<_Scope>(
        [
          (_Scope.conference, 'Whole conference'),
          if (_days.isNotEmpty) (_Scope.day, 'One day'),
          (_Scope.activities, 'Choose activities'),
        ],
        _scope,
        (v) => _scope = v,
      ),
      if (_scope == _Scope.day && _days.isNotEmpty) ...[
        const SizedBox(height: TokenSpace.space2),
        _chips<DateTime>(
          [for (final d in _days) (d, formatDateFull(d))],
          _day ?? _days.first,
          (v) => _day = v,
        ),
      ],
      if (_scope == _Scope.activities)
        for (final a in _activities)
          CheckboxListTile(
            key: Key('export-activity-${a.id}'),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _selected.contains(a.id),
            title: Text(a.title),
            subtitle: a.isPrivate ? const Text('Private') : null,
            onChanged: _running
                ? null
                : (v) => _change(
                    () => v == true
                        ? _selected.add(a.id)
                        : _selected.remove(a.id),
                  ),
          ),
      _label(theme, 'Include'),
      _chips<ExportContent>(
        const [
          (ExportContent.everything, 'Everything'),
          (ExportContent.audioOnly, 'Audio only'),
          (ExportContent.photosOnly, 'Photos only'),
          (ExportContent.textOnly, 'Notes and details only'),
        ],
        _content,
        (v) => _content = v,
      ),
      if (_content.audio) ...[
        _label(theme, 'Audio'),
        _chips<ExportAudioMode>(
          const [
            (ExportAudioMode.original, 'Original recordings'),
            (ExportAudioMode.trimmed, 'Trimmed copies'),
            (ExportAudioMode.originalWithCuts, 'Originals and cut list'),
          ],
          _audioMode,
          (v) => _audioMode = v,
        ),
        const SizedBox(height: TokenSpace.space1),
        Text(switch (_audioMode) {
          ExportAudioMode.trimmed =>
            'Copies with your cuts removed. Your recordings stay as they are.',
          ExportAudioMode.originalWithCuts =>
            'Full recordings plus cuts.json, which lists the parts to skip.',
          _ => 'Full recordings, exactly as captured.',
        }, style: muted),
      ],
      _label(theme, 'Format'),
      _chips<ExportFormat>(
        const [(ExportFormat.folder, 'Folder'), (ExportFormat.zip, 'ZIP')],
        _format,
        (v) => _format = v,
      ),
      const SizedBox(height: TokenSpace.space1),
      Text(key: const Key('export-format-hint'), switch ((_format, _canShare)) {
        (ExportFormat.zip, true) =>
          'One file you can share to Files, Google Drive or an AI app. '
              'Audio and photos are already compressed, so the ZIP is '
              'about the same size.',
        (ExportFormat.zip, false) =>
          'One file to share. Audio and photos are already compressed, '
              'so the ZIP is about the same size.',
        (_, true) =>
          "A folder stays in the app's storage and can't be shared from "
              'here. Choose ZIP to send the export to another app.',
        _ => 'A folder you can open straight away.',
      }, style: muted),
      const SizedBox(height: TokenSpace.space2),
      SwitchListTile(
        key: const Key('export-include-private'),
        contentPadding: EdgeInsets.zero,
        title: const Text('Include private items'),
        subtitle: const Text(
          'Private activities, private thoughts and reflections. Check '
          'before sharing anything about other people.',
        ),
        value: _includePrivate,
        onChanged: _running ? null : (v) => _change(() => _includePrivate = v),
      ),
      _label(theme, 'Save to'),
      // Wraps at large text instead of overflowing (NFR-09).
      Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            _destination ?? 'Choose a folder for the export.',
            key: const Key('export-destination'),
            style: theme.textTheme.bodyMedium,
          ),
          if (ref.read(exportDestinationsProvider).canChoose)
            TextButton.icon(
              key: const Key('export-choose-folder'),
              onPressed: _running ? null : _chooseFolder,
              icon: const Icon(Icons.folder_open_rounded),
              label: Text(_destination == null ? 'Choose folder' : 'Change'),
            ),
        ],
      ),
    ];
  }

  String _summary(ExportPreflightReport report) {
    final plan = report.plan;
    final activities = plan.activityCount == 1
        ? '1 activity'
        : '${plan.activityCount} activities';
    final parts = <String>[
      'About ${formatStorageBytes(plan.destinationBytes)}, $activities, '
          '${plan.entries.length + 1} files.',
      if (plan.privateActivitiesExcluded > 0)
        '${plan.privateActivitiesExcluded} private '
            '${plan.privateActivitiesExcluded == 1 ? 'activity' : 'activities'} '
            'left out.',
      if (plan.segmentsSkipped > 0)
        '${plan.segmentsSkipped} damaged or unfinished '
            '${plan.segmentsSkipped == 1 ? 'recording' : 'recordings'} '
            'left out.',
    ];
    final free = report.destination.availableBytes;
    if (_destination != null && free != null) {
      parts.add('${formatStorageBytes(free)} free there.');
    }
    return parts.join(' ');
  }

  List<Widget> _footer(ThemeData theme) {
    final report = _report;
    final danger = theme.colorScheme.error;
    final nothing = report != null && report.plan.activityCount == 0;
    final blocked =
        _destination == null ||
        report == null ||
        _checking ||
        report.insufficient ||
        nothing;
    return [
      if (_checking && report == null)
        const LinearProgressIndicator()
      else if (report != null) ...[
        Text(
          _summary(report),
          key: const Key('export-preflight'),
          style: theme.textTheme.bodyMedium,
        ),
        if (nothing)
          Padding(
            padding: const EdgeInsets.only(top: TokenSpace.space2),
            child: Text(
              report.plan.privateActivitiesExcluded > 0
                  ? 'Only private activities are chosen. Turn on "Include '
                        'private items" to export them.'
                  : 'Nothing to export for this choice.',
              style: theme.textTheme.bodyMedium,
            ),
          )
        else if (_destination != null && report.insufficient)
          Padding(
            padding: const EdgeInsets.only(top: TokenSpace.space2),
            child: Row(
              children: [
                Icon(Icons.error_outline_rounded, color: danger),
                const SizedBox(width: TokenSpace.space2),
                Expanded(
                  child: Text(
                    'Not enough space. Free '
                    '${formatStorageBytes(report.destination.shortfallBytes + (report.temp?.shortfallBytes ?? 0))} '
                    'or choose another folder.',
                    key: const Key('export-insufficient'),
                    style: theme.textTheme.bodyMedium?.copyWith(color: danger),
                  ),
                ),
              ],
            ),
          )
        else if (_destination != null && report.unknown)
          Padding(
            padding: const EdgeInsets.only(top: TokenSpace.space2),
            child: Text(
              'Couldn\'t check the free space here. If the disk fills, the '
              'export stops safely and your recordings are untouched.',
              style: theme.textTheme.bodySmall,
            ),
          ),
      ],
      if (_error != null)
        Padding(
          padding: const EdgeInsets.only(top: TokenSpace.space2),
          child: Text(
            _error!,
            key: const Key('export-error'),
            style: theme.textTheme.bodyMedium?.copyWith(color: danger),
          ),
        ),
      const SizedBox(height: TokenSpace.space4),
      if (_running) ...[
        LinearProgressIndicator(
          key: const Key('export-progress'),
          value: _progress?.fraction,
        ),
        const SizedBox(height: TokenSpace.space2),
        Text(
          _progress == null
              ? 'Preparing…'
              : 'Exporting ${_progress!.filesDone} of ${_progress!.filesTotal} files…',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: TokenSpace.space3),
        AttenlumeButton(
          key: const Key('export-cancel'),
          label: 'Cancel',
          variant: AttenlumeButtonVariant.secondary,
          onPressed: _cancel == null || _cancel!.isCompleted
              ? null
              : () => _cancel!.complete(),
        ),
      ] else
        AttenlumeButton(
          key: const Key('export-start'),
          label: 'Export',
          leading: const Icon(Icons.ios_share_rounded),
          disabled: blocked,
          disabledReason: _destination == null ? 'Choose a folder first' : null,
          onPressed: _export,
        ),
    ];
  }

  List<Widget> _result(ThemeData theme, ExportOutcome outcome) => [
    const SizedBox(height: TokenSpace.space2),
    Row(
      children: [
        const Icon(Icons.check_circle_rounded),
        const SizedBox(width: TokenSpace.space2),
        Expanded(
          child: Text('Export saved', style: theme.textTheme.titleMedium),
        ),
      ],
    ),
    const SizedBox(height: TokenSpace.space2),
    Text(
      '${outcome.fileCount} files, ${formatStorageBytes(outcome.bytes)}. '
      '${outcome.verification == VerificationLevel.checksum ? 'Every copy was checked against checksums.sha256.' : 'Checksums are in checksums.sha256 inside the ZIP.'}',
      style: theme.textTheme.bodyMedium,
    ),
    if (_canShare) ..._share(theme, outcome),
    const SizedBox(height: TokenSpace.space3),
    SelectableText(
      outcome.outputPath,
      key: const Key('export-result-path'),
      style: theme.textTheme.bodyMedium,
    ),
    const SizedBox(height: TokenSpace.space3),
    AttenlumeButton(
      key: const Key('export-copy-path'),
      label: 'Copy location',
      variant: AttenlumeButtonVariant.secondary,
      leading: const Icon(Icons.copy_rounded),
      onPressed: () {
        Clipboard.setData(ClipboardData(text: outcome.outputPath));
        ScaffoldMessenger.maybeOf(context)
            ?.showSnackBar(const SnackBar(content: Text('Location copied')));
      },
    ),
    if (outcome.analysisPrompt case final prompt?) ...[
      const SizedBox(height: TokenSpace.space3),
      AttenlumeButton(
        key: const Key('export-copy-prompt'),
        label: 'Copy AI prompt',
        variant: AttenlumeButtonVariant.secondary,
        leading: const Icon(Icons.auto_awesome_outlined),
        onPressed: () => _copyPrompt(prompt),
      ),
      const SizedBox(height: TokenSpace.space1),
      Text(
        'The prompt from analysis_prompt.md, filled in with your role, goals '
        'and outputs. Paste it into an AI tool with the exported files.',
        key: const Key('export-copy-prompt-hint'),
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    ],
    const SizedBox(height: TokenSpace.space3),
    AttenlumeButton(
      key: const Key('export-done'),
      label: 'Done',
      variant: _canShare && _outcomeFormat == ExportFormat.zip
          ? AttenlumeButtonVariant.secondary
          : AttenlumeButtonVariant.primary,
      onPressed: () => Navigator.of(context).pop(),
    ),
  ];

  /// FR-EXP-08: the filled-in analysis prompt to the clipboard.
  Future<void> _copyPrompt(String prompt) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await Clipboard.setData(ClipboardData(text: prompt));
      messenger?.showSnackBar(
        const SnackBar(
          content: Text(
            'AI prompt copied. Paste it into your AI tool with the export '
            'files.',
          ),
        ),
      );
    } catch (_) {
      messenger?.showSnackBar(
        const SnackBar(
          content: Text(
            "Couldn't copy the prompt. Open analysis_prompt.md in the "
            'export instead.',
          ),
        ),
      );
    }
  }

  /// Android and iOS (ADR-042): the ZIP goes to the system share sheet. The
  /// file stays in the app's exports folder; nothing deletes it.
  List<Widget> _share(ThemeData theme, ExportOutcome outcome) {
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    if (_outcomeFormat != ExportFormat.zip) {
      return [
        const SizedBox(height: TokenSpace.space3),
        Text(
          "A folder can't be shared from here. To send the export to "
          'another app, export again as a ZIP.',
          key: const Key('export-share-zip-hint'),
          style: theme.textTheme.bodyMedium,
        ),
      ];
    }
    return [
      const SizedBox(height: TokenSpace.space4),
      Builder(
        builder: (buttonContext) => AttenlumeButton(
          key: const Key('export-share'),
          label: 'Share',
          leading: const Icon(Icons.share_rounded),
          disabled: _sharing,
          onPressed: () => _shareExport(buttonContext, outcome),
        ),
      ),
      const SizedBox(height: TokenSpace.space1),
      Text(
        '${p.basename(outcome.outputPath)}, ${formatStorageBytes(outcome.bytes)}. '
        'A copy stays in the app after sharing.',
        key: const Key('export-share-size'),
        style: muted,
      ),
    ];
  }

  Future<void> _shareExport(
    BuildContext buttonContext,
    ExportOutcome outcome,
  ) async {
    if (_sharing) return;
    // iPad shows the share sheet as a popover anchored to the button.
    final box = buttonContext.findRenderObject() as RenderBox?;
    final origin = box == null || !box.hasSize
        ? null
        : box.localToGlobal(Offset.zero) & box.size;
    setState(() => _sharing = true);
    try {
      await ref
          .read(exportSharerProvider)
          .shareFile(
            outcome.outputPath,
            subject: p.basenameWithoutExtension(outcome.outputPath),
            origin: origin,
          );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(
            content: Text("Couldn't open the share options. Try again."),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }
}

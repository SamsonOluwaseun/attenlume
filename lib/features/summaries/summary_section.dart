import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/tokens.dart';
import '../../domain/ai/session_material.dart';
import '../../domain/ai/session_summary.dart';
import '../../domain/ai/summary_prompt.dart';
import '../../domain/ai/text_generation_engine.dart';
import '../../domain/models/media.dart';
import '../../domain/services/session_summariser.dart';
import 'summary_providers.dart';

/// The Summary tab of the session review (P3-02, ADR-076): a summary, key
/// points, follow-ups and questions built on this device from the session's
/// saved transcript, bookmarks and notes only. Each point plays its moment.
class SummarySection extends ConsumerStatefulWidget {
  const SummarySection({
    super.key,
    required this.activityId,
    required this.title,
    required this.notesMd,
    required this.bookmarks,
    required this.cuts,
    required this.canPlay,
    required this.onPlayFrom,
    required this.onOpenTranscription,
  });

  final String activityId;
  final String title;
  final String? notesMd;
  final List<MaterialBookmark> bookmarks;
  final List<CutRange> cuts;
  final bool canPlay;
  final ValueChanged<int> onPlayFrom;

  /// Opens the transcription screen; the summary reloads on return.
  final Future<void> Function() onOpenTranscription;

  @override
  ConsumerState<SummarySection> createState() => _SummarySectionState();
}

class _SummarySectionState extends ConsumerState<SummarySection> {
  bool _loading = true;
  SessionMaterial? _material;
  SessionSummary? _saved;
  bool _savedUnreadable = false;
  String? _unavailable;
  SessionSummariser? _summariser;
  double? _progress;
  String? _error;

  bool _running = false;

  /// Counts runs, so a run stopped while the model is checked can tell it was
  /// replaced when the check finishes [P3-02d].
  int _run = 0;

  /// The model check in progress, shared by a run that starts before an
  /// abandoned check finishes, so the model is not hashed twice.
  Future<TextGenerationEngine>? _opening;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(SummarySection old) {
    super.didUpdateWidget(old);
    if (old.notesMd != widget.notesMd ||
        old.bookmarks != widget.bookmarks ||
        old.cuts != widget.cuts) {
      unawaited(_load());
    }
  }

  @override
  void dispose() {
    // Leaving the tab stops a summary in progress; nothing is saved.
    unawaited(_summariser?.cancel());
    super.dispose();
  }

  Future<void> _load() async {
    final transcripts = await ref.read(summaryTranscriptsProvider)(
      widget.activityId,
    );
    final material = SessionMaterial.build(
      title: widget.title,
      transcripts: transcripts,
      bookmarks: widget.bookmarks,
      notesMd: widget.notesMd,
      cuts: widget.cuts,
    );
    SessionSummary? saved;
    var unreadable = false;
    try {
      saved = await (await ref.read(
        summaryStoreProvider,
      )()).load(widget.activityId);
    } on Object {
      unreadable = true;
    }
    final unavailable = await ref
        .read(summaryModelAccessProvider)
        .unavailableReason();
    if (!mounted) return;
    setState(() {
      _material = material;
      _saved = saved;
      _savedUnreadable = unreadable;
      _unavailable = unavailable;
      _loading = false;
    });
  }

  Future<void> _summarise() async {
    final material = _material;
    if (material == null || _running) return;
    if (ref.read(summaryBlockedByRecordingProvider)()) {
      setState(
        () => _error =
            'A recording is running. Summaries wait until it stops, so the '
            'recording keeps the processor.',
      );
      return;
    }
    TextGenerationEngine? engine;
    String? instructions;
    final run = ++_run;
    bool current() => mounted && run == _run;
    final opening = _opening ??= ref.read(summaryModelAccessProvider).open();
    setState(() {
      _running = true;
      _error = null;
      _progress = null;
    });
    try {
      try {
        engine = await opening;
      } finally {
        if (identical(_opening, opening)) _opening = null;
      }
      if (!current()) {
        // Stopped while the model was checked. A newer run waiting on the
        // same check owns the engine; otherwise nothing will use it.
        if (mounted && _running) engine = null;
        return;
      }
      // Verification can take long enough for a recording to start.
      if (ref.read(summaryBlockedByRecordingProvider)()) {
        _fail(
          'A recording is running. Summaries wait until it stops, so the '
          'recording keeps the processor.',
        );
        return;
      }
      instructions = await ref.read(summaryInstructionsProvider)();
      if (!current()) return;
      final summariser = SessionSummariser(
        engine: engine,
        instructions: instructions,
      );
      await summariser.prepare();
      if (!current()) return;
      // A recording may have started while the instructions were read and
      // counted: check right before inference.
      if (ref.read(summaryBlockedByRecordingProvider)()) {
        _fail(
          'A recording is running. Summaries wait until it stops, so the '
          'recording keeps the processor.',
        );
        return;
      }
      setState(() => _summariser = summariser);
      final summary = await summariser.summarise(
        material,
        activityId: widget.activityId,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      await (await ref.read(summaryStoreProvider)()).save(summary);
      if (!mounted) return;
      setState(() {
        _saved = summary;
        _savedUnreadable = false;
      });
    } on TextGenerationCancelledException {
      // Stopped by the user or by leaving the tab; the old summary stays.
    } on SummaryInstructionsTooLongException {
      if (current()) _fail(SummaryInstructionsTooLongException.message);
    } on SummaryFormatException {
      if (current()) {
        _fail('The model gave an answer that could not be read. Try again.');
      }
    } on Object {
      if (current()) {
        // Own instructions may be what the model could not take.
        final custom =
            instructions != null && instructions != compactSummaryInstructions;
        _fail(
          'The summary could not be made. The recording and transcript are '
          'unchanged.'
          '${custom ? ' If you changed the summary instructions, try shorter '
                    'ones or Reset to default.' : ''}',
        );
      }
    } finally {
      unawaited(engine?.dispose());
      if (current()) {
        setState(() {
          _summariser = null;
          _running = false;
        });
      }
    }
  }

  void _stop() {
    final summariser = _summariser;
    if (summariser != null) {
      unawaited(summariser.cancel());
      return;
    }
    // Still checking the model: the check cannot be interrupted, so the run
    // is dropped now and its result discarded when the check finishes.
    setState(() {
      _run++;
      _running = false;
      _progress = null;
    });
  }

  void _fail(String message) {
    if (mounted) setState(() => _error = message);
  }

  Future<void> _copy(SessionSummary summary) async {
    await Clipboard.setData(
      ClipboardData(text: summaryAsText(widget.title, summary)),
    );
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(const SnackBar(content: Text('Summary copied')));
  }

  @override
  Widget build(BuildContext context) {
    final material = _material;
    if (_loading || material == null) {
      return const Center(
        key: Key('review-tab-summary'),
        child: Padding(
          padding: EdgeInsets.all(TokenSpace.space5),
          child: CircularProgressIndicator(),
        ),
      );
    }
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final saved = _saved;
    return Column(
      key: const Key('review-tab-summary'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_running) ..._progressRows(theme),
        if (_error case final error?) ...[
          Text(
            error,
            key: const Key('summary-error'),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
          const SizedBox(height: TokenSpace.space3),
        ],
        if (saved != null)
          ..._summaryRows(theme, muted, saved, material)
        else if (!_running) ...[
          if (_savedUnreadable) ...[
            Text(
              'The saved summary could not be read. Making a new one '
              'replaces it.',
              style: muted,
            ),
            const SizedBox(height: TokenSpace.space3),
          ],
          ..._emptyRows(theme, muted, material),
        ],
      ],
    );
  }

  List<Widget> _progressRows(ThemeData theme) => [
    LinearProgressIndicator(
      key: const Key('summary-progress'),
      value: _progress,
      semanticsLabel: 'Summarising',
    ),
    const SizedBox(height: TokenSpace.space2),
    Text(
      _summariser == null
          ? 'Checking the AI model. The first check after opening the app can '
                'take a minute.'
          : 'Summarising on this device. On a phone this can take a few '
                'minutes; stay on this tab.',
      key: const Key('summary-progress-text'),
      style: theme.textTheme.bodyMedium,
    ),
    Align(
      alignment: AlignmentDirectional.centerStart,
      child: TextButton(
        key: const Key('summary-cancel'),
        onPressed: _stop,
        child: const Text('Stop'),
      ),
    ),
    const SizedBox(height: TokenSpace.space3),
  ];

  List<Widget> _emptyRows(
    ThemeData theme,
    TextStyle? muted,
    SessionMaterial material,
  ) {
    if (!material.hasSpeech) {
      return [
        Text(
          'Summaries are built from the session transcript. Transcribe this '
          'session first.',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: TokenSpace.space3),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: OutlinedButton.icon(
            key: const Key('summary-open-transcription'),
            onPressed: () async {
              await widget.onOpenTranscription();
              if (mounted) await _load();
            },
            icon: const Icon(Icons.transcribe),
            label: const Text('Open transcription'),
          ),
        ),
      ];
    }
    if (_unavailable case final reason?) {
      return [
        Text(
          reason,
          key: const Key('summary-unavailable'),
          style: theme.textTheme.bodyMedium,
        ),
      ];
    }
    return [
      Text(
        'Make a summary, key points, follow-ups and questions from this '
        'session transcript, bookmarks and notes. It runs on this device; '
        'nothing is sent anywhere.',
        style: theme.textTheme.bodyMedium,
      ),
      const SizedBox(height: TokenSpace.space3),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: FilledButton.icon(
          key: const Key('summary-create'),
          onPressed: _running ? null : _summarise,
          icon: const Icon(Icons.auto_awesome_outlined),
          label: const Text('Create summary'),
        ),
      ),
    ];
  }

  List<Widget> _summaryRows(
    ThemeData theme,
    TextStyle? muted,
    SessionSummary summary,
    SessionMaterial material,
  ) {
    final stale = summary.materialFingerprint != material.fingerprint;
    Widget heading(String text) => Padding(
      padding: const EdgeInsets.only(
        top: TokenSpace.space4,
        bottom: TokenSpace.space2,
      ),
      child: Semantics(
        header: true,
        child: Text(
          text,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
    return [
      Text(
        'Machine-generated by ${summary.modelId}. It may be wrong; check '
        'points against the recording.',
        key: const Key('summary-label'),
        style: muted,
      ),
      if (stale) ...[
        const SizedBox(height: TokenSpace.space2),
        Text(
          'The transcript, bookmarks or notes changed after this summary was '
          'made.',
          key: const Key('summary-stale'),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.tertiary,
          ),
        ),
      ],
      const SizedBox(height: TokenSpace.space3),
      SelectableText(
        summary.summary.isEmpty ? 'No overall summary.' : summary.summary,
        key: const Key('summary-text'),
        style: theme.textTheme.bodyLarge,
      ),
      if (summary.points.isNotEmpty) ...[
        heading('Key points'),
        for (final (i, p) in summary.points.indexed)
          _ItemRow(
            key: Key('summary-point-$i'),
            item: p,
            canPlay: widget.canPlay,
            onPlayFrom: widget.onPlayFrom,
          ),
      ],
      if (summary.followUps.isNotEmpty) ...[
        heading('Follow-ups'),
        for (final (i, f) in summary.followUps.indexed)
          _ItemRow(
            key: Key('summary-follow-up-$i'),
            item: f,
            canPlay: widget.canPlay,
            onPlayFrom: widget.onPlayFrom,
          ),
      ],
      if (summary.questions.isNotEmpty) ...[
        heading('Questions to ask'),
        for (final q in summary.questions)
          Padding(
            padding: const EdgeInsets.only(bottom: TokenSpace.space2),
            child: Text('• $q', style: theme.textTheme.bodyMedium),
          ),
      ],
      const SizedBox(height: TokenSpace.space4),
      Wrap(
        spacing: TokenSpace.space2,
        runSpacing: TokenSpace.space2,
        children: [
          OutlinedButton.icon(
            key: const Key('summary-copy'),
            onPressed: () => _copy(summary),
            icon: const Icon(Icons.copy_rounded),
            label: const Text('Copy'),
          ),
          if (_unavailable == null && material.hasSpeech)
            TextButton.icon(
              key: const Key('summary-regenerate'),
              onPressed: _running ? null : _summarise,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Make again'),
            ),
        ],
      ),
    ];
  }
}

/// A point or follow-up with the time that plays it.
class _ItemRow extends StatelessWidget {
  const _ItemRow({
    super.key,
    required this.item,
    required this.canPlay,
    required this.onPlayFrom,
  });

  final SummaryItem item;
  final bool canPlay;
  final ValueChanged<int> onPlayFrom;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final time = formatSummaryTime(item.at);
    return Padding(
      padding: const EdgeInsets.only(bottom: TokenSpace.space2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextButton(
            onPressed: canPlay
                ? () => onPlayFrom(item.at.inMilliseconds)
                : null,
            style: TextButton.styleFrom(
              minimumSize: const Size(TokenSize.tapMin, TokenSize.tapMin),
              padding: const EdgeInsets.symmetric(
                horizontal: TokenSpace.space2,
              ),
            ),
            child: Text(
              time,
              semanticsLabel: 'Play from $time',
              style: theme.textTheme.labelLarge?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(width: TokenSpace.space2),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: TokenSpace.space3),
              child: Text(item.text, style: theme.textTheme.bodyMedium),
            ),
          ),
        ],
      ),
    );
  }
}

/// The summary as plain text for copying, with the machine-generated label.
String summaryAsText(String title, SessionSummary summary) {
  final lines = <String>[
    'Summary: $title',
    'Machine-generated by ${summary.modelId}; may contain errors.',
    '',
    if (summary.summary.isNotEmpty) ...[summary.summary, ''],
    if (summary.points.isNotEmpty) ...[
      'Key points',
      for (final p in summary.points)
        '- [${formatSummaryTime(p.at)}] ${p.text}',
      '',
    ],
    if (summary.followUps.isNotEmpty) ...[
      'Follow-ups',
      for (final f in summary.followUps)
        '- [${formatSummaryTime(f.at)}] ${f.text}',
      '',
    ],
    if (summary.questions.isNotEmpty) ...[
      'Questions to ask',
      for (final q in summary.questions) '- $q',
    ],
  ];
  return '${lines.join('\n').trimRight()}\n';
}

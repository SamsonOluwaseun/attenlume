import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/tokens.dart';
import '../../data/filesystem/media_paths.dart';
import '../../data/repositories/activity_repository.dart';
import '../../data/repositories/repository_providers.dart';
import '../../domain/models/activity.dart';
import '../../domain/models/enums.dart';
import '../../domain/models/media.dart';
import '../../domain/services/activity_splitter.dart';
import '../../domain/services/permanent_trim_service.dart';
import '../../domain/services/review_timeline.dart';
import '../../platform/audio_playback/audio_playback_engine.dart';
import '../../platform/audio_playback/audioplayers_playback_engine.dart';
import '../../platform/audio_trimmer/mp4_sample_trimmer.dart';
import '../../shared/utilities/date_formatters.dart';
import '../capture/recording_providers.dart';
import 'review_player_controller.dart';
import 'timeline_strip.dart';
import 'trim_panel.dart';
import 'waveform_pages.dart';
import 'waveform_view.dart';

/// Makes a new player for each review screen, which disposes it on close
/// (ADR-034) [P1-17].
final audioPlaybackEngineFactoryProvider =
    Provider<AudioPlaybackEngine Function()>(
      (ref) => AudioplayersPlaybackEngine.new,
    );

final activitySplitterProvider = Provider<ActivitySplitter>(
  (ref) => ActivitySplitter(
    activities: ref.watch(activityRepositoryProvider),
    mediaRoot: ref.watch(mediaRootProvider),
  ),
);

/// "Apply trims permanently" (FR-REV-06, ADR-037) [P1-19].
final permanentTrimServiceProvider = Provider<PermanentTrimService>(
  (ref) => PermanentTrimService(
    activities: ref.watch(activityRepositoryProvider),
    media: ref.watch(mediaAssetRepositoryProvider),
    cuts: ref.watch(cutRangeRepositoryProvider),
    trimmer: const Mp4SampleTrimmer(),
    mediaRoot: ref.watch(mediaRootProvider),
    freeSpace: ref.watch(freeSpaceProbeProvider),
  ),
);

/// Player, timeline and waveform for one activity (FR-REV-01 to 03)
/// [P1-17], with non-destructive trims, cuts with undo and split at the
/// playhead (FR-REV-04, FR-REV-05) [P1-18].
class ReviewScreen extends ConsumerStatefulWidget {
  const ReviewScreen({super.key, required this.activityId});

  final String activityId;

  @override
  ConsumerState<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends ConsumerState<ReviewScreen> {
  Activity? _activity;
  ReviewTimeline? _timeline;
  ReviewPlayerController? _player;
  WaveformPager? _pager;
  List<CutRange> _cuts = const [];
  int? _markedStartMs;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final activity = await ref
        .read(activityRepositoryProvider)
        .get(widget.activityId);
    final media = ref.read(mediaAssetRepositoryProvider);
    final id = widget.activityId;
    final timeline = ReviewTimeline.build(
      segments: await media.segmentsFor(id),
      interruptions: await media.interruptionsFor(id),
      photos: await media.photosFor(id),
      bookmarks: await media.bookmarksFor(id),
    );
    final cuts = await ref.read(cutRangeRepositoryProvider).activeFor(id);
    final mediaRoot = ref.read(mediaRootProvider);
    if (!mounted) return;
    final engine = ref.read(audioPlaybackEngineFactoryProvider)();
    setState(() {
      _activity = activity;
      _timeline = timeline;
      _cuts = cuts;
      _markedStartMs = null;
      _player = ReviewPlayerController(
        timeline: timeline,
        engine: engine,
        resolvePath: (s) async =>
            MediaPaths.resolve(await mediaRoot(), s.filePath).path,
      )..cutRanges = cuts;
      _pager = activity == null
          ? null
          : WaveformPager(
              timeline: timeline,
              summaryFile: (s) async => MediaPaths.resolve(
                await mediaRoot(),
                MediaPaths.waveform(activity.conferenceId, id, s.id),
              ),
            );
      _loading = false;
    });
  }

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  /// Trims need finished audio: not while a segment is still being written.
  bool get _editable {
    final timeline = _timeline;
    return timeline != null &&
        timeline.hasAudio &&
        timeline.segments.every((s) => s.segment.state != SegmentState.writing);
  }

  Future<void> _reloadCuts() async {
    final cuts = await ref
        .read(cutRangeRepositoryProvider)
        .activeFor(widget.activityId);
    if (!mounted) return;
    setState(() => _cuts = cuts);
    _player?.cutRanges = cuts;
  }

  void _say(String message, {VoidCallback? undo}) {
    final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        action: undo == null
            ? null
            : SnackBarAction(label: 'Undo', onPressed: undo),
      ),
    );
  }

  Future<void> _addCut(int start, int end, String reason) async {
    if (end <= start) return;
    final repo = ref.read(cutRangeRepositoryProvider);
    final cut = await repo.add(
      widget.activityId,
      startOffsetMs: start,
      endOffsetMs: end,
      reason: reason,
    );
    await _reloadCuts();
    if (!mounted) return;
    _say(
      'Cut ${formatOffset(start)} to ${formatOffset(end)}. '
      'The recording is unchanged.',
      undo: () async {
        await repo.remove(cut.id);
        await _reloadCuts();
      },
    );
  }

  Future<void> _removeCut(CutRange cut) async {
    final repo = ref.read(cutRangeRepositoryProvider);
    await repo.remove(cut.id);
    await _reloadCuts();
    if (!mounted) return;
    _say(
      'Cut removed.',
      undo: () async {
        await repo.restore(cut.id);
        await _reloadCuts();
      },
    );
  }

  void _markCut(int positionMs) {
    final start = _markedStartMs;
    if (start == null) {
      setState(() => _markedStartMs = positionMs);
      return;
    }
    setState(() => _markedStartMs = null);
    final (from, to) = start < positionMs
        ? (start, positionMs)
        : (positionMs, start);
    _addCut(from, to, 'Cut');
  }

  Future<void> _split(int positionMs) async {
    final activity = _activity;
    if (activity == null) return;
    await _player?.pause();
    if (!mounted) return;
    final title = await showDialog<String>(
      context: context,
      builder: (_) =>
          _SplitDialog(positionMs: positionMs, title: activity.title),
    );
    if (title == null || !mounted) return;
    final ActivitySplitResult result;
    try {
      result = await ref
          .read(activitySplitterProvider)
          .split(
            widget.activityId,
            splitOffsetMs: positionMs,
            part2Title: title,
          );
    } on Object {
      if (mounted) {
        _say('The activity could not be split. Nothing was changed.');
      }
      return;
    }
    if (!mounted) return;
    _player?.dispose();
    setState(() {
      _player = null;
      _loading = true;
    });
    await _load();
    if (!mounted) return;
    _say('Split. "${result.part2.title}" is now in the activity list.');
  }

  Future<void> _applyPermanently() async {
    await _player?.pause();
    final service = ref.read(permanentTrimServiceProvider);
    final PermanentTrimPlan plan;
    try {
      plan = await service.plan(widget.activityId);
    } on PermanentTrimException catch (e) {
      if (mounted) _say(e.message);
      return;
    }
    if (!mounted) return;
    if (!plan.hasWork) {
      _say(
        'The cuts only cover time between recordings, so there is nothing '
        'to write.',
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => _ApplyTrimDialog(plan: plan),
    );
    if (confirmed != true || !mounted) return;

    // Release the audio files first: Windows cannot move an open file.
    _player?.dispose();
    setState(() {
      _player = null;
      _loading = true;
    });
    final PermanentTrimResult result;
    try {
      result = await service.apply(widget.activityId);
    } on PermanentTrimException catch (e) {
      await _load();
      if (mounted) _say(e.message);
      return;
    }
    await _load();
    if (!mounted) return;
    if (result.originals.isEmpty) {
      _say(
        result.sharedOriginals > 0
            ? 'Trims applied. The original recording is kept because '
                  'another activity still uses it.'
            : 'Trims applied.',
      );
      return;
    }
    final remove = await showDialog<bool>(
      context: context,
      builder: (_) => _RemoveOriginalsDialog(result: result),
    );
    if (!mounted) return;
    if (remove == true) {
      final removed = await service.removeOriginals(result.originals);
      if (!mounted) return;
      _say(
        removed == result.originals.length
            ? 'Trims applied. Originals removed.'
            : 'Trims applied. Some originals could not be removed and are '
                  'still on this device.',
      );
    } else {
      _say('Trims applied. Your originals are kept.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final player = _player;
    final timeline = _timeline;
    return Scaffold(
      appBar: AppBar(title: Text(_activity?.title ?? 'Review')),
      body: _loading || player == null || timeline == null
          ? const Center(child: CircularProgressIndicator())
          : ListenableBuilder(
              listenable: player,
              builder: (context, _) => ListView(
                padding: const EdgeInsets.all(TokenSpace.space4),
                children: [
                  if (!player.canPlay)
                    Padding(
                      padding: const EdgeInsets.only(bottom: TokenSpace.space3),
                      child: Text(
                        'No recording to play yet. Photos and bookmarks '
                        'still show on the timeline.',
                        key: const Key('review-no-audio'),
                        style: theme.textTheme.bodyLarge,
                      ),
                    ),
                  if (_pager case final pager?)
                    WaveformView(
                      pager: pager,
                      positionMs: player.positionMs,
                      onSeek: player.seekTo,
                    ),
                  const SizedBox(height: TokenSpace.space4),
                  TimelineStrip(
                    timeline: timeline,
                    positionMs: player.positionMs,
                    onSeek: player.seekTo,
                    cuts: player.cuts,
                  ),
                  const SizedBox(height: TokenSpace.space2),
                  _PositionRow(timeline: timeline, player: player),
                  const SizedBox(height: TokenSpace.space3),
                  _Controls(player: player),
                  const SizedBox(height: TokenSpace.space5),
                  TrimPanel(
                    positionMs: player.positionMs,
                    audioEndMs: timeline.audioEndMs,
                    cuts: _cuts,
                    enabled: _editable,
                    markedStartMs: _markedStartMs,
                    onTrimStart: () =>
                        _addCut(0, player.positionMs, 'Trim start'),
                    onTrimEnd: () => _addCut(
                      player.positionMs,
                      timeline.audioEndMs,
                      'Trim end',
                    ),
                    onMarkCut: () => _markCut(player.positionMs),
                    onCancelMark: () => setState(() => _markedStartMs = null),
                    onSplit: () => _split(player.positionMs),
                    onRemoveCut: _removeCut,
                    onSeek: player.seekTo,
                    onApplyPermanently: _applyPermanently,
                  ),
                  if (player.error case final error?) ...[
                    const SizedBox(height: TokenSpace.space3),
                    Text(
                      error,
                      key: const Key('review-error'),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: TokenSpace.space5),
                  _KeyMoments(timeline: timeline, player: player),
                ],
              ),
            ),
    );
  }
}

class _PositionRow extends StatelessWidget {
  const _PositionRow({required this.timeline, required this.player});

  final ReviewTimeline timeline;
  final ReviewPlayerController player;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium
        ?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
    // Wraps at large text instead of overflowing (NFR-09).
    final row = Wrap(
      alignment: WrapAlignment.spaceBetween,
      spacing: TokenSpace.space2,
      children: [
        Text(
          formatOffset(player.positionMs),
          key: const Key('review-position'),
          style: style,
        ),
        Text(
          '${formatDuration(Duration(milliseconds: timeline.audioDurationMs))}'
          ' recorded',
          key: const Key('review-recorded'),
          style: style,
        ),
      ],
    );
    if (player.cuts.isEmpty) return row;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        row,
        Text(
          '${formatDuration(Duration(milliseconds: player.keptAudioMs))}'
          ' after cuts',
          key: const Key('review-kept'),
          style: style,
        ),
      ],
    );
  }
}

/// Confirms "Apply trims permanently" (FR-REV-06) [P1-19].
class _ApplyTrimDialog extends StatelessWidget {
  const _ApplyTrimDialog({required this.plan});

  final PermanentTrimPlan plan;

  @override
  Widget build(BuildContext context) {
    final removed = formatOffset(plan.removedMs);
    final kept = formatOffset(plan.keptMs);
    return AlertDialog(
      title: const Text('Apply trims permanently?'),
      content: Text(
        'Attenlume writes new audio files without the cut parts: $removed '
        'removed, $kept left. This needs about '
        '${formatStorageBytes(plan.estimatedBytes)} of space.\n\n'
        'Photos, bookmarks and notes stay where they are. Your original '
        'recordings are kept until you choose to remove them.',
        key: const Key('apply-trim-summary'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('apply-trim-confirm'),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Write trimmed files'),
        ),
      ],
    );
  }
}

/// Offers to remove originals once the trimmed files are saved
/// (FR-REV-06) [P1-19].
class _RemoveOriginalsDialog extends StatelessWidget {
  const _RemoveOriginalsDialog({required this.result});

  final PermanentTrimResult result;

  @override
  Widget build(BuildContext context) {
    final n = result.originals.length;
    final files = n == 1 ? 'original recording' : '$n original recordings';
    return AlertDialog(
      title: const Text('Remove the originals?'),
      content: Text(
        'The trimmed files are saved. Your $files '
        '(${formatStorageBytes(result.originalBytes)}) are still on this '
        'device in case you need the cut parts. Removing them frees the '
        'space and cannot be undone.'
        '${result.sharedOriginals > 0 ? ' Recordings another activity still uses are kept either way.' : ''}',
        key: const Key('remove-originals-summary'),
      ),
      actions: [
        TextButton(
          key: const Key('keep-originals'),
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Keep originals'),
        ),
        TextButton(
          key: const Key('remove-originals'),
          style: TextButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.error,
          ),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Remove originals'),
        ),
      ],
    );
  }
}

/// Confirms a split and names the new activity (FR-REV-05) [P1-18].
class _SplitDialog extends StatefulWidget {
  const _SplitDialog({required this.positionMs, required this.title});

  final int positionMs;
  final String title;

  @override
  State<_SplitDialog> createState() => _SplitDialogState();
}

class _SplitDialogState extends State<_SplitDialog> {
  late final TextEditingController _name = TextEditingController(
    text: '${widget.title.isEmpty ? 'Session' : widget.title} (Part 2)',
  );

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final at = formatOffset(widget.positionMs);
    return AlertDialog(
      title: Text('Split at $at?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Everything from $at, with its photos and bookmarks, moves to a '
            'new activity. No audio is deleted or rewritten.',
          ),
          const SizedBox(height: TokenSpace.space3),
          TextField(
            key: const Key('split-title'),
            controller: _name,
            decoration: const InputDecoration(labelText: 'New activity name'),
            textCapitalization: TextCapitalization.sentences,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('split-confirm'),
          onPressed: () => Navigator.of(context).pop(_name.text),
          child: const Text('Split'),
        ),
      ],
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({required this.player});

  final ReviewPlayerController player;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = player.canPlay;
    final speed = player.speed;
    final speedText = speed == speed.roundToDouble()
        ? '${speed.toInt()}×'
        : '$speed×';
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          key: const Key('review-skip-back'),
          tooltip: 'Back 15 seconds',
          iconSize: 32,
          onPressed: enabled ? player.skipBack : null,
          icon: const Icon(Icons.replay_rounded),
        ),
        const SizedBox(width: TokenSpace.space4),
        SizedBox(
          width: 72,
          height: 72,
          child: IconButton.filled(
            key: const Key('review-play'),
            tooltip: player.isPlaying ? 'Pause' : 'Play',
            iconSize: 40,
            onPressed: enabled ? player.togglePlay : null,
            icon: Icon(
              player.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
            ),
          ),
        ),
        const SizedBox(width: TokenSpace.space4),
        IconButton(
          key: const Key('review-skip-forward'),
          tooltip: 'Forward 15 seconds',
          iconSize: 32,
          onPressed: enabled ? player.skipForward : null,
          icon: const Icon(Icons.forward_rounded),
        ),
        const SizedBox(width: TokenSpace.space4),
        Semantics(
          button: true,
          label: 'Playback speed $speedText',
          excludeSemantics: true,
          child: OutlinedButton(
            key: const Key('review-speed'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(TokenSize.tapMin, TokenSize.tapMin),
            ),
            onPressed: enabled ? player.cycleSpeed : null,
            child: Text(speedText, style: theme.textTheme.labelLarge),
          ),
        ),
      ],
    );
  }
}

/// Bookmarks and photos in time order; tapping one plays from there.
class _KeyMoments extends StatelessWidget {
  const _KeyMoments({required this.timeline, required this.player});

  final ReviewTimeline timeline;
  final ReviewPlayerController player;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final moments = timeline.markers
        .where((m) => m.kind != TimelineMarkerKind.interruption)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Key moments',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        if (moments.isEmpty)
          Text(
            'No bookmarks or photos in this activity.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        for (final m in moments)
          ListTile(
            key: Key('review-moment-${m.id}'),
            contentPadding: EdgeInsets.zero,
            minTileHeight: TokenSize.tapMin,
            leading: Icon(
              m.kind == TimelineMarkerKind.photo
                  ? Icons.photo_camera_outlined
                  : Icons.bookmark_rounded,
            ),
            title: Text(
              m.label ??
                  (m.kind == TimelineMarkerKind.photo ? 'Photo' : 'Bookmark'),
            ),
            trailing: Text(
              formatOffset(m.offsetMs),
              style: theme.textTheme.bodySmall?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            onTap: player.canPlay ? () => player.seekTo(m.offsetMs) : null,
          ),
      ],
    );
  }
}

/// Opens the review screen for an activity.
Future<void> openReview(BuildContext context, String activityId) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ReviewScreen(activityId: activityId),
      ),
    );

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/tokens.dart';
import '../../data/filesystem/app_data_directory.dart';
import '../../data/filesystem/media_paths.dart';
import '../../data/repositories/activity_repository.dart';
import '../../data/repositories/repository_providers.dart';
import '../../data/transcription/transcript_store.dart';
import '../../domain/ai/session_material.dart' show MaterialBookmark;
import '../../domain/models/activity.dart';
import '../../domain/models/conference.dart';
import '../../domain/models/enums.dart';
import '../../domain/models/media.dart';
import '../../domain/services/activity_splitter.dart';
import '../../domain/services/permanent_trim_service.dart';
import '../../domain/services/review_timeline.dart';
import '../../domain/services/transcript_carrier.dart';
import '../../platform/audio_playback/audio_playback_engine.dart';
import '../../platform/audio_playback/audioplayers_playback_engine.dart';
import '../../platform/audio_trimmer/mp4_sample_trimmer.dart';
import '../../shared/utilities/date_formatters.dart';
import '../bookmarks/activity_notes_section.dart';
import '../capture/recording_providers.dart';
import '../photos/activity_photos_section.dart';
import '../summaries/summary_section.dart';
import '../transcription/transcription_providers.dart';
import '../transcription/transcription_screen.dart';
import 'review_header.dart';
import 'review_moments.dart';
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

/// Moves saved transcripts with a permanent trim or split (ADR-081). The
/// same folder the transcription screen uses; opening it loads no model.
/// Null leaves transcripts where they are.
final transcriptCarrierProvider = Provider<TranscriptCarrier?>(
  (ref) => TranscriptCarrier(
    store: () async => TranscriptStore(await appDataDirectory()),
    media: ref.watch(mediaAssetRepositoryProvider),
  ),
);

final activitySplitterProvider = Provider<ActivitySplitter>(
  (ref) => ActivitySplitter(
    activities: ref.watch(activityRepositoryProvider),
    mediaRoot: ref.watch(mediaRootProvider),
    transcripts: ref.watch(transcriptCarrierProvider),
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
    transcripts: ref.watch(transcriptCarrierProvider),
  ),
);

/// Player, timeline and waveform for one activity (FR-REV-01 to 03)
/// [P1-17], with non-destructive trims, cuts with undo and split at the
/// playhead (FR-REV-04, FR-REV-05) [P1-18].
///
/// Laid out as the screens board's "Session review" (ADR-053) [P1-39]: hero
/// photo, title, place, date and duration, the player, then tabs for
/// Highlights (Key moments), Timeline (waveform, timeline and trims),
/// Photos and Notes.
class ReviewScreen extends ConsumerStatefulWidget {
  const ReviewScreen({super.key, required this.activityId});

  final String activityId;

  @override
  ConsumerState<ReviewScreen> createState() => _ReviewScreenState();
}

/// The review screen's tabs, in order (ADR-053).
enum ReviewTab {
  highlights('Highlights'),
  summary('Summary'),
  timeline('Timeline'),
  photos('Photos'),
  notes('Notes');

  const ReviewTab(this.label);
  final String label;
}

class _ReviewScreenState extends ConsumerState<ReviewScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(
    length: ReviewTab.values.length,
    vsync: this,
  )..addListener(_onTab);
  Activity? _activity;
  Conference? _conference;
  List<Photo> _photos = const [];
  Directory? _root;
  ReviewTimeline? _timeline;
  ReviewPlayerController? _player;
  WaveformPager? _pager;
  List<CutRange> _cuts = const [];

  /// Bookmarks on the timeline, for the Summary tab (P3-02). Built once per
  /// load so playback rebuilds do not reload the summary.
  List<MaterialBookmark> _summaryBookmarks = const [];
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
    final photos = await media.photosFor(id);
    final bookmarks = await media.bookmarksFor(id);
    final timeline = ReviewTimeline.build(
      segments: await media.segmentsFor(id),
      interruptions: await media.interruptionsFor(id),
      photos: photos,
      bookmarks: bookmarks,
    );
    final bookmarkOffsets = {
      for (final m in timeline.markers)
        if (m.kind == TimelineMarkerKind.bookmark) m.id: m.offsetMs,
    };
    final cuts = await ref.read(cutRangeRepositoryProvider).activeFor(id);
    final conference = activity == null
        ? null
        : await ref
              .read(conferenceRepositoryProvider)
              .get(activity.conferenceId);
    final mediaRoot = ref.read(mediaRootProvider);
    final root = await mediaRoot();
    if (!mounted) return;
    final engine = ref.read(audioPlaybackEngineFactoryProvider)();
    setState(() {
      _activity = activity;
      _conference = conference;
      _photos = photos;
      _root = root;
      _timeline = timeline;
      _cuts = cuts;
      _summaryBookmarks = [
        for (final b in bookmarks)
          if (bookmarkOffsets[b.id] case final offset?)
            (offsetMs: offset, label: b.label, note: b.note),
      ];
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
    _tabs.dispose();
    _player?.dispose();
    super.dispose();
  }

  void _onTab() {
    if (mounted) setState(() {});
  }

  /// Rereads the activity after its notes change.
  Future<void> _reloadActivity() async {
    final activity = await ref
        .read(activityRepositoryProvider)
        .get(widget.activityId);
    if (mounted && activity != null) setState(() => _activity = activity);
  }

  /// Opens a photo to view it and edit its caption and label (FR-PHO-06).
  Future<void> _openPhoto(Photo photo) async {
    final root = _root;
    if (root == null) return;
    final updated = await PhotoDetailSheet.show(context, photo, root);
    if (updated == null || !mounted) return;
    final photos = await ref
        .read(mediaAssetRepositoryProvider)
        .photosFor(widget.activityId);
    if (mounted) setState(() => _photos = photos);
  }

  /// Moves the playhead and starts playback, for "Play from here".
  Future<void> _playFrom(int offsetMs) async {
    final player = _player;
    if (player == null || !player.canPlay) return;
    await player.seekTo(offsetMs);
    if (!player.isPlaying) await player.play();
  }

  void _showOnTimeline(int offsetMs) {
    _player?.seekTo(offsetMs);
    _tabs.animateTo(ReviewTab.timeline.index);
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
    await _reloadTranscripts({widget.activityId, result.part2.id});
    if (!mounted) return;
    _say(
      'Split. "${result.part2.title}" is now in the activity list.'
      '${_transcriptNote(result.transcripts)}',
    );
  }

  /// Says when saved transcripts could not follow a trim or split
  /// (ADR-081); empty when they did, or there were none.
  String _transcriptNote(TranscriptCarryReport report) {
    if (report.unchecked) {
      return ' Saved transcripts could not be checked, so any are left as '
          'they were.';
    }
    if (report.notCarried == 0) return '';
    return report.notCarried == 1
        ? ' A saved transcript could not be moved and is left as it was.'
        : ' ${report.notCarried} saved transcripts could not be moved and '
              'are left as they were.';
  }

  /// The transcription screen keeps transcripts in memory; refresh it only
  /// if it is already open, so this never loads a model (ADR-081).
  Future<void> _reloadTranscripts(Set<String> activityIds) async {
    if (!ref.exists(transcriptionControllerProvider)) return;
    try {
      final controller = ref.read(transcriptionControllerProvider).value;
      await controller?.reloadActivities(activityIds);
    } on Object {
      // Shown again the next time the app starts.
    }
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
    await _reloadTranscripts({widget.activityId});
    if (!mounted) return;
    final note = _transcriptNote(result.transcripts);
    if (result.originals.isEmpty) {
      _say(
        result.sharedOriginals > 0
            ? 'Trims applied. The original recording is kept because '
                  'another activity still uses it.$note'
            : 'Trims applied.$note',
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
            ? 'Trims applied. Originals removed.$note'
            : 'Trims applied. Some originals could not be removed and are '
                  'still on this device.$note',
      );
    } else {
      _say('Trims applied. Your originals are kept.$note');
    }
  }

  @override
  Widget build(BuildContext context) {
    final player = _player;
    final timeline = _timeline;
    return Scaffold(
      appBar: AppBar(title: const Text('Session review')),
      body: _loading || player == null || timeline == null
          ? const Center(child: CircularProgressIndicator())
          : ListenableBuilder(
              listenable: player,
              builder: (context, _) => LayoutBuilder(
                builder: (context, constraints) {
                  // Content up to 720 dp wide, centred on tablets and
                  // Windows (DESIGN_GUIDE layout).
                  final side =
                      constraints.maxWidth > 720 + TokenSpace.space5 * 2
                      ? (constraints.maxWidth - 720) / 2
                      : TokenSpace.space4;
                  return ListView(
                    key: const Key('review-scroll'),
                    padding: EdgeInsets.symmetric(
                      horizontal: side,
                      vertical: TokenSpace.space4,
                    ),
                    children: [
                      ..._header(timeline),
                      const SizedBox(height: TokenSpace.space4),
                      _PlayerCard(timeline: timeline, player: player),
                      const SizedBox(height: TokenSpace.space4),
                      _ReviewTabBar(controller: _tabs),
                      const SizedBox(height: TokenSpace.space4),
                      _tabBody(timeline, player),
                    ],
                  );
                },
              ),
            ),
    );
  }

  List<Widget> _header(ReviewTimeline timeline) {
    final activity = _activity;
    final conference = _conference;
    final place = [
      if (activity?.room case final room? when room.trim().isNotEmpty)
        room.trim(),
      ?conference?.name,
    ].join(' · ');
    final started =
        activity?.actualStart ??
        (timeline.segments.isEmpty
            ? null
            : timeline.segments.first.segment.startUtc) ??
        activity?.plannedStart;
    return [
      ReviewHero(photo: reviewHeroPhoto(_photos), root: _root),
      const SizedBox(height: TokenSpace.space4),
      ReviewHeader(
        title: activity?.title ?? '',
        place: place,
        date: started == null
            ? null
            : reviewDate(started, conference?.timezone ?? 'UTC'),
        durationMs: timeline.audioDurationMs,
      ),
    ];
  }

  Widget _tabBody(ReviewTimeline timeline, ReviewPlayerController player) {
    return switch (ReviewTab.values[_tabs.index]) {
      ReviewTab.highlights => ReviewHighlights(
        key: const Key('review-tab-highlights'),
        moments: keyMoments(timeline, _photos),
        root: _root,
        canPlay: player.canPlay,
        onSeek: player.seekTo,
        onPlayFrom: _playFrom,
        onShowOnTimeline: _showOnTimeline,
        onOpenPhoto: _openPhoto,
      ),
      ReviewTab.summary => SummarySection(
        activityId: widget.activityId,
        title: _activity?.title ?? '',
        notesMd: _activity?.notesMd,
        bookmarks: _summaryBookmarks,
        cuts: _cuts,
        canPlay: player.canPlay,
        onPlayFrom: _playFrom,
        onOpenTranscription: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => TranscriptionScreen(
              activityId: widget.activityId,
              isPrivate: _activity?.isPrivate ?? false,
            ),
          ),
        ),
      ),
      ReviewTab.timeline => Column(
        key: const Key('review-tab-timeline'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_pager case final pager?) ...[
            WaveformView(
              pager: pager,
              positionMs: player.positionMs,
              onSeek: player.seekTo,
            ),
            const SizedBox(height: TokenSpace.space4),
          ],
          TimelineStrip(
            timeline: timeline,
            positionMs: player.positionMs,
            onSeek: player.seekTo,
            cuts: player.cuts,
          ),
          const SizedBox(height: TokenSpace.space5),
          TrimPanel(
            positionMs: player.positionMs,
            audioEndMs: timeline.audioEndMs,
            cuts: _cuts,
            enabled: _editable,
            markedStartMs: _markedStartMs,
            onTrimStart: () => _addCut(0, player.positionMs, 'Trim start'),
            onTrimEnd: () =>
                _addCut(player.positionMs, timeline.audioEndMs, 'Trim end'),
            onMarkCut: () => _markCut(player.positionMs),
            onCancelMark: () => setState(() => _markedStartMs = null),
            onSplit: () => _split(player.positionMs),
            onRemoveCut: _removeCut,
            onSeek: player.seekTo,
            onApplyPermanently: _applyPermanently,
          ),
        ],
      ),
      ReviewTab.photos => ReviewPhotos(
        key: const Key('review-tab-photos'),
        photos: _photos,
        offsets: {
          for (final m in timeline.markers)
            if (m.kind == TimelineMarkerKind.photo) m.id: m.offsetMs,
        },
        root: _root,
        canPlay: player.canPlay,
        onPlayFrom: _playFrom,
        onOpenPhoto: _openPhoto,
      ),
      ReviewTab.notes => ActivityNotesSection(
        key: const Key('review-tab-notes'),
        activityId: widget.activityId,
        notesMd: _activity?.notesMd,
        onChanged: _reloadActivity,
      ),
    };
  }
}

/// Highlights, Timeline, Photos and Notes as pills: the selected one on
/// brand-tint with ink text (DESIGN_GUIDE tokens) [P1-39].
class _ReviewTabBar extends StatelessWidget {
  const _ReviewTabBar({required this.controller});

  final TabController controller;

  static const _padding = TokenSpace.space2;

  /// True when every label fits in an equal share of [width].
  static bool _fits(BuildContext context, TextStyle? style, double width) {
    final share = width / ReviewTab.values.length - _padding * 2;
    final scaler = MediaQuery.textScalerOf(context);
    for (final tab in ReviewTab.values) {
      final painter = TextPainter(
        text: TextSpan(text: tab.label, style: style),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      final w = painter.width;
      painter.dispose();
      if (w > share) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        // Equal pills across the width, as on the board; scrolls sideways
        // only when large text no longer fits (NFR-09).
        final scrollable = !_fits(
          context,
          theme.textTheme.labelLarge,
          constraints.maxWidth,
        );
        return _bar(scheme, theme, scrollable: scrollable);
      },
    );
  }

  Widget _bar(ColorScheme scheme, ThemeData theme, {required bool scrollable}) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(TokenRadius.radiusPill),
      ),
      child: TabBar(
        key: const Key('review-tabs'),
        controller: controller,
        isScrollable: scrollable,
        tabAlignment: scrollable ? TabAlignment.start : TabAlignment.fill,
        dividerColor: Colors.transparent,
        indicatorSize: TabBarIndicatorSize.tab,
        indicator: BoxDecoration(
          color: scheme.primaryContainer,
          borderRadius: BorderRadius.circular(TokenRadius.radiusPill),
        ),
        labelColor: scheme.onPrimaryContainer,
        unselectedLabelColor: scheme.onSurface,
        labelStyle: theme.textTheme.labelLarge,
        unselectedLabelStyle: theme.textTheme.labelLarge,
        labelPadding: const EdgeInsets.symmetric(horizontal: _padding),
        tabs: [
          for (final tab in ReviewTab.values)
            Tab(
              key: Key('review-tab-${tab.name}-button'),
              height: TokenSize.tapMin,
              text: tab.label,
            ),
        ],
      ),
    );
  }
}

/// Play controls, position and any playback error, on every tab.
class _PlayerCard extends StatelessWidget {
  const _PlayerCard({required this.timeline, required this.player});

  final ReviewTimeline timeline;
  final ReviewPlayerController player;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(TokenSpace.space3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
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
            _Controls(player: player),
            const SizedBox(height: TokenSpace.space2),
            _PositionRow(timeline: timeline, player: player),
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
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        row,
        Text(
          '${formatDuration(Duration(milliseconds: player.keptAudioMs))}'
          ' after cuts',
          key: const Key('review-kept'),
          textAlign: TextAlign.end,
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
    // Wraps at large text instead of overflowing (NFR-09).
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
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

/// Opens the review screen for an activity.
Future<void> openReview(BuildContext context, String activityId) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ReviewScreen(activityId: activityId),
      ),
    );

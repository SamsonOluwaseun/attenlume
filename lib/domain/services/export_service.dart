import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../data/filesystem/cuts_manifest.dart';
import '../../data/filesystem/export_space.dart';
import '../../data/filesystem/export_writer.dart';
import '../../data/filesystem/folder_export.dart';
import '../../data/filesystem/media_paths.dart';
import '../../data/filesystem/safe_export_paths.dart';
import '../../data/repositories/activity_repository.dart';
import '../../data/repositories/conference_repository.dart';
import '../../data/repositories/cut_range_repository.dart';
import '../../data/repositories/export_job_repository.dart';
import '../../data/repositories/media_asset_repository.dart';
import '../../data/repositories/repository_support.dart';
import '../../platform/storage/free_space_probe.dart';
import '../models/activity.dart';
import '../models/conference.dart';
import '../models/enums.dart';
import '../models/media.dart';
import 'activity_title.dart';
import 'cut_range_math.dart';
import 'export_documents.dart';
import 'permanent_trim_service.dart';
import 'private_notes.dart';
import 'review_timeline.dart';

/// Which activities an export covers (FR-EXP-01).
sealed class ExportSelection {
  const ExportSelection();

  Map<String, Object?> toJson();
}

/// Every activity in the conference.
class WholeConference extends ExportSelection {
  const WholeConference();

  @override
  Map<String, Object?> toJson() => {'kind': 'conference'};
}

/// The activities with these ids.
class SelectedActivities extends ExportSelection {
  const SelectedActivities(this.activityIds);

  final Set<String> activityIds;

  @override
  Map<String, Object?> toJson() => {
    'kind': 'activities',
    'activity_ids': activityIds.toList()..sort(),
  };
}

/// The activities on one calendar day in the conference's timezone.
class OneDay extends ExportSelection {
  OneDay(DateTime day) : day = DateTime.utc(day.year, day.month, day.day);

  /// Only year, month and day matter.
  final DateTime day;

  @override
  Map<String, Object?> toJson() => {
    'kind': 'day',
    'date': day.toIso8601String().substring(0, 10),
  };
}

/// What kinds of files an export holds (FR-EXP-01).
enum ExportContent implements KeyedEnum {
  everything('everything'),
  audioOnly('audio_only'),
  photosOnly('photos_only'),
  textOnly('text_only');

  const ExportContent(this.key);
  @override
  final String key;

  bool get audio => this == everything || this == audioOnly;
  bool get photos => this == everything || this == photosOnly;
  bool get text => this == everything || this == textOnly;
}

/// What the user asked to export.
class ExportRequest {
  const ExportRequest({
    required this.conferenceId,
    this.selection = const WholeConference(),
    this.content = ExportContent.everything,
    this.format = ExportFormat.folder,
    this.audioMode = ExportAudioMode.original,
    this.includePrivate = false,
    this.includeKeptOriginals = false,
  });

  final String conferenceId;
  final ExportSelection selection;
  final ExportContent content;
  final ExportFormat format;

  /// FR-EXP-03. Ignored when [content] has no audio.
  final ExportAudioMode audioMode;

  /// FR-EXP-10: off by default, so private activities, private thought
  /// bookmarks and private reflections in notes stay out.
  final bool includePrivate;

  /// Recordings a permanent trim replaced (`audio/originals/`, ADR-037).
  /// Not in any row, so left out unless asked.
  final bool includeKeptOriginals;

  ExportAudioMode get effectiveAudioMode =>
      content.audio ? audioMode : ExportAudioMode.none;

  /// Stored in `export_jobs.scope` and `conference.json`.
  Map<String, Object?> toScopeJson() => {
    ...selection.toJson(),
    'content': content.key,
    'format': format.key,
    'audio_mode': effectiveAudioMode.key,
    'include_private': includePrivate,
    'include_kept_originals': includeKeptOriginals,
  };
}

/// One activity as it goes into the export, for contributors.
class ExportedActivity {
  const ExportedActivity({
    required this.activity,
    required this.type,
    required this.folder,
    required this.segments,
    required this.photos,
    required this.bookmarks,
    required this.cuts,
    required this.interruptions,
    required this.files,
  });

  final Activity activity;
  final ActivityType type;

  /// Folder relative to the export root (`activities/001_0930_...`).
  final String folder;
  final List<RecordingSegment> segments;
  final List<Photo> photos;

  /// Private thoughts already removed unless private items are included.
  final List<Bookmark> bookmarks;
  final List<CutRange> cuts;
  final List<Interruption> interruptions;
  final ActivityExportFiles files;
}

/// What contributors see when adding files.
class ExportContext {
  const ExportContext({
    required this.conference,
    required this.goals,
    required this.request,
    required this.exportedAtUtc,
    required this.activities,
    required this.privateActivitiesExcluded,
    required this.privateNotesExcluded,
  });

  final Conference conference;
  final List<Goal> goals;
  final ExportRequest request;
  final DateTime exportedAtUtc;
  final List<ExportedActivity> activities;
  final int privateActivitiesExcluded;
  final int privateNotesExcluded;
}

/// A generated text file a contributor adds. [path] is relative to the
/// export root (or to the activity folder for activity documents) and is
/// made safe and unique (FR-EXP-07).
class ExportDocument {
  const ExportDocument(this.path, this.text);

  final String path;
  final String text;
}

/// Extension point for generated files (ADR-040). P1-22 adds the full
/// manifest, `timeline.csv`, `README_START_HERE.md`, `analysis_prompt.md`,
/// `prompts/` and `activity.md` by implementing this.
abstract class ExportContributor {
  const ExportContributor();

  /// Files at the export root.
  List<ExportDocument> rootDocuments(ExportContext context) => const [];

  /// Files in one activity's folder. Only called when the export includes
  /// text and metadata.
  List<ExportDocument> activityDocuments(
    ExportContext context,
    ExportedActivity activity,
  ) => const [];
}

/// The basic `conference.json` this task writes; P1-22 replaces it.
class BasicConferenceJsonContributor extends ExportContributor {
  const BasicConferenceJsonContributor();

  @override
  List<ExportDocument> rootDocuments(ExportContext context) => [
    ExportDocument(
      'conference.json',
      buildConferenceJson(
        conference: context.conference,
        goals: context.goals,
        exportedAtUtc: context.exportedAtUtc,
        scope: context.request.toScopeJson(),
        activities: [
          for (final a in context.activities)
            {
              'id': a.activity.id,
              'title': a.activity.title,
              'folder': a.folder,
            },
        ],
        privateActivitiesExcluded: context.privateActivitiesExcluded,
        privateNotesExcluded: context.privateNotesExcluded,
      ),
    ),
  ];
}

/// An export worked out but not yet written.
class ExportPlan {
  const ExportPlan({
    required this.request,
    required this.rootName,
    required this.entries,
    required this.activityCount,
    required this.privateActivitiesExcluded,
    required this.privateNotesExcluded,
    required this.segmentsSkipped,
    required this.tempBytes,
  });

  final ExportRequest request;

  /// Base name of the export folder or ZIP; a `-2` suffix is added at the
  /// destination if the name is taken.
  final String rootName;
  final List<ExportEntry> entries;
  final int activityCount;
  final int privateActivitiesExcluded;
  final int privateNotesExcluded;

  /// Damaged, still-recording or missing segments left out.
  final int segmentsSkipped;

  /// Scratch space a ZIP with trimmed copies needs while writing.
  final int tempBytes;

  /// Media files (audio and photos) in the export.
  int get mediaFileCount =>
      entries.where((e) => e.source is! TextExportSource).length;

  /// About how big the export's files are.
  int get contentBytes => entries.fold(0, (n, e) => n + e.estimatedBytes);

  /// What the destination needs, with checksums and filesystem slack.
  int get destinationBytes {
    final sizes = entries.map((e) => e.estimatedBytes);
    return request.format == ExportFormat.zip
        ? estimateZipExportBytes(sizes)
        : estimateFolderExportBytes(sizes);
  }
}

/// Space check before writing (FR-EXP-05).
class ExportPreflightReport {
  const ExportPreflightReport({
    required this.plan,
    required this.destination,
    this.temp,
  });

  final ExportPlan plan;
  final ExportPreflight destination;

  /// Null when the export needs no scratch space.
  final ExportPreflight? temp;

  bool get insufficient =>
      destination.status == PreflightStatus.insufficient ||
      temp?.status == PreflightStatus.insufficient;

  /// Free space could not be read; the UI must say so.
  bool get unknown =>
      destination.status == PreflightStatus.unknown ||
      temp?.status == PreflightStatus.unknown;
}

/// A finished export.
class ExportOutcome {
  const ExportOutcome({
    required this.jobId,
    required this.outputPath,
    required this.fileCount,
    required this.bytes,
    required this.verification,
  });

  final String jobId;

  /// The export folder or ZIP file.
  final String outputPath;

  /// Files listed in `checksums.sha256`.
  final int fileCount;
  final int bytes;
  final VerificationLevel verification;
}

/// Plain UK English refusals, ready to show. Nothing was written.
class ExportException implements Exception {
  const ExportException(this.message);

  final String message;

  @override
  String toString() => 'ExportException: $message';
}

/// Writes an [ExportWritePlan]; [writeExportInBackground] in the app,
/// [writeExport] inline in tests.
typedef ExportWriterFunction = Future<ExportWriteResult> Function(
  ExportWritePlan plan, {
  void Function(ExportWriteProgress progress)? onProgress,
  Future<void>? cancel,
});

/// Local export (FR-EXP-01 to 07, FR-EXP-10, ADR-040) [P1-21].
///
/// [plan] reads the database and file sizes only. [preflight] adds the
/// free-space check. [run] plans again, checks space, records an
/// `export_jobs` row and writes with [writer]. Sources are only ever read.
class ExportService {
  ExportService({
    required this.conferences,
    required this.activities,
    required this.media,
    required this.cuts,
    required this.jobs,
    required this.mediaRoot,
    required this.tempRoot,
    this.freeSpace = const UnknownFreeSpaceProbe(),
    this.reserveBytes = defaultExportReserveBytes,
    this.writer = writeExportInBackground,
    this.contributors = const [BasicConferenceJsonContributor()],
    this.clock = systemUtcClock,
  });

  final ConferenceRepository conferences;
  final ActivityRepository activities;
  final MediaAssetRepository media;
  final CutRangeRepository cuts;
  final ExportJobRepository jobs;
  final Future<Directory> Function() mediaRoot;

  /// App cache folder; exports use `exports-temp/<job_id>/` in it
  /// (BUILD_GUIDE 9.5).
  final Future<Directory> Function() tempRoot;
  final FreeSpaceProbe freeSpace;
  final int reserveBytes;
  final ExportWriterFunction writer;
  final List<ExportContributor> contributors;
  final UtcClock clock;

  /// Calendar days (conference timezone) that have activities, for the
  /// one-day scope.
  Future<List<DateTime>> activityDays(String conferenceId) async {
    final conference = await _conference(conferenceId);
    final days = <DateTime>{};
    for (final a in await activities.listForConference(conferenceId)) {
      days.add(await _dayOf(a, conference.timezone));
    }
    return days.toList()..sort();
  }

  Future<ExportPlan> plan(ExportRequest request) async {
    final conference = await _conference(request.conferenceId);
    final tz = conference.timezone;
    final types = {for (final t in await activities.types()) t.id: t};
    final all = await activities.listForConference(conference.id);
    final root = await mediaRoot();
    final now = clock();

    // Stable numbering across exports: the activity's place in the whole
    // conference.
    final numbered = <(int, Activity)>[
      for (var i = 0; i < all.length; i++) (i + 1, all[i]),
    ];
    final chosen = <(int, Activity)>[];
    var privateExcluded = 0;
    for (final (n, a) in numbered) {
      final selected = switch (request.selection) {
        WholeConference() => true,
        SelectedActivities(:final activityIds) => activityIds.contains(a.id),
        OneDay(:final day) => await _dayOf(a, tz) == day,
      };
      if (!selected) continue;
      if (a.isPrivate && !request.includePrivate) {
        privateExcluded++;
        continue;
      }
      chosen.add((n, a));
    }

    final rootDate = switch (request.selection) {
      OneDay(:final day) => day,
      _ => conference.startDate ?? toConferenceTime(now, tz),
    };
    final paths = ExportPathAllocator(
      '${_isoDate(rootDate)}_${exportSlug(conference.name, maxLength: 48, fallback: 'conference')}',
    );
    final entries = <ExportEntry>[];
    final exported = <ExportedActivity>[];
    final activityDocs = <(ExportedActivity, int)>[];
    var privateNotes = 0;
    var skipped = 0;
    var tempBytes = 0;
    final mode = request.effectiveAudioMode;

    for (final (n, a) in chosen) {
      final type =
          types[a.typeId] ??
          ActivityType(
            id: a.typeId,
            key: 'activity',
            label: 'Activity',
            icon: 'tag',
            isBuiltin: false,
            sortOrder: 0,
            createdAt: a.createdAt,
            updatedAt: a.updatedAt,
          );
      final segments = await media.segmentsFor(a.id);
      final photos = await media.photosFor(a.id);
      var bookmarks = await media.bookmarksFor(a.id);
      final activeCuts = await cuts.activeFor(a.id);
      final interruptions = await media.interruptionsFor(a.id);
      if (!request.includePrivate) {
        final before = bookmarks.length;
        bookmarks = bookmarks.where((b) => !isPrivateThought(b)).toList();
        privateNotes += before - bookmarks.length;
      }

      final start = segments.isEmpty
          ? (a.actualStart ?? a.plannedStart)
          : segments.first.startUtc;
      final hhmm = start == null
          ? ''
          : '${_two(toConferenceTime(start, tz).hour)}'
                '${_two(toConferenceTime(start, tz).minute)}_';
      final folder = paths.folder(
        'activities',
        '${n.toString().padLeft(3, '0')}_$hhmm'
            '${exportSlug(type.label, maxLength: 16, fallback: 'activity')}_'
            '${exportSlug(a.title, maxLength: 40, fallback: 'untitled')}',
      );

      final activityEntries = <ExportEntry>[];
      final segmentFiles = <String, String>{};
      final segmentNotes = <String, String>{};
      final photoFiles = <String, String>{};
      final trimmedKeep = <String, List<TimeRange>>{};

      // Audio (FR-EXP-03). A file_path two rows share (ADR-036) goes in
      // once per activity.
      if (mode != ExportAudioMode.none) {
        final seen = <String, String>{};
        final playable = <RecordingSegment>[];
        for (final s in segments) {
          if (seen[s.filePath] case final other?) {
            segmentNotes[s.id] = 'same_file_as_segment_$other';
            continue;
          }
          seen[s.filePath] = s.sequence.toString();
          if (s.state == SegmentState.writing) {
            segmentNotes[s.id] = 'still_recording';
            skipped++;
          } else if (s.state == SegmentState.damaged) {
            segmentNotes[s.id] = 'damaged';
            skipped++;
          } else if (!MediaPaths.resolve(root, s.filePath).existsSync()) {
            segmentNotes[s.id] = 'file_missing';
            skipped++;
          } else {
            playable.add(s);
          }
        }
        // Cut offsets count from the activity's first segment (9.4), so
        // the timeline holds every segment, playable or not.
        final timeline = ReviewTimeline.build(segments: segments);
        final trims = <String, SegmentTrimChange>{};
        if (mode == ExportAudioMode.trimmed && activeCuts.isNotEmpty) {
          for (final change in segmentTrimChanges(
            timeline,
            CutRangeMath.mergeOverlappingCutRanges(activeCuts),
          )) {
            trims[change.segment.id] = change;
          }
        }
        for (final s in playable) {
          final file = MediaPaths.resolve(root, s.filePath);
          final size = file.lengthSync();
          final seq = s.sequence.toString().padLeft(3, '0');
          final ext = _ext(s.filePath, '.m4a');
          final trim = trims[s.id];
          if (trim == null) {
            final path = paths.file('$folder/audio', 'segment-$seq$ext');
            segmentFiles[s.id] = _inFolder(path, folder);
            activityEntries.add(
              ExportEntry(
                relativePath: path,
                source: FileExportSource(file.path),
                estimatedBytes: size,
              ),
            );
          } else if (trim.dropped) {
            segmentNotes[s.id] = 'cut';
          } else {
            final path = paths.file(
              '$folder/audio',
              'segment-$seq-trimmed$ext',
            );
            segmentFiles[s.id] = _inFolder(path, folder);
            trimmedKeep[s.id] = trim.keep;
            final duration = trim.segmentDurationMs <= 0
                ? 1
                : trim.segmentDurationMs;
            // Kept share of the file plus room for the new sample tables.
            final estimate = (size * trim.keptMs / duration).ceil() + 64 * 1024;
            final capped = estimate > size + 64 * 1024
                ? size + 64 * 1024
                : estimate;
            if (request.format == ExportFormat.zip && capped > tempBytes) {
              tempBytes = capped;
            }
            activityEntries.add(
              ExportEntry(
                relativePath: path,
                source: TrimmedAudioExportSource(file.path, trim.keep),
                estimatedBytes: capped,
              ),
            );
          }
        }
        if (mode == ExportAudioMode.originalWithCuts && activeCuts.isNotEmpty) {
          // Name each file as it is in the export (relative to the
          // activity folder, where cuts.json sits), not as stored: the
          // export renumbers files by sequence and resolves clashes.
          final manifest = CutsManifest.fromDomain(
            fileNames: segmentFiles,
            activityId: a.id,
            totalDurationMs: timeline.endMs,
            cutRanges: activeCuts,
            segments: [
              for (final s in playable)
                if (segmentFiles.containsKey(s.id)) s,
            ],
            firstSegmentStartUtc: timeline.segments.isEmpty
                ? null
                : timeline.segments.first.segment.startUtc,
          );
          activityEntries.add(
            _text(
              paths.file(folder, 'cuts.json'),
              '${manifest.toPrettyJson()}\n',
            ),
          );
        }
        if (request.includeKeptOriginals) {
          final dir = Directory(
            MediaPaths.resolve(
              root,
              MediaPaths.originalsFolder(conference.id, a.id),
            ).path,
          );
          if (dir.existsSync()) {
            final kept = dir.listSync().whereType<File>().toList()
              ..sort((x, y) => x.path.compareTo(y.path));
            for (final f in kept) {
              activityEntries.add(
                ExportEntry(
                  relativePath: paths.file(
                    '$folder/audio/originals',
                    p.basename(f.path),
                  ),
                  source: FileExportSource(f.path),
                  estimatedBytes: f.lengthSync(),
                ),
              );
            }
          }
        }
      }

      // Photos.
      if (request.content.photos) {
        for (final ph in photos) {
          final file = MediaPaths.resolve(root, ph.filePath);
          if (!file.existsSync()) continue;
          final name =
              '${_photoTime(ph.takenUtc)}_'
              '${exportSlug(ph.label ?? ph.caption, maxLength: 24, fallback: 'photo')}'
              '${_ext(ph.filePath, '.jpg')}';
          final path = paths.file('$folder/photos', name);
          photoFiles[ph.id] = _inFolder(path, folder);
          activityEntries.add(
            ExportEntry(
              relativePath: path,
              source: FileExportSource(file.path),
              estimatedBytes: file.lengthSync(),
            ),
          );
        }
      }

      final item = ExportedActivity(
        activity: a,
        type: type,
        folder: folder,
        segments: segments,
        photos: photos,
        bookmarks: bookmarks,
        cuts: activeCuts,
        interruptions: interruptions,
        files: ActivityExportFiles(
          folder: folder,
          trimmedKeepRanges: trimmedKeep,
          segmentFiles: segmentFiles,
          segmentNotes: segmentNotes,
          photoFiles: photoFiles,
        ),
      );

      // Text and metadata.
      if (request.content.text) {
        var notes = a.notesMd ?? '';
        if (!request.includePrivate) {
          final (kept, removed) = stripPrivateReflections(notes);
          notes = kept;
          privateNotes += removed;
        }
        // Written after the activity's audio, so trimmed copies are
        // described by the files actually written (FR-EXP-06).
        activityEntries.add(
          _activityJsonEntry(
            paths.file(folder, 'activity.json'),
            activity: a,
            type: type,
            timezone: tz,
            audioMode: mode.key,
            segments: segments,
            photos: photos,
            bookmarks: bookmarks,
            cuts: activeCuts,
            interruptions: interruptions,
            files: item.files,
          ),
        );
        if (notes.trim().isNotEmpty ||
            (a.followUpText?.trim().isNotEmpty ?? false)) {
          activityEntries.add(
            _text(
              paths.file(folder, 'notes.md'),
              buildNotesMarkdown(a, notes: notes),
            ),
          );
        }
        if (bookmarks.isNotEmpty) {
          activityEntries.add(
            _text(
              paths.file(folder, 'bookmarks.csv'),
              buildBookmarksCsv(bookmarks, tz),
            ),
          );
        }
      }

      if (activityEntries.isEmpty) continue;
      entries.addAll(activityEntries);
      exported.add(item);
      activityDocs.add((item, entries.length));
    }

    final context = ExportContext(
      conference: conference,
      goals: await conferences.goalsFor(conference.id),
      request: request,
      exportedAtUtc: now,
      activities: exported,
      privateActivitiesExcluded: privateExcluded,
      privateNotesExcluded: privateNotes,
    );
    // Contributor files for each activity go after its own files.
    if (request.content.text) {
      for (final (item, end) in activityDocs.reversed) {
        final extra = [
          for (final c in contributors)
            for (final doc in c.activityDocuments(context, item))
              _text(_docPath(paths, item.folder, doc.path), doc.text),
        ];
        entries.insertAll(end, extra);
      }
    }
    final rootEntries = [
      for (final c in contributors)
        for (final doc in c.rootDocuments(context))
          _text(_docPath(paths, '', doc.path), doc.text),
    ];

    return ExportPlan(
      request: request,
      rootName: paths.root,
      entries: [...rootEntries, ...entries],
      activityCount: exported.length,
      privateActivitiesExcluded: privateExcluded,
      privateNotesExcluded: privateNotes,
      segmentsSkipped: skipped,
      tempBytes: tempBytes,
    );
  }

  /// [plan] plus the free-space check on [destinationParent] and the temp
  /// folder (FR-EXP-05).
  Future<ExportPreflightReport> preflight(
    ExportRequest request,
    String destinationParent,
  ) async => _preflight(await plan(request), destinationParent);

  Future<ExportPreflightReport> _preflight(
    ExportPlan plan,
    String destinationParent,
  ) async {
    // The temp folder may share the destination's volume, so count it
    // there too: safe, at worst a little cautious.
    final destination = await preflightExport(
      requiredBytes: plan.destinationBytes + plan.tempBytes,
      destination: destinationParent,
      probe: freeSpace,
      reserveBytes: reserveBytes,
    );
    ExportPreflight? temp;
    if (plan.tempBytes > 0) {
      temp = await preflightExport(
        requiredBytes: plan.tempBytes,
        destination: (await tempRoot()).path,
        probe: freeSpace,
        reserveBytes: reserveBytes,
      );
    }
    return ExportPreflightReport(
      plan: plan,
      destination: destination,
      temp: temp,
    );
  }

  /// Writes the export into [destinationParent]. Throws
  /// [InsufficientSpaceException] before writing anything when space is
  /// short, [ExportCancelledException] when [cancel] completes first, and
  /// [ExportException] when there is nothing to export. On any failure
  /// the partial export is removed and sources are untouched (FR-EXP-05).
  ///
  /// One export at a time: while one runs, another call throws
  /// [ExportException] before doing anything (ADR-040).
  Future<ExportOutcome> run(
    ExportRequest request, {
    required String destinationParent,
    void Function(ExportWriteProgress progress)? onProgress,
    Future<void>? cancel,
  }) async {
    if (_busy) {
      throw const ExportException(
        'An export is already running. Wait for it to finish, then try '
        'again.',
      );
    }
    _busy = true;
    try {
      return await _run(
        request,
        destinationParent: destinationParent,
        onProgress: onProgress,
        cancel: cancel,
      );
    } finally {
      _busy = false;
    }
  }

  var _busy = false;

  /// Whether an export is being written now.
  bool get isRunning => _busy;

  Future<ExportOutcome> _run(
    ExportRequest request, {
    required String destinationParent,
    void Function(ExportWriteProgress progress)? onProgress,
    Future<void>? cancel,
  }) async {
    // Taken before planning reads anything: a change at or after it may
    // be missing from this export (Storage Manager, ADR-047).
    final snapshotAt = clock();
    final plan = await this.plan(request);
    if (plan.activityCount == 0) {
      throw ExportException(
        plan.privateActivitiesExcluded > 0
            ? 'Nothing to export: the chosen activities are private. Turn on '
                  '"Include private items" to export them.'
            : 'Nothing to export for this choice.',
      );
    }
    final job = await jobs.create(
      conferenceId: request.conferenceId,
      scope: {
        ...request.toScopeJson(),
        'snapshot_at': snapshotAt.toIso8601String(),
      },
      format: request.format,
      audioMode: request.effectiveAudioMode,
      bytesTotal: plan.contentBytes,
    );
    final report = await _preflight(plan, destinationParent);
    if (report.insufficient) {
      await jobs.fail(job.id, 'insufficient_space');
      throw InsufficientSpaceException(
        report.destination.status == PreflightStatus.insufficient
            ? report.destination
            : report.temp!,
      );
    }

    final writePlan = ExportWritePlan(
      format: request.format,
      destinationParent: destinationParent,
      rootName: _uniqueRoot(destinationParent, plan.rootName, request.format),
      entries: plan.entries,
      tempDirectory: p.join((await tempRoot()).path, 'exports-temp', job.id),
    );
    await jobs.markRunning(job.id);
    var lastReported = 0;
    try {
      final result = await writer(
        writePlan,
        cancel: cancel,
        onProgress: (progress) {
          onProgress?.call(progress);
          // One database write per file is plenty.
          if (progress.bytesDone != lastReported) {
            lastReported = progress.bytesDone;
            unawaited(jobs.reportProgress(job.id, progress.bytesDone));
          }
        },
      );
      final verification = request.format == ExportFormat.folder
          ? VerificationLevel.checksum
          : VerificationLevel.none;
      await jobs.reportProgress(job.id, result.totalBytes);
      await jobs.complete(job.id, verification);
      return ExportOutcome(
        jobId: job.id,
        outputPath: result.outputPath,
        fileCount: result.files.length,
        bytes: result.totalBytes,
        verification: verification,
      );
    } on ExportCancelledException {
      await jobs.cancel(job.id);
      rethrow;
    } catch (error) {
      // No paths or names: they can hold personal data.
      await jobs.fail(job.id, switch (error) {
        ExportOutOfSpaceException() => 'out_of_space',
        FileSystemException() => 'file_system_error',
        _ => error.runtimeType.toString(),
      });
      rethrow;
    }
  }

  Future<Conference> _conference(String id) async {
    final conference = await conferences.get(id);
    if (conference == null) {
      throw const ExportException('This conference no longer exists.');
    }
    return conference;
  }

  Future<DateTime> _dayOf(Activity a, String tz) async {
    final first = await media.firstSegmentStart(a.id);
    final at = first ?? a.actualStart ?? a.plannedStart ?? a.createdAt;
    final local = toConferenceTime(at, tz);
    return DateTime.utc(local.year, local.month, local.day);
  }
}

/// `activity.json` built while writing, from the files written before it.
/// A top-level function so the closure captures only these plain values
/// and can cross to the export isolate.
ExportEntry _activityJsonEntry(
  String path, {
  required Activity activity,
  required ActivityType type,
  required String timezone,
  required String audioMode,
  required List<RecordingSegment> segments,
  required List<Photo> photos,
  required List<Bookmark> bookmarks,
  required List<CutRange> cuts,
  required List<Interruption> interruptions,
  required ActivityExportFiles files,
}) {
  String build(Map<String, ExportedFile> written) => buildActivityJson(
    activity: activity,
    type: type,
    timezone: timezone,
    audioMode: audioMode,
    segments: segments,
    photos: photos,
    bookmarks: bookmarks,
    cuts: cuts,
    interruptions: interruptions,
    files: files,
    written: written,
  );
  // Real sizes and hashes are a little longer than placeholders.
  final estimate = utf8.encode(build(const {})).length + 160 * segments.length;
  return ExportEntry(
    relativePath: path,
    source: GeneratedTextExportSource(build),
    estimatedBytes: estimate,
  );
}

ExportEntry _text(String path, String text) {
  final source = TextExportSource(text);
  return ExportEntry(
    relativePath: path,
    source: source,
    estimatedBytes: source.bytes.length,
  );
}

/// A contributor path like `prompts/blog_draft.md`, made safe.
String _docPath(ExportPathAllocator paths, String base, String path) {
  final parts = path.split('/');
  var folder = base;
  for (final part in parts.take(parts.length - 1)) {
    final safe = safeExportComponent(
      part,
      maxLength: maxExportFolderNameLength,
    );
    folder = folder.isEmpty ? safe : '$folder/$safe';
  }
  return paths.file(folder, parts.last);
}

String _uniqueRoot(String parent, String root, ExportFormat format) {
  bool taken(String name) {
    for (final candidate in [
      p.join(parent, name),
      p.join(parent, '$name.partial'),
      p.join(parent, '$name.zip'),
      p.join(parent, '$name.zip.partial'),
    ]) {
      if (FileSystemEntity.typeSync(candidate) !=
          FileSystemEntityType.notFound) {
        return true;
      }
    }
    return false;
  }

  if (!taken(root)) return root;
  for (var n = 2; ; n++) {
    final suffix = '-$n';
    final base = root.length + suffix.length > maxExportFolderNameLength
        ? root.substring(0, maxExportFolderNameLength - suffix.length)
        : root;
    final name = '$base$suffix';
    if (!taken(name)) return name;
  }
}

String _inFolder(String path, String folder) =>
    path.substring(folder.length + 1);

String _ext(String path, String fallback) {
  final ext = p.posix.extension(path).toLowerCase();
  return ext.isEmpty ? fallback : ext;
}

String _two(int v) => v.toString().padLeft(2, '0');

String _isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${_two(d.month)}-${_two(d.day)}';

/// `2026-11-04T09-44-21Z`: UTC, no colons (FR-EXP-07, BUILD_GUIDE 5.10).
String _photoTime(DateTime t) {
  final u = t.toUtc();
  return '${_isoDate(u)}T${_two(u.hour)}-${_two(u.minute)}-${_two(u.second)}Z';
}

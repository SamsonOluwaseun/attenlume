/// Re-import of an Attenlume export as a conference (FR-EXP-11, ADR-049)
/// [P1-23].
///
/// Two steps, so the user sees what will happen before anything changes:
///
/// 1. [ExportImportService.prepare] copies the export (folder or ZIP) into
///    a staging folder next to the media folder, checks every copy against
///    `checksums.sha256` and reads `conference.json`, each `activity.json`,
///    `notes.md`, `bookmarks.csv`, `cuts.json` and `timeline.csv` into an
///    [ImportPreview]. Nothing in the app changes.
/// 2. [ExportImportService.commit] moves the checked copies into the media
///    layout (rename on the same volume, so each file appears whole) and
///    adds the rows in one transaction. An existing conference is never
///    changed: when its ID (or any activity, recording, photo or bookmark
///    ID) is already in the app, everything gets new IDs and the
///    conference is named "... (imported copy)".
///
/// A trimmed-copy export imports the trimmed files as the recordings and
/// no cut ranges (the cuts are already applied). Originals, with or
/// without `cuts.json`, restore the cut ranges. Offsets follow the 9.4
/// rule from the first imported recording.
library;

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value, Variable;
import 'package:path/path.dart' as p;

import '../../data/filesystem/export_import_source.dart';
import '../../data/filesystem/export_space.dart';
import '../../data/filesystem/folder_export.dart';
import '../../data/filesystem/m4a_inspector.dart';
import '../../data/filesystem/media_paths.dart';
import '../../data/local_database/app_database.dart';
import '../../data/repositories/activity_repository.dart';
import '../../data/repositories/repository_support.dart';
import '../../data/repositories/settings_repository.dart';
import '../../platform/storage/free_space_probe.dart';
import '../models/enums.dart';
import 'export_documents.dart' show exportSchemaVersion;
import 'timeline_offset.dart';

/// Where the import is.
enum ImportPhase { checking, importing }

class ImportProgress {
  const ImportProgress(this.phase, this.done, this.total);

  final ImportPhase phase;

  /// Bytes while checking, files while importing.
  final int done;
  final int total;

  double? get fraction => total <= 0 ? null : done / total;
}

/// One activity as the preview shows it.
class ImportActivityPreview {
  const ImportActivityPreview({
    required this.title,
    required this.typeLabel,
    required this.isPrivate,
    required this.segments,
    required this.photos,
    required this.bookmarks,
    required this.hasNotes,
    required this.cuts,
    required this.bytes,
  });

  final String title;
  final String typeLabel;
  final bool isPrivate;
  final int segments;
  final int photos;
  final int bookmarks;
  final bool hasNotes;
  final int cuts;
  final int bytes;
}

/// What an export holds and whether it passed the checksum check.
class ImportPreview {
  const ImportPreview({
    required this.sourcePath,
    required this.isZip,
    required this.conferenceId,
    required this.conferenceName,
    required this.schemaVersion,
    required this.content,
    required this.audioMode,
    required this.activities,
    required this.totalBytes,
    required this.fileCount,
    required this.check,
    required this.alreadyExists,
    this.warnings = const [],
  });

  final String sourcePath;
  final bool isZip;
  final String conferenceId;
  final String conferenceName;
  final int schemaVersion;

  /// `everything`, `audio_only`, `photos_only`, `text_only`, or empty when
  /// the export does not say.
  final String content;

  /// `original`, `trimmed`, `original_with_cuts` or `none`.
  final String audioMode;
  final List<ImportActivityPreview> activities;
  final int totalBytes;
  final int fileCount;
  final ChecksumCheck check;

  /// The conference (or one of its items) is already in the app, so it
  /// will be imported as a copy with new IDs.
  final bool alreadyExists;
  final List<String> warnings;

  /// Only an export whose every listed file matches can be imported.
  bool get canImport => check.ok;
}

/// What an import added.
class ImportSummary {
  const ImportSummary({
    required this.conferenceId,
    required this.conferenceName,
    required this.asCopy,
    required this.activities,
    required this.segments,
    required this.photos,
    required this.bookmarks,
    required this.notes,
    required this.cuts,
    required this.bytes,
    this.warnings = const [],
  });

  final String conferenceId;
  final String conferenceName;
  final bool asCopy;
  final int activities;
  final int segments;
  final int photos;
  final int bookmarks;
  final int notes;
  final int cuts;
  final int bytes;
  final List<String> warnings;
}

/// A checked, staged export waiting for [ExportImportService.commit] or
/// [ExportImportService.discard].
class PreparedImport {
  PreparedImport._(this.preview, this._staged, this._conference);

  final ImportPreview preview;
  final StagedExport _staged;
  final _Conf _conference;
  bool _finished = false;
}

/// Re-import of exports (FR-EXP-11). One per app; it refuses a second
/// import while one runs.
class ExportImportService {
  ExportImportService({
    required this.db,
    required this.activities,
    required this.mediaRoot,
    required this.freeSpace,
    this._stagingRoot,
    this.reserveBytes = defaultExportReserveBytes,
    this._clock = systemUtcClock,
    this._newId = uuidV4,
  });

  final AppDatabase db;
  final ActivityRepository activities;
  final Future<Directory> Function() mediaRoot;
  final FreeSpaceProbe freeSpace;
  final int reserveBytes;
  final Future<Directory> Function()? _stagingRoot;
  final UtcClock _clock;
  final IdGenerator _newId;
  bool _busy = false;

  /// `<app data>/imports-temp/`: next to `media/`, so the final move is a
  /// rename on the same volume. Holds copies only.
  Future<Directory> _staging() async {
    if (_stagingRoot != null) return _stagingRoot();
    final media = await mediaRoot();
    return Directory(p.join(media.parent.path, 'imports-temp'));
  }

  /// Copies and checks the export at [path] and reads what it holds.
  /// Nothing in the app changes. Throws [ExportImportException] with a
  /// message for the user when the export cannot be read.
  Future<PreparedImport> prepare(
    String path, {
    void Function(ImportProgress progress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    if (_busy) {
      throw const ExportImportException(
        'An import is already running. Wait for it to finish.',
      );
    }
    _busy = true;
    Directory? staging;
    try {
      final source = await ExportImportSource.open(path);
      final root = await _staging();
      // Leftovers from an earlier import hold copies only.
      if (root.existsSync()) {
        try {
          await root.delete(recursive: true);
        } on FileSystemException {
          // Not fatal: a new subfolder is used below.
        }
      }
      final media = await mediaRoot();
      final space = await preflightExport(
        requiredBytes: source.totalBytes,
        destination: media.path,
        probe: freeSpace,
        reserveBytes: reserveBytes,
      );
      if (space.status == PreflightStatus.insufficient) {
        throw ExportImportException(
          'Not enough free space to import this export. It needs '
          '${_mb(source.totalBytes + reserveBytes)} including a safety '
          'margin; ${_mb(space.availableBytes ?? 0)} is free.',
        );
      }
      staging = Directory(p.join(root.path, _newId()));
      final staged = await source.stage(
        staging,
        isCancelled: isCancelled,
        onProgress: (done, total) =>
            onProgress?.call(ImportProgress(ImportPhase.checking, done, total)),
      );
      final conf = await _Reader(staged, _clock()).read();
      final exists = await _anyIdExists(conf);
      final preview = ImportPreview(
        sourcePath: path,
        isZip: source.isZip,
        conferenceId: conf.id,
        conferenceName: conf.name,
        schemaVersion: conf.schema,
        content: conf.content,
        audioMode: conf.audioMode,
        activities: [
          for (final a in conf.activities)
            ImportActivityPreview(
              title: a.title,
              typeLabel: a.typeLabel,
              isPrivate: a.isPrivate,
              segments: a.segments.length,
              photos: a.photos.length,
              bookmarks: a.bookmarks.length,
              hasNotes: a.hasNotes,
              cuts: a.cuts.length,
              bytes: [
                for (final s in a.segments) staged.sizes[s.file] ?? 0,
                for (final ph in a.photos) staged.sizes[ph.file] ?? 0,
              ].fold(0, (n, b) => n + b),
            ),
        ],
        totalBytes: source.totalBytes,
        fileCount: source.members.length,
        check: staged.check,
        alreadyExists: exists,
        warnings: conf.warnings,
      );
      final prepared = PreparedImport._(preview, staged, conf);
      staging = null; // Kept for commit or discard.
      return prepared;
    } finally {
      _busy = false;
      if (staging != null && staging.existsSync()) {
        try {
          await staging.delete(recursive: true);
        } on FileSystemException {
          // Copies only; cleared on the next import.
        }
      }
    }
  }

  /// Removes the staged copies. The export itself is never touched.
  Future<void> discard(PreparedImport prepared) async {
    prepared._finished = true;
    final dir = prepared._staged.folder;
    if (dir.existsSync()) {
      try {
        await dir.delete(recursive: true);
      } on FileSystemException {
        // Copies only; cleared on the next import.
      }
    }
  }

  /// Imports a checked export. Refuses one that failed the checksum check.
  /// [asCopy] gives everything new IDs even when the conference is not in
  /// the app; an existing conference is always imported as a copy.
  Future<ImportSummary> commit(
    PreparedImport prepared, {
    bool asCopy = false,
    void Function(ImportProgress progress)? onProgress,
  }) async {
    if (prepared._finished) {
      throw StateError('This import has already finished.');
    }
    if (!prepared.preview.canImport) {
      throw const ExportImportException(
        'Some files do not match checksums.sha256, so nothing was imported.',
      );
    }
    if (_busy) {
      throw const ExportImportException(
        'An import is already running. Wait for it to finish.',
      );
    }
    _busy = true;
    try {
      final conf = prepared._conference;
      final staged = prepared._staged;
      final copy = asCopy || await _anyIdExists(conf);
      String idFor(String? old) => (copy || old == null) ? _newId() : old;

      final root = await mediaRoot();
      final now = _clock();
      final conferenceId = idFor(conf.id);
      final name = copy ? '${conf.name} (imported copy)' : conf.name;
      final profile = await SettingsRepository(db)
          .globalDefaultRecordingProfile();

      // Types first: a custom type the app does not have is added.
      final typeIds = <_Act, String>{};
      for (final a in conf.activities) {
        typeIds[a] = await _typeFor(a);
      }

      // Work out every row and file before touching anything.
      final moves = <(File, File)>[];
      final taken = <String>{};
      File free(String rel, String Function(int attempt) nameFor) {
        for (var attempt = 0; ; attempt++) {
          final candidate = attempt == 0 ? rel : nameFor(attempt);
          final file = MediaPaths.resolve(root, candidate);
          if (!file.existsSync() && taken.add(candidate)) return file;
        }
      }

      final activityRows = <ActivitiesCompanion>[];
      final segmentRows = <RecordingSegmentsCompanion>[];
      final photoRows = <PhotosCompanion>[];
      final bookmarkRows = <BookmarksCompanion>[];
      final interruptionRows = <InterruptionsCompanion>[];
      final cutRows = <CutRangesCompanion>[];
      var bytes = 0;
      var notes = 0;
      final warnings = [...conf.warnings];

      for (var i = 0; i < conf.activities.length; i++) {
        final a = conf.activities[i];
        final activityId = idFor(a.id);
        // Keeps the export's order for activities with no start time.
        final created = now.add(Duration(milliseconds: i));
        final segments = [...a.segments]
          ..sort((x, y) => x.start.compareTo(y.start));
        final firstStart = segments.isEmpty ? null : segments.first.start;
        int? offsetOf(DateTime t) =>
            timelineOffsetMs(eventUtc: t, firstSegmentStartUtc: firstStart);
        final hasNotes =
            a.notes.trim().isNotEmpty ||
            (a.followUp?.trim().isNotEmpty ?? false);
        if (hasNotes) notes++;

        activityRows.add(
          ActivitiesCompanion.insert(
            id: activityId,
            conferenceId: conferenceId,
            typeId: typeIds[a]!,
            title: a.title,
            speakerNames: a.speakers,
            organisation: Value(a.organisation),
            room: Value(a.room),
            notesMd: Value(a.notes.trim().isEmpty ? null : a.notes),
            tags: a.tags,
            plannedStart: Value(a.plannedStart),
            actualStart: Value(a.actualStart ?? firstStart),
            actualEnd: Value(a.actualEnd),
            status: a.status,
            recordingPermissionStatus: a.permission,
            isPrivate: a.isPrivate,
            followUpText: Value(a.followUp),
            createdAt: created,
            updatedAt: created,
          ),
        );

        for (var n = 0; n < segments.length; n++) {
          final s = segments[n];
          final sequence = n + 1;
          final ext = p.posix.extension(s.file).toLowerCase();
          String pathFor(int attempt) {
            final rel = MediaPaths.segment(
              conferenceId,
              activityId,
              sequence,
              attempt: attempt,
            );
            return ext == '.m4a' || ext.isEmpty
                ? rel
                : '${p.posix.withoutExtension(rel)}$ext';
          }

          final target = free(pathFor(0), pathFor);
          moves.add((staged.file(s.file), target));
          final size = staged.sizes[s.file]!;
          bytes += size;
          segmentRows.add(
            RecordingSegmentsCompanion.insert(
              id: idFor(s.id),
              activityId: activityId,
              sequence: sequence,
              filePath: _relative(root, target),
              state: s.state,
              requestedProfile: s.profile,
              codec: s.codec,
              container: s.container,
              channelCount: s.channels,
              sampleRateHz: s.sampleRate,
              requestedBitrateBps: s.requestedBitrate,
              observedBitrateBps: Value(s.observedBitrate),
              inputRoute: Value(s.inputRoute),
              startUtc: s.start,
              endUtc: Value(s.end),
              durationMs: Value(s.durationMs),
              bytes: Value(size),
              sha256: Value(staged.hashes[s.file]),
              endReason: Value(s.endReason),
              createdAt: now,
              updatedAt: now,
            ),
          );
        }

        for (final ph in a.photos) {
          final photoId = idFor(ph.id);
          final ext = p.posix.extension(ph.file).toLowerCase();
          String pathFor(int attempt) {
            final rel = MediaPaths.photo(conferenceId, activityId, photoId);
            final stem = p.posix.withoutExtension(rel);
            return '$stem${attempt == 0 ? '' : '-${attempt + 1}'}'
                '${ext.isEmpty ? '.jpg' : ext}';
          }

          final target = free(pathFor(0), pathFor);
          moves.add((staged.file(ph.file), target));
          final size = staged.sizes[ph.file]!;
          bytes += size;
          photoRows.add(
            PhotosCompanion.insert(
              id: photoId,
              activityId: activityId,
              filePath: _relative(root, target),
              takenUtc: ph.taken,
              offsetMs: Value(offsetOf(ph.taken)),
              caption: Value(ph.caption),
              label: Value(ph.label),
              source: ph.source,
              width: Value(ph.width),
              height: Value(ph.height),
              bytes: Value(size),
              sha256: Value(staged.hashes[ph.file]),
              originalKept: false,
              createdAt: now,
              updatedAt: now,
            ),
          );
        }

        for (final b in a.bookmarks) {
          bookmarkRows.add(
            BookmarksCompanion.insert(
              id: idFor(b.id),
              activityId: activityId,
              atUtc: b.at,
              offsetMs: Value(offsetOf(b.at)),
              label: Value(b.label),
              note: Value(b.note),
              source: b.source,
              createdAt: now,
              updatedAt: now,
            ),
          );
        }

        for (final gap in a.interruptions) {
          interruptionRows.add(
            InterruptionsCompanion.insert(
              id: _newId(),
              activityId: activityId,
              reason: gap.reason,
              startUtc: gap.start,
              endUtc: Value(gap.end),
              autoResumed: gap.autoResumed,
              createdAt: now,
              updatedAt: now,
            ),
          );
        }

        // Cut offsets count from the first recording of the export's
        // activity; move them to the first imported one (9.4 rule).
        if (firstStart != null && a.cuts.isNotEmpty) {
          final shift = a.cutsOrigin == null
              ? 0
              : firstStart.difference(a.cutsOrigin!).inMilliseconds;
          var dropped = 0;
          for (final c in a.cuts) {
            final start = c.start - shift < 0 ? 0 : c.start - shift;
            final end = c.end - shift;
            if (end <= start) {
              dropped++;
              continue;
            }
            cutRows.add(
              CutRangesCompanion.insert(
                id: _newId(),
                activityId: activityId,
                startOffsetMs: start,
                endOffsetMs: end,
                reason: Value(c.reason),
                createdAt: now,
                updatedAt: now,
              ),
            );
          }
          if (dropped > 0) {
            warnings.add(
              '"${a.title}": $dropped cut ${dropped == 1 ? 'range was' : 'ranges were'} '
              'before the first imported recording and left out.',
            );
          }
        }
      }

      // Files first, each by one rename, so no half-written file appears
      // in the media folder. Undone if the rows cannot be added.
      final moved = <(File, File)>[];
      try {
        for (var i = 0; i < moves.length; i++) {
          final (from, to) = moves[i];
          await to.parent.create(recursive: true);
          await _move(from, to, staged.hashes[_stagedRel(staged, from)]);
          moved.add((from, to));
          onProgress?.call(
            ImportProgress(ImportPhase.importing, i + 1, moves.length),
          );
        }
        await db.transaction(() async {
          await db
              .into(db.conferences)
              .insert(
                ConferencesCompanion.insert(
                  id: conferenceId,
                  name: name,
                  venue: Value(conf.venue),
                  startDate: Value(conf.startDate),
                  endDate: Value(conf.endDate),
                  timezone: conf.timezone,
                  roleType: Value(conf.roleType),
                  roleText: Value(conf.roleText),
                  requestedOutputs: conf.outputs,
                  defaultRecordingProfile: profile,
                  createdAt: now,
                  updatedAt: now,
                ),
              );
          for (var g = 0; g < conf.goals.length; g++) {
            await db
                .into(db.goals)
                .insert(
                  GoalsCompanion.insert(
                    id: _newId(),
                    conferenceId: conferenceId,
                    goalText: conf.goals[g].$1,
                    priority: Value(conf.goals[g].$2),
                    sortOrder: g,
                    createdAt: now,
                    updatedAt: now,
                  ),
                );
          }
          for (final r in activityRows) {
            await db.into(db.activities).insert(r);
          }
          for (final r in segmentRows) {
            await db.into(db.recordingSegments).insert(r);
          }
          for (final r in photoRows) {
            await db.into(db.photos).insert(r);
          }
          for (final r in bookmarkRows) {
            await db.into(db.bookmarks).insert(r);
          }
          for (final r in interruptionRows) {
            await db.into(db.interruptions).insert(r);
          }
          for (final r in cutRows) {
            await db.into(db.cutRanges).insert(r);
          }
        });
      } catch (_) {
        for (final (from, to) in moved.reversed) {
          try {
            await to.rename(from.path);
          } on FileSystemException {
            // The export still holds the original.
          }
        }
        rethrow;
      }

      await discard(prepared);
      return ImportSummary(
        conferenceId: conferenceId,
        conferenceName: name,
        asCopy: copy,
        activities: activityRows.length,
        segments: segmentRows.length,
        photos: photoRows.length,
        bookmarks: bookmarkRows.length,
        notes: notes,
        cuts: cutRows.length,
        bytes: bytes,
        warnings: warnings,
      );
    } finally {
      _busy = false;
    }
  }

  String _stagedRel(StagedExport staged, File file) =>
      p.posix.joinAll(p.split(p.relative(file.path, from: staged.folder.path)));

  /// Renames [from] to [to]; if they are on different volumes, copies
  /// through a temporary name and checks the copy's hash.
  Future<void> _move(File from, File to, String? sha256) async {
    if (to.existsSync()) {
      throw const ExportImportException(
        'A file the import needs is already there; nothing was overwritten.',
      );
    }
    try {
      await from.rename(to.path);
    } on FileSystemException {
      final (_, hash) = await copyFileHashing(from, to);
      if (sha256 != null && hash != sha256) {
        await to.delete();
        throw const ExportImportException(
          'A file changed while it was being imported. Nothing was imported.',
        );
      }
      await from.delete();
    }
  }

  static String _relative(Directory root, File file) =>
      p.posix.joinAll(p.split(p.relative(file.path, from: root.path)));

  Future<String> _typeFor(_Act a) async {
    final byKey = await activities.typeByKey(a.typeKey);
    if (byKey != null) return byKey.id;
    final label = a.typeLabel.trim().isEmpty ? 'Activity' : a.typeLabel.trim();
    for (final t in await activities.types()) {
      if (t.label.toLowerCase() == label.toLowerCase()) return t.id;
    }
    return (await activities.createCustomType(label)).id;
  }

  Future<bool> _anyIdExists(_Conf conf) async {
    Future<bool> any(String table, Iterable<String?> ids) async {
      final list = ids.whereType<String>().toList();
      if (list.isEmpty) return false;
      for (var i = 0; i < list.length; i += 500) {
        final chunk = list.sublist(
          i,
          i + 500 > list.length ? list.length : i + 500,
        );
        final marks = List.filled(chunk.length, '?').join(',');
        final row = await db
            .customSelect(
              'SELECT COUNT(*) AS c FROM $table WHERE id IN ($marks)',
              variables: [for (final id in chunk) Variable<String>(id)],
            )
            .getSingle();
        if (row.read<int>('c') > 0) return true;
      }
      return false;
    }

    return await any('conferences', [conf.id]) ||
        await any('activities', conf.activities.map((a) => a.id)) ||
        await any('recording_segments', [
          for (final a in conf.activities) ...a.segments.map((s) => s.id),
        ]) ||
        await any('photos', [
          for (final a in conf.activities) ...a.photos.map((ph) => ph.id),
        ]) ||
        await any('bookmarks', [
          for (final a in conf.activities) ...a.bookmarks.map((b) => b.id),
        ]);
  }
}

String _mb(int bytes) => '${(bytes / (1024 * 1024)).ceil()} MB';

// ---------------------------------------------------------------------------
// What the export holds, read from the staged copy.

class _Conf {
  _Conf();

  late String id;
  late String name;
  int schema = 1;
  String? venue;
  DateTime? startDate;
  DateTime? endDate;
  String timezone = 'UTC';
  RoleType? roleType;
  String? roleText;
  final goals = <(String, int?)>[];
  final outputs = <RequestedOutput>[];
  String content = '';
  String audioMode = '';
  DateTime? exportedAt;
  final activities = <_Act>[];
  final warnings = <String>[];
}

class _Act {
  String? id;
  String title = 'Untitled';
  String typeKey = 'session';
  String typeLabel = 'Session';
  List<String> speakers = const [];
  String? organisation;
  String? room;
  List<String> tags = const [];
  ActivityStatus status = ActivityStatus.completed;
  RecordingPermissionStatus permission = RecordingPermissionStatus.unknown;
  bool isPrivate = false;
  DateTime? plannedStart;
  DateTime? actualStart;
  DateTime? actualEnd;
  String notes = '';
  String? followUp;
  final segments = <_Seg>[];
  final photos = <_Pho>[];
  final bookmarks = <_Bm>[];
  final interruptions = <_Gap>[];
  final cuts = <_Cut>[];

  /// Start of the export's first recording, which the cut offsets count
  /// from.
  DateTime? cutsOrigin;

  bool get hasNotes =>
      notes.trim().isNotEmpty || (followUp?.trim().isNotEmpty ?? false);
}

class _Seg {
  String? id;

  /// Path from the export root.
  late String file;
  late DateTime start;
  DateTime? end;
  int? durationMs;
  SegmentState state = SegmentState.finalised;
  RecordingProfile profile = RecordingProfile.balanced;
  String codec = 'aac_lc';
  String container = 'm4a';
  int channels = 1;
  int sampleRate = 48000;
  int requestedBitrate = RecordingProfile.balanced.targetBitrateBps;
  int? observedBitrate;
  String? inputRoute;
  SegmentEndReason? endReason;
}

class _Pho {
  String? id;
  late String file;
  late DateTime taken;
  String? caption;
  String? label;
  PhotoSource source = PhotoSource.inApp;
  int? width;
  int? height;
}

class _Bm {
  String? id;
  late DateTime at;
  String? label;
  String? note;
  BookmarkSource source = BookmarkSource.ui;
}

class _Gap {
  InterruptionReason reason = InterruptionReason.system;
  late DateTime start;
  DateTime? end;
  bool autoResumed = false;
}

class _Cut {
  _Cut(this.start, this.end, this.reason);

  final int start;
  final int end;
  final String? reason;
}

/// Reads the staged export into [_Conf]. Only files that passed the
/// checksum check are used.
class _Reader {
  _Reader(this.staged, this.now);

  final StagedExport staged;
  final DateTime now;

  bool has(String rel) => staged.hashes.containsKey(rel);

  Future<String> text(String rel) => staged.file(rel).readAsString();

  Future<Map<String, Object?>> json(String rel) async {
    try {
      final value = jsonDecode(await text(rel));
      if (value is Map<String, Object?>) return value;
    } on FormatException {
      // Reported below.
    }
    throw ExportImportException('$rel could not be read.');
  }

  Future<_Conf> read() async {
    if (!has('conference.json')) {
      throw const ExportImportException(
        'conference.json is not in the checksum list, so the export cannot '
        'be trusted.',
      );
    }
    final c = await json('conference.json');
    final conf = _Conf();
    conf.schema = _int(c['schema_version']) ?? 1;
    if (conf.schema > exportSchemaVersion) {
      throw const ExportImportException(
        'This export was made by a newer version of Attenlume. Update the '
        'app, then import it again.',
      );
    }
    final id = _str(c['id']);
    final name = _str(c['name']) ?? _str(c['title']);
    if (id == null || name == null || name.trim().isEmpty) {
      throw const ExportImportException(
        'conference.json does not name a conference.',
      );
    }
    conf
      ..id = id
      ..name = name.trim()
      ..venue = _str(c['venue'])
      ..startDate = _date(c['start_date'])
      ..endDate = _date(c['end_date'])
      ..timezone = _str(c['timezone']) ?? 'UTC'
      ..roleType = _enum(RoleType.values, c['role_type'])
      ..roleText = _str(c['role_text'])
      ..exportedAt = _time(c['exported_at_utc']);
    for (final g in _list(c['goals'])) {
      if (g is! Map) continue;
      final text = _str(g['text']);
      if (text == null || text.trim().isEmpty) continue;
      final priority = _int(g['priority']);
      conf.goals.add((
        text,
        priority != null && priority >= 1 && priority <= 3 ? priority : null,
      ));
    }
    for (final o in _list(c['requested_outputs'])) {
      final value = _enum(RequestedOutput.values, o);
      if (value != null) conf.outputs.add(value);
    }
    final scope = c['scope'];
    if (scope is Map) {
      conf
        ..content = _str(scope['content']) ?? ''
        ..audioMode = _str(scope['audio_mode']) ?? '';
    }

    final timeline = has('timeline.csv')
        ? _timelineRows(await text('timeline.csv'))
        : const <Map<String, String>>[];

    for (final entry in _list(c['activities'])) {
      if (entry is! Map) continue;
      final folder = _str(entry['folder']);
      if (folder == null || !isSafeRelativePath(folder)) continue;
      final a = _Act()
        ..id = _str(entry['id'])
        ..title = _str(entry['title']) ?? 'Untitled'
        ..typeKey = _str(entry['type']) ?? ''
        ..typeLabel = _str(entry['type_label']) ?? ''
        ..isPrivate = entry['is_private'] == true
        ..actualStart = _time(entry['start_utc']);
      if (a.typeKey.isEmpty) _typeFromFolder(a, folder);

      if (has('$folder/activity.json')) {
        await _fromActivityJson(conf, a, folder);
      } else if (timeline.isNotEmpty) {
        await _fromTimeline(a, folder, timeline);
      } else {
        await _fromFiles(conf, a, folder);
      }

      if (has('$folder/notes.md')) {
        final (notes, followUp) = parseNotesMarkdown(
          await text('$folder/notes.md'),
        );
        a
          ..notes = notes
          ..followUp = followUp;
      }
      // Originals with cuts.json but no activity.json (audio only).
      if (a.cuts.isEmpty &&
          conf.audioMode != 'trimmed' &&
          has('$folder/cuts.json')) {
        final cuts = await json('$folder/cuts.json');
        for (final cut in _list(cuts['cuts'])) {
          if (cut is! Map) continue;
          final s = _int(cut['start_ms']);
          final e = _int(cut['end_ms']);
          if (s == null || e == null || e <= s) continue;
          a.cuts.add(_Cut(s, e, _str(cut['reason'])));
        }
      }
      if (conf.audioMode == 'trimmed') a.cuts.clear();
      conf.activities.add(a);
    }
    if (conf.audioMode == 'trimmed' &&
        conf.activities.any((a) => a.segments.isNotEmpty)) {
      conf.warnings.add(
        'This export holds trimmed copies, so they are imported as the '
        'recordings; the cut parts are not in it.',
      );
    }
    return conf;
  }

  Future<void> _fromActivityJson(_Conf conf, _Act a, String folder) async {
    final j = await json('$folder/activity.json');
    a
      ..id = _str(j['id']) ?? a.id
      ..title = _str(j['title']) ?? a.title
      ..typeKey = _str(j['type']) ?? a.typeKey
      ..typeLabel = _str(j['type_label']) ?? a.typeLabel
      ..speakers = [
        for (final s in _list(j['speakers']))
          if (s is String) s,
      ]
      ..organisation = _str(j['organisation'])
      ..room = _str(j['room'])
      ..tags = [
        for (final s in _list(j['tags']))
          if (s is String) s,
      ]
      ..status =
          _enum(ActivityStatus.values, j['status']) ?? ActivityStatus.completed
      ..permission =
          _enum(
            RecordingPermissionStatus.values,
            j['recording_permission_status'],
          ) ??
          RecordingPermissionStatus.unknown
      ..isPrivate = j['is_private'] == true
      ..plannedStart = _time(j['planned_start_utc'])
      ..actualStart = _time(j['actual_start_utc'])
      ..actualEnd = _time(j['actual_end_utc']);
    // Nothing is being recorded in an imported activity.
    if (a.status == ActivityStatus.active) a.status = ActivityStatus.completed;

    DateTime? origin;
    for (final s in _list(j['segments'])) {
      if (s is! Map) continue;
      final start = _time(s['start_utc']);
      if (start == null) continue;
      if (origin == null || start.isBefore(origin)) origin = start;
      final file = _str(s['file']);
      if (file == null) continue;
      final rel = '$folder/$file';
      if (!has(rel)) continue;
      final state = _enum(SegmentState.values, s['state']);
      final trimmed = s['trimmed'] == true;
      final duration = _int(s['duration_ms']);
      final seg = _Seg()
        ..id = _str(s['id'])
        ..file = rel
        ..start = start
        ..end = trimmed && duration != null
            ? start.add(Duration(milliseconds: duration))
            : _time(s['end_utc'])
        ..durationMs = duration
        ..state = state == SegmentState.recovered
            ? SegmentState.recovered
            : SegmentState.finalised
        ..profile =
            _enum(RecordingProfile.values, s['profile']) ??
            RecordingProfile.balanced
        ..codec = _str(s['codec']) ?? 'aac_lc'
        ..container = _str(s['container']) ?? 'm4a'
        ..channels = _int(s['channel_count']) ?? 1
        ..sampleRate = _int(s['sample_rate_hz']) ?? 48000
        ..observedBitrate = _int(s['observed_bitrate_bps'])
        ..inputRoute = _str(s['input_route'])
        ..endReason = _enum(SegmentEndReason.values, s['end_reason']);
      seg.requestedBitrate =
          _int(s['requested_bitrate_bps']) ?? seg.profile.targetBitrateBps;
      a.segments.add(seg);
    }
    a.cutsOrigin = origin;

    for (final ph in _list(j['photos'])) {
      if (ph is! Map) continue;
      final file = _str(ph['file']);
      final taken = _time(ph['taken_utc']);
      if (file == null || taken == null || !has('$folder/$file')) continue;
      a.photos.add(
        _Pho()
          ..id = _str(ph['id'])
          ..file = '$folder/$file'
          ..taken = taken
          ..caption = _str(ph['caption'])
          ..label = _str(ph['label'])
          ..source =
              _enum(PhotoSource.values, ph['source']) ?? PhotoSource.inApp
          ..width = _int(ph['width'])
          ..height = _int(ph['height']),
      );
    }

    final bookmarks = _list(j['bookmarks']);
    if (bookmarks.isEmpty && has('$folder/bookmarks.csv')) {
      _bookmarksFromCsv(a, await text('$folder/bookmarks.csv'));
    }
    for (final b in bookmarks) {
      if (b is! Map) continue;
      final at = _time(b['at_utc']);
      if (at == null) continue;
      a.bookmarks.add(
        _Bm()
          ..id = _str(b['id'])
          ..at = at
          ..label = _str(b['label'])
          ..note = _str(b['note'])
          ..source =
              _enum(BookmarkSource.values, b['source']) ?? BookmarkSource.ui,
      );
    }

    for (final gap in _list(j['interruptions'])) {
      if (gap is! Map) continue;
      final start = _time(gap['start_utc']);
      if (start == null) continue;
      a.interruptions.add(
        _Gap()
          ..reason =
              _enum(InterruptionReason.values, gap['reason']) ??
              InterruptionReason.system
          ..start = start
          ..end = _time(gap['end_utc'])
          ..autoResumed = gap['auto_resumed'] == true,
      );
    }

    if (conf.audioMode != 'trimmed') {
      for (final cut in _list(j['cut_ranges'])) {
        if (cut is! Map) continue;
        final s = _int(cut['start_offset_ms']);
        final e = _int(cut['end_offset_ms']);
        if (s == null || e == null || e <= s) continue;
        a.cuts.add(_Cut(s, e, _str(cut['reason'])));
      }
    }
  }

  void _bookmarksFromCsv(_Act a, String csv) {
    final rows = parseCsv(csv);
    if (rows.isEmpty) return;
    final header = rows.first;
    for (final row in rows.skip(1)) {
      String? field(String name) {
        final i = header.indexOf(name);
        if (i < 0 || i >= row.length) return null;
        final v = _unFormula(row[i]);
        return v.isEmpty ? null : v;
      }

      final at = _time(field('utc_time'));
      if (at == null) continue;
      a.bookmarks.add(
        _Bm()
          ..at = at
          ..label = field('label')
          ..note = field('note')
          ..source =
              _enum(BookmarkSource.values, field('source')) ??
              BookmarkSource.ui,
      );
    }
  }

  /// Audio-only and photos-only exports (schema 2) have no activity.json;
  /// `timeline.csv` holds the times, offsets and files.
  Future<void> _fromTimeline(
    _Act a,
    String folder,
    List<Map<String, String>> timeline,
  ) async {
    final rows = timeline.where((r) => r['activity_id'] == a.id);
    DateTime? origin;
    for (final r in rows) {
      final at = _time(r['utc_time']);
      if (at == null) continue;
      final file = r['file'] ?? '';
      switch (r['kind']) {
        case 'segment':
          if (origin == null || at.isBefore(origin)) origin = at;
          if (file.isEmpty || !has(file) || !file.startsWith('$folder/')) {
            continue;
          }
          final seg = _Seg()
            ..file = file
            ..start = at
            ..end = _time(r['end_utc_time'])
            ..profile =
                _enum(RecordingProfile.values, r['profile']) ??
                RecordingProfile.balanced
            ..observedBitrate = int.tryParse(r['observed_bitrate_bps'] ?? '');
          seg.requestedBitrate = seg.profile.targetBitrateBps;
          await _inspect(seg, trimmed: r['note'] == 'trimmed copy');
          a.segments.add(seg);
        case 'photo':
          if (file.isEmpty || !has(file) || !file.startsWith('$folder/')) {
            continue;
          }
          a.photos.add(
            _Pho()
              ..file = file
              ..taken = at
              ..label = _blank(r['label'])
              ..caption = _blank(r['note']),
          );
        case 'bookmark':
          a.bookmarks.add(
            _Bm()
              ..at = at
              ..label = _blank(r['label'])
              ..note = _blank(r['note']),
          );
        case 'interruption':
          a.interruptions.add(
            _Gap()
              ..reason =
                  _enum(InterruptionReason.values, r['label']) ??
                  InterruptionReason.system
              ..start = at
              ..end = _time(r['end_utc_time'])
              ..autoResumed = r['note'] == 'resumed automatically',
          );
      }
    }
    a.cutsOrigin = origin;
  }

  /// Schema 1 audio-only or photos-only exports hold only the files. Photo
  /// times come from their names; recording times are not in the export,
  /// so recordings are placed one after another from the conference's
  /// first day (and the user is told).
  Future<void> _fromFiles(_Conf conf, _Act a, String folder) async {
    final files =
        staged.hashes.keys.where((k) => k.startsWith('$folder/')).toList()
          ..sort();
    final audio = files
        .where((f) => p.posix.dirname(f) == '$folder/audio')
        .where((f) => p.posix.extension(f).toLowerCase() == '.m4a')
        .toList();
    final photos = files
        .where((f) => p.posix.dirname(f) == '$folder/photos')
        .toList();
    var cursor =
        conf.startDate ??
        conf.exportedAt ??
        DateTime.utc(now.year, now.month, now.day);
    for (final f in audio) {
      final seg = _Seg()
        ..file = f
        ..start = cursor;
      await _inspect(seg, trimmed: f.contains('-trimmed'));
      seg.end ??= cursor.add(Duration(milliseconds: seg.durationMs ?? 0));
      cursor = seg.end!;
      a.segments.add(seg);
    }
    for (final f in photos) {
      a.photos.add(
        _Pho()
          ..file = f
          ..taken = _photoTime(p.posix.basename(f)) ?? cursor,
      );
    }
    if (audio.isNotEmpty) {
      conf.warnings.add(
        '"${a.title}": recording times are not in this export, so they '
        'start at the beginning of the conference.',
      );
    }
  }

  /// Fills a segment's audio details from the file (moov box only).
  Future<void> _inspect(_Seg seg, {required bool trimmed}) async {
    try {
      final info = await const M4aInspector().inspect(staged.file(seg.file));
      seg
        ..codec = info.codec
        ..container = info.container
        ..channels = info.channelCount
        ..sampleRate = info.sampleRateHz
        ..durationMs = info.durationMs;
      if (trimmed || seg.end == null) {
        seg.end = seg.start.add(Duration(milliseconds: info.durationMs));
      }
    } on Object {
      final end = seg.end;
      seg.durationMs = end?.difference(seg.start).inMilliseconds;
    }
  }

  void _typeFromFolder(_Act a, String folder) {
    // `001_0930_keynote_title`: the type label's slug is one of the parts.
    const known = {
      'session': 'Session',
      'keynote': 'Keynote',
      'panel': 'Panel',
      'breakout': 'Breakout',
      'workshop': 'Workshop',
      'exhibit': 'Exhibit',
      'conversation': 'Conversation',
      'reflection': 'Reflection',
    };
    final parts = p.posix.basename(folder).split('_');
    for (final part in parts.skip(1).take(2)) {
      final label = known[part];
      if (label != null) {
        a
          ..typeKey = switch (part) {
            'conversation' => 'business_conversation',
            'reflection' => 'personal_reflection',
            _ => part,
          }
          ..typeLabel = label;
        return;
      }
    }
    a
      ..typeKey = 'session'
      ..typeLabel = 'Session';
  }
}

/// `notes.md` as the export writes it (`# title`, the notes, then an
/// optional `## Follow-up` section) back into notes and follow-up text.
(String, String?) parseNotesMarkdown(String markdown) {
  var body = markdown.replaceAll('\r\n', '\n');
  if (body.startsWith('# ')) {
    final end = body.indexOf('\n');
    body = end < 0 ? '' : body.substring(end + 1);
  }
  String? followUp;
  const marker = '\n## Follow-up\n\n';
  final at = ('\n$body').lastIndexOf(marker);
  if (at >= 0) {
    final withLead = '\n$body';
    followUp = withLead.substring(at + marker.length).trim();
    body = withLead.substring(0, at);
  }
  final notes = body.trim();
  return (notes, (followUp == null || followUp.isEmpty) ? null : followUp);
}

/// RFC 4180 CSV (quoted fields, doubled quotes, CRLF or LF).
List<List<String>> parseCsv(String text) {
  final rows = <List<String>>[];
  var row = <String>[];
  final field = StringBuffer();
  var quoted = false;
  var i = 0;
  void endField() {
    row.add(field.toString());
    field.clear();
  }

  while (i < text.length) {
    final ch = text[i];
    if (quoted) {
      if (ch == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          quoted = false;
        }
      } else {
        field.write(ch);
      }
    } else if (ch == '"') {
      quoted = true;
    } else if (ch == ',') {
      endField();
    } else if (ch == '\r' || ch == '\n') {
      if (ch == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
      endField();
      rows.add(row);
      row = <String>[];
    } else {
      field.write(ch);
    }
    i++;
  }
  if (field.isNotEmpty || row.isNotEmpty) {
    endField();
    rows.add(row);
  }
  return rows;
}

List<Map<String, String>> _timelineRows(String csv) {
  final rows = parseCsv(csv);
  if (rows.isEmpty) return const [];
  final header = rows.first;
  return [
    for (final r in rows.skip(1))
      {
        for (var i = 0; i < header.length && i < r.length; i++)
          header[i]: _unFormula(r[i]),
      },
  ];
}

/// Undoes the `'` the exporter puts before a leading `=`, `+`, `-` or `@`.
String _unFormula(String v) =>
    v.length > 1 && v.startsWith("'") && '=+-@'.contains(v[1])
    ? v.substring(1)
    : v;

final _photoTimePattern = RegExp(
  r'^(\d{4})-(\d{2})-(\d{2})T(\d{2})-(\d{2})-(\d{2})Z',
);

DateTime? _photoTime(String name) {
  final m = _photoTimePattern.firstMatch(name);
  if (m == null) return null;
  int g(int i) => int.parse(m.group(i)!);
  return DateTime.utc(g(1), g(2), g(3), g(4), g(5), g(6));
}

String? _str(Object? v) => v is String ? v : null;

String? _blank(String? v) => (v == null || v.isEmpty) ? null : v;

int? _int(Object? v) => v is int
    ? v
    : v is num
    ? v.toInt()
    : v is String
    ? int.tryParse(v)
    : null;

List<Object?> _list(Object? v) => v is List ? v : const [];

DateTime? _time(Object? v) {
  if (v is! String || v.isEmpty) return null;
  return DateTime.tryParse(v)?.toUtc();
}

DateTime? _date(Object? v) {
  if (v is! String || v.length < 10) return null;
  final d = DateTime.tryParse(v.substring(0, 10));
  return d == null ? null : DateTime.utc(d.year, d.month, d.day);
}

T? _enum<T extends KeyedEnum>(List<T> values, Object? key) {
  if (key is! String) return null;
  for (final v in values) {
    if (v.key == key) return v;
  }
  return null;
}

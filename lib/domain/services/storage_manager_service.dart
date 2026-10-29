import 'dart:io';

import 'package:path/path.dart' as p;

import '../../data/filesystem/media_paths.dart';
import '../../data/repositories/activity_repository.dart';
import '../../data/repositories/conference_repository.dart';
import '../../data/repositories/export_job_repository.dart';
import '../../data/repositories/media_asset_repository.dart';
import '../../platform/storage/free_space_probe.dart';
import '../models/activity.dart';
import '../models/enums.dart';
import '../models/export_job.dart';
import '../models/media.dart';
import '../models/storage_breakdown.dart';
import 'export_documents.dart' show isPrivateThought;
import 'export_service.dart' show ExportContent;
import 'permanent_trim_service.dart' show KeptOriginal;
import 'private_notes.dart' show stripPrivateReflections;

/// Storage Manager (FR-STO-05, FR-STO-06, ADR-038, ADR-047) [P1-20].
///
/// Sizes come from the files on disk, attributed through the database
/// rows that name them; a file two rows share (ADR-036) is counted once.
/// Cleanup only removes what is safe: leftover export staging and waveform
/// summaries whose segment is gone. Partial and unlinked recordings belong
/// to crash recovery and are never touched (ADR-038). "Delete local
/// copies" needs a verified export that covers everything it removes, and
/// never deletes a file another row still names.
class StorageManagerService {
  StorageManagerService({
    required this.conferences,
    required this.activities,
    required this.media,
    required this.exports,
    required this.mediaRoot,
    required this.tempRoot,
    required this.freeSpaceProbe,
    required this.removeOriginals,
    this.exportRunning = _never,
  });

  final ConferenceRepository conferences;
  final ActivityRepository activities;
  final MediaAssetRepository media;
  final ExportJobRepository exports;
  final Future<Directory> Function() mediaRoot;

  /// The app cache folder; exports stage in `exports-temp/` there (ADR-040).
  final Future<Directory> Function() tempRoot;
  final FreeSpaceProbe freeSpaceProbe;

  /// `PermanentTrimService.removeOriginals` (ADR-037), which refuses any
  /// file a row names or outside an `audio/originals/` folder.
  final Future<int> Function(List<KeptOriginal> originals) removeOriginals;

  /// Whether an export is being written now; its staging is left alone.
  final bool Function() exportRunning;

  static bool _never() => false;

  static const exportsTempFolder = 'exports-temp';

  // ---------------------------------------------------------------------
  // FR-STO-05: sizes and export status.

  Future<AppStorageBreakdown> analyse() async {
    final root = await mediaRoot();
    final space = await _space(root.path);
    final segmentPaths = await media.segmentPaths();
    final segmentIds = await media.segmentIds();
    final types = {for (final t in await activities.types()) t.id: t.label};

    final confs = <ConferenceStorageBreakdown>[];
    final kept = <KeptOriginalFile>[];
    var total = StorageKindSizes.zero;
    var orphanWaveforms = 0;

    for (final conf in await conferences.getAll(includeArchived: true)) {
      final acts = await activities.listForConference(conf.id);
      final titles = {for (final a in acts) a.id: a.title};
      final jobs = await _completedJobs(conf.id);

      // Rows of the conference, to classify each file once.
      final photoPaths = <String>{};
      final thumbPaths = <String>{};
      final details = <String, _ActivityRows>{};
      for (final a in acts) {
        final rows = await _rows(a);
        details[a.id] = rows;
        for (final ph in rows.photos) {
          photoPaths.add(ph.filePath);
          if (ph.thumbnailPath != null) thumbPaths.add(ph.thumbnailPath!);
        }
      }

      // Every file in the conference folder, once.
      final files = _listFiles(root, MediaPaths.conferenceFolder(conf.id));
      var audio = 0, photos = 0, thumbs = 0, waves = 0, originals = 0;
      var recovery = 0;
      for (final MapEntry(key: rel, value: bytes) in files.entries) {
        final parts = p.posix.split(rel);
        final sub = parts.length > 5 ? parts[4] : '';
        if (MediaPaths.isPartial(rel)) {
          recovery += bytes;
        } else if (segmentPaths.contains(rel)) {
          audio += bytes;
        } else if (photoPaths.contains(rel)) {
          photos += bytes;
        } else if (thumbPaths.contains(rel) || sub == 'thumbs') {
          thumbs += bytes;
        } else if (MediaPaths.isKeptOriginal(rel)) {
          originals += bytes;
          kept.add(
            KeptOriginalFile(
              relativePath: rel,
              bytes: bytes,
              conferenceName: conf.name,
              activityTitle: titles[parts[3]],
            ),
          );
        } else if (sub == 'waveforms') {
          waves += bytes;
          if (!segmentIds.contains(p.posix.basenameWithoutExtension(rel))) {
            orphanWaveforms += bytes;
          }
        } else if (sub == 'photos') {
          photos += bytes;
        } else {
          // Unlinked audio and anything not recognised: crash recovery's.
          recovery += bytes;
        }
      }

      final actBreakdowns = <ActivityStorageBreakdown>[];
      for (final a in acts) {
        final rows = details[a.id]!;
        final folder = MediaPaths.activityFolder(conf.id, a.id);
        int sizeOf(Iterable<String> paths) =>
            paths.toSet().fold(0, (n, path) => n + (files[path] ?? 0));
        int sizeUnder(String sub) => files.entries
            .where((e) => p.posix.isWithin(p.posix.join(folder, sub), e.key))
            .fold(0, (n, e) => n + e.value);
        final keptHere = files.keys
            .where(
              (k) => MediaPaths.isKeptOriginal(k) && k.startsWith('$folder/'),
            )
            .length;
        actBreakdowns.add(
          ActivityStorageBreakdown(
            activityId: a.id,
            activityTitle: a.title,
            activityTypeLabel: types[a.typeId] ?? 'Activity',
            exportStatus: _status(jobs, a.id),
            sizes: StorageKindSizes(
              audioBytes: sizeOf(rows.segments.map((s) => s.filePath)),
              photoBytes: sizeOf(rows.photos.map((ph) => ph.filePath)),
              thumbnailBytes: sizeOf(
                rows.photos.map((ph) => ph.thumbnailPath).nonNulls,
              ),
              waveformBytes: sizeUnder('waveforms'),
              keptOriginalBytes: sizeUnder(p.posix.join('audio', 'originals')),
            ),
            segmentCount: rows.segments.length,
            photoCount: rows.photos.length,
            keptOriginalsCount: keptHere,
            deleteBlockedReason: _blockedReason(a, rows, jobs),
          ),
        );
      }

      final sizes = StorageKindSizes(
        audioBytes: audio,
        photoBytes: photos,
        thumbnailBytes: thumbs,
        waveformBytes: waves,
        keptOriginalBytes: originals,
        recoveryBytes: recovery,
      );
      total += sizes;
      confs.add(
        ConferenceStorageBreakdown(
          conferenceId: conf.id,
          conferenceName: conf.name,
          isArchived: conf.isArchived,
          exportStatus: acts.isEmpty
              ? _status(jobs, null)
              : actBreakdowns
                    .map((a) => a.exportStatus)
                    .reduce((x, y) => x.index <= y.index ? x : y),
          sizes: sizes,
          activities: actBreakdowns,
          deleteBlockedReason: acts.isEmpty
              ? 'This conference has no activities.'
              : actBreakdowns
                    .map((a) => a.deleteBlockedReason)
                    .nonNulls
                    .firstOrNull,
        ),
      );
    }

    // Folders of deleted conferences can still hold kept originals and
    // recovery files (Delete local copies leaves them): list them too.
    final known = {for (final c in confs) c.conferenceId};
    var leftOriginals = 0, leftOther = 0;
    for (final MapEntry(key: rel, value: bytes) in _listFiles(
      root,
      'conferences',
    ).entries) {
      final parts = p.posix.split(rel);
      if (parts.length < 3 || known.contains(parts[1])) continue;
      if (MediaPaths.isKeptOriginal(rel) && !segmentPaths.contains(rel)) {
        leftOriginals += bytes;
        kept.add(
          KeptOriginalFile(
            relativePath: rel,
            bytes: bytes,
            conferenceName: 'Deleted conference',
            activityTitle: null,
          ),
        );
      } else {
        leftOther += bytes;
      }
    }
    total += StorageKindSizes(
      keptOriginalBytes: leftOriginals,
      recoveryBytes: leftOther,
    );

    final temp = await tempRoot();
    final tempExports = _listFiles(
      temp,
      exportsTempFolder,
    ).values.fold(0, (n, b) => n + b);

    return AppStorageBreakdown(
      freeBytes: space?.availableBytes,
      capacityBytes: space?.totalBytes,
      sizes: total,
      conferences: confs,
      temporaryExportBytes: tempExports,
      orphanWaveformBytes: orphanWaveforms,
      keptOriginals: kept,
    );
  }

  // ---------------------------------------------------------------------
  // FR-STO-06: Clear safe temporary files.

  /// Deletes leftover export staging (`exports-temp/`, unless an export is
  /// running) and waveform summaries whose segment no longer exists
  /// (skipped while anything records). Never touches recordings, partial
  /// files, photos, thumbnails, kept originals or live waveforms
  /// (FR-REC-08, ADR-038, ADR-047).
  Future<SafeCleanupResult> clearSafeTemporaryFiles() async {
    var deleted = 0;
    var freed = 0;

    void remove(File f) {
      try {
        final bytes = f.lengthSync();
        f.deleteSync();
        deleted++;
        freed += bytes;
      } on FileSystemException {
        // In use or gone; left for next time.
      }
    }

    if (!exportRunning()) {
      final temp = await tempRoot();
      final staging = Directory(p.join(temp.path, exportsTempFolder));
      for (final rel in _listFiles(temp, exportsTempFolder).keys) {
        remove(File(p.joinAll([temp.path, ...p.posix.split(rel)])));
      }
      _removeEmptyFolders(staging, keepTop: true);
    }

    if ((await media.unfinalisedSegments()).isEmpty) {
      final root = await mediaRoot();
      final ids = await media.segmentIds();
      for (final rel in _listFiles(root, 'conferences').keys) {
        final parts = p.posix.split(rel);
        if (parts.length != 6 || parts[4] != 'waveforms') continue;
        if (p.posix.extension(rel) != '.wave') continue;
        if (ids.contains(p.posix.basenameWithoutExtension(rel))) continue;
        remove(MediaPaths.resolve(root, rel));
      }
    }
    return SafeCleanupResult(filesDeleted: deleted, bytesFreed: freed);
  }

  // ---------------------------------------------------------------------
  // FR-STO-06, ADR-037: Remove kept originals after trimming.

  /// Removes [originals] through `PermanentTrimService.removeOriginals`,
  /// which skips any file a row names.
  Future<SafeCleanupResult> removeKeptOriginals(
    List<KeptOriginalFile> originals,
  ) async {
    final root = await mediaRoot();
    final removed = await removeOriginals([
      for (final o in originals)
        KeptOriginal(relativePath: o.relativePath, bytes: o.bytes),
    ]);
    final freed = originals
        .where((o) => !MediaPaths.resolve(root, o.relativePath).existsSync())
        .fold(0, (n, o) => n + o.bytes);
    return SafeCleanupResult(filesDeleted: removed, bytesFreed: freed);
  }

  // ---------------------------------------------------------------------
  // FR-STO-06, FR-STO-07: Delete local copies.

  /// What "Delete local copies" of [activityId], or of the whole
  /// conference when null, would remove. Throws [StorageManagerException]
  /// when it is not allowed; nothing changes.
  Future<DeleteLocalPreview> previewDeleteLocalCopies({
    required String conferenceId,
    String? activityId,
  }) async => (await _plan(conferenceId, activityId)).preview;

  /// Deletes the files in the preview, then the activities' rows (and the
  /// conference row when every activity went). An activity whose file
  /// could not be deleted keeps its rows so nothing is left unnamed.
  Future<DeleteLocalResult> deleteLocalCopies({
    required String conferenceId,
    String? activityId,
  }) async {
    final plan = await _plan(conferenceId, activityId);
    final root = await mediaRoot();
    var deleted = 0;
    var freed = 0;
    final failedActivities = <String>{};
    var failed = 0;

    for (final MapEntry(key: rel, value: owners) in plan.files.entries) {
      final file = MediaPaths.resolve(root, rel);
      try {
        if (!file.existsSync()) continue;
        final bytes = file.lengthSync();
        file.deleteSync();
        deleted++;
        freed += bytes;
      } on FileSystemException {
        failed++;
        failedActivities.addAll(owners);
      }
    }

    var activitiesDeleted = 0;
    for (final a in plan.activities) {
      if (failedActivities.contains(a.id)) continue;
      await activities.delete(a.id);
      activitiesDeleted++;
      _removeEmptyFolders(
        Directory(
          p.join(root.path, MediaPaths.activityFolder(conferenceId, a.id)),
        ),
      );
    }
    if (activityId == null && failedActivities.isEmpty) {
      await conferences.delete(conferenceId);
      _removeEmptyFolders(
        Directory(p.join(root.path, MediaPaths.conferenceFolder(conferenceId))),
      );
    }
    return DeleteLocalResult(
      filesDeleted: deleted,
      bytesFreed: freed,
      activitiesDeleted: activitiesDeleted,
      failedFiles: failed,
    );
  }

  Future<_DeletePlan> _plan(String conferenceId, String? activityId) async {
    final conf = await conferences.get(conferenceId);
    if (conf == null) {
      throw const StorageManagerException('This conference no longer exists.');
    }
    final all = await activities.listForConference(conferenceId);
    final targets = activityId == null
        ? all
        : all.where((a) => a.id == activityId).toList();
    if (targets.isEmpty) {
      throw const StorageManagerException('There is nothing to delete.');
    }
    final jobs = await _completedJobs(conferenceId);
    final rowsByActivity = <String, _ActivityRows>{};
    for (final a in targets) {
      final rows = await _rows(a);
      final reason = _blockedReason(a, rows, jobs);
      if (reason != null) throw StorageManagerException(reason);
      rowsByActivity[a.id] = rows;
    }

    final root = await mediaRoot();
    final elsewhere = await media.namedFilePaths(
      excludingActivities: targets.map((a) => a.id),
    );
    final files = <String, Set<String>>{};
    final shared = <String>{};
    var audioFiles = 0, audioBytes = 0, photoFiles = 0, photoBytes = 0;
    var otherFiles = 0, otherBytes = 0, recoveryKept = 0, bookmarks = 0;
    var keptOriginals = 0;

    int add(String rel, String owner) {
      if (elsewhere.contains(rel)) {
        shared.add(rel);
        return -1;
      }
      final file = MediaPaths.resolve(root, rel);
      if (files.containsKey(rel)) {
        files[rel]!.add(owner);
        return -1;
      }
      if (!file.existsSync()) return -1;
      files[rel] = {owner};
      return file.lengthSync();
    }

    for (final a in targets) {
      final rows = rowsByActivity[a.id]!;
      bookmarks += rows.bookmarks.length;
      for (final s in rows.segments) {
        final b = add(s.filePath, a.id);
        if (b >= 0) {
          audioFiles++;
          audioBytes += b;
        }
      }
      for (final ph in rows.photos) {
        for (final rel in [ph.filePath, ph.thumbnailPath].nonNulls) {
          final b = add(rel, a.id);
          if (b >= 0) {
            photoFiles++;
            photoBytes += b;
          }
        }
      }
      // Waveform summaries in the activity folder go too. Kept originals
      // are not in a normal export (ADR-040), so they stay for their own
      // "Remove originals" action. Partial and unlinked recordings stay
      // for crash recovery.
      final folder = MediaPaths.activityFolder(conferenceId, a.id);
      for (final rel in _listFiles(root, folder).keys) {
        if (files.containsKey(rel) || elsewhere.contains(rel)) continue;
        final parts = p.posix.split(rel);
        final isWave = parts.length == 6 && parts[4] == 'waveforms';
        if (MediaPaths.isKeptOriginal(rel)) {
          keptOriginals++;
        } else if (!MediaPaths.isPartial(rel) && isWave) {
          final b = add(rel, a.id);
          if (b >= 0) {
            otherFiles++;
            otherBytes += b;
          }
        } else if (!_namedByTargets(rel, rowsByActivity.values)) {
          recoveryKept++;
        }
      }
    }

    return _DeletePlan(
      activities: targets,
      files: files,
      preview: DeleteLocalPreview(
        conferenceId: conferenceId,
        conferenceName: conf.name,
        activityId: activityId,
        activityTitles: [for (final a in targets) a.title],
        audioFiles: audioFiles,
        audioBytes: audioBytes,
        photoFiles: photoFiles,
        photoBytes: photoBytes,
        otherFiles: otherFiles,
        otherBytes: otherBytes,
        sharedFilesKept: shared.length,
        recoveryFilesKept: recoveryKept,
        keptOriginalsKept: keptOriginals,
        bookmarkCount: bookmarks,
      ),
    );
  }

  static bool _namedByTargets(String rel, Iterable<_ActivityRows> rows) =>
      rows.any(
        (r) =>
            r.segments.any((s) => s.filePath == rel) ||
            r.photos.any((ph) => ph.filePath == rel || ph.thumbnailPath == rel),
      );

  // ---------------------------------------------------------------------
  // Export status and the delete gate (ADR-040, ADR-047).

  Future<List<ExportJob>> _completedJobs(String conferenceId) async =>
      (await exports.forConference(conferenceId))
          .where((j) => j.state == ExportJobState.completed)
          .toList();

  /// True when [job]'s scope names [activityId] (or the whole conference;
  /// [activityId] null asks about the conference). A one-day export does
  /// not count: its activities are not stored in the job.
  static bool _covers(ExportJob job, String? activityId) {
    final kind = job.scope['kind'];
    if (kind == 'conference') return true;
    if (activityId != null && kind == 'activities') {
      final ids = job.scope['activity_ids'];
      return ids is List && ids.contains(activityId);
    }
    return false;
  }

  static ExportStatus _status(List<ExportJob> jobs, String? activityId) {
    var best = ExportStatus.notExported;
    for (final j in jobs.where((j) => _covers(j, activityId))) {
      final s = j.verificationLevel == VerificationLevel.checksum
          ? ExportStatus.verified
          : j.destination == ExportDestination.local
          ? ExportStatus.exportedLocally
          : ExportStatus.uploaded;
      if (s.index > best.index) best = s;
    }
    return best;
  }

  /// Why the activity's local copies may not be deleted, or null.
  ///
  /// Needs a completed export verified by checksum that covers the
  /// activity, holds everything (all content, full-length audio, private
  /// items when the activity, its bookmarks or its notes have any) and
  /// read its data after the activity last changed. Never while a segment
  /// is being written, and never when a segment is damaged or missing
  /// (the export could not hold it).
  static String? _blockedReason(
    Activity a,
    _ActivityRows rows,
    List<ExportJob> jobs,
  ) {
    if (rows.segments.any((s) => s.state == SegmentState.writing)) {
      return 'This activity is still recording.';
    }
    if (rows.unexportable > 0) {
      return 'A recording in this activity is damaged or missing, so no '
          'export holds it. Its local copies are kept.';
    }
    final verified =
        jobs
            .where(
              (j) =>
                  _covers(j, a.id) &&
                  j.verificationLevel == VerificationLevel.checksum,
            )
            .toList()
          ..sort((x, y) => _snapshot(y).compareTo(_snapshot(x)));
    if (verified.isEmpty) {
      return 'Needs a verified export first. Export as a folder: folder '
          'exports are checked file by file.';
    }
    final notes = a.notesMd;
    final needsPrivate =
        a.isPrivate ||
        rows.bookmarks.any(isPrivateThought) ||
        (notes != null && stripPrivateReflections(notes).$2 > 0);
    final changed = rows.lastChange(a);
    String? reason;
    for (final j in verified) {
      final scope = j.scope;
      final audioMode = scope['audio_mode'];
      final String? why;
      if (scope['content'] != ExportContent.everything.key) {
        why =
            'The verified export does not hold everything. Export again '
            'with "Everything".';
      } else if (audioMode != ExportAudioMode.original.key &&
          audioMode != ExportAudioMode.originalWithCuts.key) {
        why =
            'The verified export has trimmed audio only. Export again '
            'with the original recordings.';
      } else if (needsPrivate && scope['include_private'] != true) {
        why =
            'The verified export left out private items. Export again '
            'with "Include private items".';
      } else if (!changed.isBefore(_snapshot(j))) {
        why =
            'This activity changed after the last verified export. '
            'Export it again first.';
      } else {
        return null;
      }
      reason ??= why;
    }
    return reason;
  }

  /// When the export read its data. `ExportService` plans (reads every
  /// row) and then creates the job, so `created_at` is just after the
  /// snapshot; a change at or after it, including while the export ran,
  /// is not in the export.
  static DateTime _snapshot(ExportJob j) => j.createdAt;

  // ---------------------------------------------------------------------
  // Helpers.

  Future<_ActivityRows> _rows(Activity a) async {
    final root = await mediaRoot();
    final segments = await media.segmentsFor(a.id);
    return _ActivityRows(
      segments: segments,
      photos: await media.photosFor(a.id),
      bookmarks: await media.bookmarksFor(a.id),
      // What ExportService.plan leaves out (ADR-040): damaged segments
      // and files that are missing.
      unexportable: segments
          .where(
            (s) =>
                s.state == SegmentState.damaged ||
                !MediaPaths.resolve(root, s.filePath).existsSync(),
          )
          .length,
    );
  }

  Future<FreeSpace?> _space(String path) async {
    try {
      return await freeSpaceProbe.query(path);
    } on Object {
      return null;
    }
  }

  /// Files under [folder] (relative, POSIX) of [base], with sizes, keyed
  /// by the path relative to [base].
  static Map<String, int> _listFiles(Directory base, String folder) {
    final dir = Directory(p.joinAll([base.path, ...p.posix.split(folder)]));
    final out = <String, int>{};
    if (!dir.existsSync()) return out;
    try {
      for (final e in dir.listSync(recursive: true, followLinks: false)) {
        if (e is! File) continue;
        try {
          final rel = p.posix.joinAll(
            p.split(p.relative(e.path, from: base.path)),
          );
          out[rel] = e.lengthSync();
        } on FileSystemException {
          // Gone or locked; not counted.
        }
      }
    } on FileSystemException {
      // Folder unreadable; count what was listed.
    }
    return out;
  }

  /// Removes empty folders under [dir], deepest first, and [dir] itself
  /// unless [keepTop]. A folder with any file in it stays.
  static void _removeEmptyFolders(Directory dir, {bool keepTop = false}) {
    if (!dir.existsSync()) return;
    try {
      final folders =
          dir
              .listSync(recursive: true, followLinks: false)
              .whereType<Directory>()
              .toList()
            ..sort((a, b) => b.path.length.compareTo(a.path.length));
      for (final f in [...folders, if (!keepTop) dir]) {
        if (f.listSync().isEmpty) f.deleteSync();
      }
    } on FileSystemException {
      // Left in place.
    }
  }
}

class _ActivityRows {
  _ActivityRows({
    required this.segments,
    required this.photos,
    required this.bookmarks,
    required this.unexportable,
  });

  final List<RecordingSegment> segments;
  final List<Photo> photos;
  final List<Bookmark> bookmarks;

  /// Damaged segments or segments whose file is missing: no export can
  /// hold them.
  final int unexportable;

  DateTime lastChange(Activity a) {
    var last = a.updatedAt;
    for (final t in [
      ...segments.map((s) => s.updatedAt),
      ...photos.map((ph) => ph.updatedAt),
      ...bookmarks.map((b) => b.updatedAt),
    ]) {
      if (t.isAfter(last)) last = t;
    }
    return last;
  }
}

class _DeletePlan {
  _DeletePlan({
    required this.activities,
    required this.files,
    required this.preview,
  });

  final List<Activity> activities;

  /// Relative path to the ids of the target activities that name it.
  final Map<String, Set<String>> files;
  final DeleteLocalPreview preview;
}

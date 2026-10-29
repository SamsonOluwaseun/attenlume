import 'dart:io';

import 'package:attenlume/data/filesystem/media_paths.dart';
import 'package:attenlume/data/local_database/app_database.dart';
import 'package:attenlume/domain/models/enums.dart';
import 'package:attenlume/domain/models/storage_breakdown.dart';
import 'package:attenlume/domain/services/capture_settings.dart';
import 'package:attenlume/domain/services/permanent_trim_service.dart';
import 'package:attenlume/domain/services/private_notes.dart';
import 'package:attenlume/domain/services/recording_service.dart';
import 'package:attenlume/domain/services/recording_state.dart';
import 'package:attenlume/domain/services/storage_manager_service.dart';
import 'package:attenlume/platform/audio_trimmer/mp4_sample_trimmer.dart';
import 'package:attenlume/platform/storage/free_space_probe.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../fixtures/fake_capture_engine.dart';
import '../fixtures/fixtures.dart';

class FixedFreeSpace implements FreeSpaceProbe {
  const FixedFreeSpace();

  @override
  Future<FreeSpace?> query(String path) async =>
      const FreeSpace(availableBytes: 50 << 30, totalBytes: 128 << 30);
}

/// The scope an export of the whole conference stores (ADR-040).
Map<String, Object?> fullScope({
  String audioMode = 'original',
  String content = 'everything',
  bool includePrivate = false,
}) => {
  'kind': 'conference',
  'content': content,
  'format': 'folder',
  'audio_mode': audioMode,
  'include_private': includePrivate,
  'include_kept_originals': false,
};

void main() {
  late TestData t;
  late Directory sandbox;
  late Directory root;
  late Directory temp;
  late StorageManagerService service;
  var exportRunning = false;
  // Paths the fake deleter refuses, as if another app had them open.
  final locked = <String>{};
  // The recorder's held activity, as RecordingService reports it.
  String? Function() held = () => null;

  setUp(() {
    t = TestData();
    sandbox = Directory.systemTemp.createTempSync('attenlume_storage_');
    root = Directory(p.join(sandbox.path, 'media'))..createSync();
    temp = Directory(p.join(sandbox.path, 'cache'))..createSync();
    exportRunning = false;
    locked.clear();
    held = () => null;
    final trim = PermanentTrimService(
      activities: t.activities,
      media: t.media,
      cuts: t.cuts,
      trimmer: const Mp4SampleTrimmer(),
      mediaRoot: () async => root,
    );
    service = StorageManagerService(
      conferences: t.conferences,
      activities: t.activities,
      media: t.media,
      exports: t.exports,
      cuts: t.cuts,
      mediaRoot: () async => root,
      tempRoot: () async => temp,
      freeSpaceProbe: const FixedFreeSpace(),
      removeOriginals: trim.removeOriginals,
      exportRunning: () => exportRunning,
      deleteFile: (f) {
        if (locked.contains(f.path)) {
          throw FileSystemException('Locked', f.path);
        }
        f.deleteSync();
      },
      heldActivityId: () => held(),
    );
  });

  tearDown(() async {
    await t.close();
    sandbox.deleteSync(recursive: true);
  });

  File write(String rel, int bytes, {Directory? base}) {
    final f = MediaPaths.resolve(base ?? root, rel);
    f.parent.createSync(recursive: true);
    f.writeAsBytesSync(List.filled(bytes, 1));
    return f;
  }

  Future<String> segment(
    String activityId,
    String rel,
    int bytes, {
    bool finalise = true,
  }) async {
    write(rel, bytes);
    final s = await t.media.startSegment(
      activityId: activityId,
      filePath: rel,
      requestedProfile: RecordingProfile.balanced,
      codec: 'aac_lc',
      container: 'm4a',
      channelCount: 1,
      sampleRateHz: 48000,
      requestedBitrateBps: 48000,
      inputRoute: 'built_in',
      startUtc: t.clock(),
    );
    if (finalise) {
      await t.media.finaliseSegment(
        s.id,
        endUtc: t.clock().add(const Duration(minutes: 1)),
        endReason: SegmentEndReason.userStop,
        durationMs: 60000,
        bytes: bytes,
        sha256: 'f' * 64,
        observedBitrateBps: 48000,
      );
    }
    return s.id;
  }

  Future<void> photo(String confId, String activityId, String id) async {
    final rel = MediaPaths.photo(confId, activityId, id);
    final thumb = MediaPaths.thumbnail(confId, activityId, id);
    write(rel, 5000);
    write(thumb, 800);
    await t.media.addPhoto(
      id: id,
      activityId: activityId,
      filePath: rel,
      thumbnailPath: thumb,
      takenUtc: t.clock(),
      source: PhotoSource.inApp,
      bytes: 5000,
    );
  }

  Future<void> exported(
    String confId, {
    Map<String, Object?>? scope,
    VerificationLevel level = VerificationLevel.checksum,
  }) async {
    // The export reads its data after the last change.
    t.clock.advance(const Duration(seconds: 1));
    final job = await t.exports.create(
      conferenceId: confId,
      scope: {
        'snapshot_at': t.clock().toIso8601String(),
        ...(scope ?? fullScope()),
      },
      format: ExportFormat.folder,
      audioMode: ExportAudioMode.original,
    );
    await t.exports.complete(job.id, level);
  }

  group('FR-STO-05 sizes and export status', () {
    test('FR-STO-05 an empty app reports nothing used', () async {
      final b = await service.analyse();
      expect(b.totalBytes, 0);
      expect(b.conferences, isEmpty);
      expect(b.freeBytes, 50 << 30);
      expect(b.capacityBytes, 128 << 30);
    });

    test('FR-STO-05 sizes split into audio, photos, thumbnails, waveforms, '
        'kept originals, temporary exports and recovery files', () async {
      final conf = await t.conference();
      final act = await t.activity(conf.id, title: 'Opening keynote');
      final segId = await segment(
        act.id,
        MediaPaths.segment(conf.id, act.id, 1),
        10000,
      );
      await photo(conf.id, act.id, 'photo1');
      write(MediaPaths.waveform(conf.id, act.id, segId), 1200);
      write(
        p.posix.join(
          MediaPaths.originalsFolder(conf.id, act.id),
          'segment-001.m4a',
        ),
        20000,
      );
      write(MediaPaths.partial(MediaPaths.segment(conf.id, act.id, 2)), 700);
      write('exports-temp/job-1/audio.m4a', 300, base: temp);

      final b = await service.analyse();
      final c = b.conferences.single;
      final a = c.activities.single;
      expect(a.sizes.audioBytes, 10000);
      expect(a.sizes.photoBytes, 5000);
      expect(a.sizes.thumbnailBytes, 800);
      expect(a.sizes.waveformBytes, 1200);
      expect(a.sizes.keptOriginalBytes, 20000);
      expect(a.keptOriginalsCount, 1);
      expect(c.sizes.recoveryBytes, 700);
      expect(a.sizes.recoveryBytes, 700);
      expect(c.sizes.totalBytes, 10000 + 5000 + 800 + 1200 + 20000 + 700);
      expect(b.temporaryExportBytes, 300);
      expect(b.orphanWaveformBytes, 0);
      expect(b.totalBytes, c.sizes.totalBytes + 300);
      expect(b.keptOriginals.single.activityTitle, 'Opening keynote');
      expect(
        b.keptOriginals.single.conferenceName,
        'Samlytics Conference 2026',
      );
    });

    test('FR-STO-05 ADR-036 a file shared by two segment rows is counted '
        'once', () async {
      final conf = await t.conference();
      final part1 = await t.activity(conf.id, title: 'Panel');
      final part2 = await t.activity(conf.id, title: 'Panel (Part 2)');
      final shared = MediaPaths.segment(conf.id, part1.id, 1);
      await segment(part1.id, shared, 15000);
      await segment(part2.id, shared, 15000);

      final b = await service.analyse();
      final c = b.conferences.single;
      expect(c.activities.map((a) => a.sizes.audioBytes), [15000, 15000]);
      expect(c.sizes.audioBytes, 15000);
      expect(b.sizes.audioBytes, 15000);
      expect(b.totalBytes, 15000);
    });

    test('FR-STO-05 export status comes from export_jobs: not exported, '
        'exported locally, verified', () async {
      final conf = await t.conference();
      final a1 = await t.activity(conf.id, title: 'Talk one');
      final a2 = await t.activity(conf.id, title: 'Talk two');

      var c = (await service.analyse()).conferences.single;
      expect(c.exportStatus, ExportStatus.notExported);

      // A ZIP is not checked file by file (ADR-040).
      await exported(conf.id, level: VerificationLevel.none);
      c = (await service.analyse()).conferences.single;
      expect(c.exportStatus, ExportStatus.exportedLocally);

      await exported(
        conf.id,
        scope: {
          ...fullScope(),
          'kind': 'activities',
          'activity_ids': [a1.id],
        },
      );
      c = (await service.analyse()).conferences.single;
      final byId = {for (final a in c.activities) a.activityId: a};
      expect(byId[a1.id]!.exportStatus, ExportStatus.verified);
      expect(byId[a2.id]!.exportStatus, ExportStatus.exportedLocally);
      // The conference shows the least-exported activity.
      expect(c.exportStatus, ExportStatus.exportedLocally);

      await exported(conf.id);
      c = (await service.analyse()).conferences.single;
      expect(c.exportStatus, ExportStatus.verified);
    });
  });

  test('FR-STO-05 recovery files in an activity folder show under that '
      'activity, and activities plus conference-level files add up to the '
      'conference total', () async {
    final conf = await t.conference();
    final a1 = await t.activity(conf.id, title: 'Interrupted talk');
    final a2 = await t.activity(conf.id, title: 'Workshop');
    write(MediaPaths.partial(MediaPaths.segment(conf.id, a1.id, 1)), 4000);
    write(MediaPaths.segment(conf.id, a1.id, 2), 1500); // unlinked
    await segment(a2.id, MediaPaths.segment(conf.id, a2.id, 1), 3000);
    await photo(conf.id, a2.id, 'photo1');
    write(MediaPaths.waveform(conf.id, a2.id, 'gone'), 100);
    // Outside any activity folder.
    final stray = p.posix.join(MediaPaths.conferenceFolder(conf.id), 'x.tmp');
    write(stray, 250);

    final c = (await service.analyse()).conferences.single;
    final byId = {for (final a in c.activities) a.activityId: a};
    expect(byId[a1.id]!.sizes.recoveryBytes, 5500);
    expect(byId[a1.id]!.totalBytes, 5500);
    expect(byId[a2.id]!.totalBytes, 3000 + 5000 + 800 + 100);
    expect(
      c.activities.fold(0, (n, a) => n + a.totalBytes) + 250,
      c.totalBytes,
    );
  });

  group('FR-STO-06 Clear safe temporary files', () {
    test('FR-STO-06 FR-REC-08 ADR-038 partial recordings are never cleared; '
        'only export staging and orphaned waveforms go', () async {
      final conf = await t.conference();
      final act = await t.activity(conf.id);
      final segRel = MediaPaths.segment(conf.id, act.id, 1);
      final segId = await segment(act.id, segRel, 1000);
      await photo(conf.id, act.id, 'photo1');
      final liveWave = write(MediaPaths.waveform(conf.id, act.id, segId), 300);
      final orphanWave = write(
        MediaPaths.waveform(conf.id, act.id, 'gone-segment'),
        200,
      );
      final partial = write(
        MediaPaths.partial(MediaPaths.segment(conf.id, act.id, 2)),
        500,
      );
      final unlinked = write(MediaPaths.segment(conf.id, act.id, 3), 600);
      final original = write(
        p.posix.join(MediaPaths.originalsFolder(conf.id, act.id), 'a.m4a'),
        900,
      );
      final staging = write('exports-temp/job-1/x.m4a', 400, base: temp);

      expect((await service.analyse()).safeTemporaryBytes, 600);
      final res = await service.clearSafeTemporaryFiles();
      expect(res.filesDeleted, 2);
      expect(res.bytesFreed, 600);

      expect(staging.existsSync(), isFalse);
      expect(orphanWave.existsSync(), isFalse);
      expect(partial.readAsBytesSync(), List.filled(500, 1));
      expect(unlinked.existsSync(), isTrue);
      expect(liveWave.existsSync(), isTrue);
      expect(original.existsSync(), isTrue);
      expect(MediaPaths.resolve(root, segRel).existsSync(), isTrue);
      expect(
        MediaPaths.resolve(
          root,
          MediaPaths.photo(conf.id, act.id, 'photo1'),
        ).existsSync(),
        isTrue,
      );
    });

    test('FR-STO-06 export staging is left alone while an export runs, and '
        'orphaned waveforms while anything records', () async {
      final conf = await t.conference();
      final act = await t.activity(conf.id);
      await segment(
        act.id,
        MediaPaths.segment(conf.id, act.id, 1),
        100,
        finalise: false,
      );
      final orphan = write(MediaPaths.waveform(conf.id, act.id, 'old'), 50);
      final staging = write('exports-temp/job-1/x.m4a', 400, base: temp);
      exportRunning = true;

      final res = await service.clearSafeTemporaryFiles();
      expect(res.filesDeleted, 0);
      expect(staging.existsSync(), isTrue);
      expect(orphan.existsSync(), isTrue);
    });
  });

  group('FR-STO-06 ADR-037 kept originals', () {
    test('FR-STO-06 kept originals are listed and removable; a file a row '
        'names is never removed', () async {
      final conf = await t.conference();
      final act = await t.activity(conf.id, title: 'Workshop');
      final folder = MediaPaths.originalsFolder(conf.id, act.id);
      final kept = write(p.posix.join(folder, 'segment-001.m4a'), 7000);
      final namedRel = p.posix.join(folder, 'segment-002.m4a');
      await segment(act.id, namedRel, 3000);

      final b = await service.analyse();
      expect(b.keptOriginals.map((o) => o.relativePath), [
        p.posix.join(folder, 'segment-001.m4a'),
      ]);
      expect(b.keptOriginalBytes, 7000);

      // Even when asked to, a named file stays.
      final res = await service.removeKeptOriginals([
        ...b.keptOriginals,
        KeptOriginalFile(
          relativePath: namedRel,
          bytes: 3000,
          conferenceName: conf.name,
          activityTitle: act.title,
        ),
      ]);
      expect(res.filesDeleted, 1);
      expect(res.bytesFreed, 7000);
      expect(kept.existsSync(), isFalse);
      expect(MediaPaths.resolve(root, namedRel).existsSync(), isTrue);
      expect((await service.analyse()).keptOriginals, isEmpty);
    });
  });

  group('FR-STO-06 FR-STO-07 Delete local copies', () {
    test('FR-STO-06 delete local copies is refused without a verified '
        'export', () async {
      final conf = await t.conference();
      final act = await t.activity(conf.id);
      final rel = MediaPaths.segment(conf.id, act.id, 1);
      await segment(act.id, rel, 1000);
      // Exported as a ZIP: completed but not verified.
      await exported(conf.id, level: VerificationLevel.none);

      final c = (await service.analyse()).conferences.single;
      expect(c.canDeleteLocalCopies, isFalse);
      expect(c.activities.single.canDeleteLocalCopies, isFalse);
      await expectLater(
        service.previewDeleteLocalCopies(conferenceId: conf.id),
        throwsA(isA<StorageManagerException>()),
      );
      await expectLater(
        service.deleteLocalCopies(conferenceId: conf.id, activityId: act.id),
        throwsA(isA<StorageManagerException>()),
      );
      expect(MediaPaths.resolve(root, rel).existsSync(), isTrue);
      expect(await t.activities.get(act.id), isNotNull);
    });

    test('FR-STO-06 a verified export that does not hold everything does '
        'not allow deleting', () async {
      final conf = await t.conference();
      final act = await t.activity(conf.id, title: 'Reflection');
      await segment(act.id, MediaPaths.segment(conf.id, act.id, 1), 1000);
      await t.media.addBookmark(
        activityId: act.id,
        source: BookmarkSource.ui,
        label: privateThoughtLabel,
        note: 'Follow up with Samlytics Data Services',
      );

      Future<String?> reason() async => (await service.analyse())
          .conferences
          .single
          .activities
          .single
          .deleteBlockedReason;

      t.clock.advance(const Duration(seconds: 1));
      await exported(conf.id, scope: fullScope(audioMode: 'trimmed'));
      expect(await reason(), contains('trimmed audio'));
      t.clock.advance(const Duration(seconds: 1));
      await exported(conf.id, scope: fullScope(content: 'audio_only'));
      expect(await reason(), contains('Everything'));
      t.clock.advance(const Duration(seconds: 1));
      await exported(conf.id, scope: fullScope());
      expect(await reason(), contains('private items'));

      t.clock.advance(const Duration(seconds: 1));
      await exported(conf.id, scope: fullScope(includePrivate: true));
      expect(await reason(), isNull);

      // A change after the export needs a new export.
      t.clock.advance(const Duration(minutes: 5));
      await t.media.addBookmark(activityId: act.id, source: BookmarkSource.ui);
      expect(await reason(), contains('changed after'));
    });

    test('FR-STO-06 delete local copies is refused while recording', () async {
      final conf = await t.conference();
      final act = await t.activity(conf.id);
      await segment(
        act.id,
        MediaPaths.segment(conf.id, act.id, 1),
        100,
        finalise: false,
      );
      await exported(conf.id);
      expect(
        (await service.analyse()).conferences.single.deleteBlockedReason,
        contains('still recording'),
      );
    });

    test(
      'FR-STO-06 ADR-036 refuses to delete a file another row names',
      () async {
        final conf = await t.conference();
        final part1 = await t.activity(conf.id, title: 'Panel');
        final part2 = await t.activity(conf.id, title: 'Panel (Part 2)');
        final shared = MediaPaths.segment(conf.id, part1.id, 1);
        final own = MediaPaths.segment(conf.id, part1.id, 2);
        await segment(part1.id, shared, 8000);
        await segment(part1.id, own, 4000);
        await segment(part2.id, shared, 8000);
        await exported(conf.id);

        final preview = await service.previewDeleteLocalCopies(
          conferenceId: conf.id,
          activityId: part1.id,
        );
        expect(preview.audioFiles, 1);
        expect(preview.audioBytes, 4000);
        expect(preview.sharedFilesKept, 1);

        final res = await service.deleteLocalCopies(
          conferenceId: conf.id,
          activityId: part1.id,
        );
        expect(res.filesDeleted, 1);
        expect(res.activitiesDeleted, 1);
        expect(MediaPaths.resolve(root, own).existsSync(), isFalse);
        expect(MediaPaths.resolve(root, shared).existsSync(), isTrue);
        expect(await t.activities.get(part1.id), isNull);
        expect((await t.media.segmentsFor(part2.id)).single.filePath, shared);
      },
    );

    test('FR-STO-06 FR-STO-07 deleting a conference removes its files and '
        'rows ("delete means delete") but keeps partial recordings and kept '
        'originals', () async {
      final conf = await t.conference();
      final act = await t.activity(conf.id, title: 'Opening keynote');
      final segRel = MediaPaths.segment(conf.id, act.id, 1);
      final segId = await segment(act.id, segRel, 6000);
      await photo(conf.id, act.id, 'photo1');
      await t.media.addBookmark(
        activityId: act.id,
        source: BookmarkSource.ui,
        label: 'Key slide',
      );
      final wave = write(MediaPaths.waveform(conf.id, act.id, segId), 100);
      final original = write(
        p.posix.join(MediaPaths.originalsFolder(conf.id, act.id), 'old.m4a'),
        900,
      );
      final partial = write(
        MediaPaths.partial(MediaPaths.segment(conf.id, act.id, 2)),
        500,
      );
      await exported(conf.id);

      final preview = await service.previewDeleteLocalCopies(
        conferenceId: conf.id,
      );
      expect(preview.audioFiles, 1);
      expect(preview.photoFiles, 2);
      expect(preview.otherFiles, 1);
      expect(preview.bookmarkCount, 1);
      expect(preview.recoveryFilesKept, 1);
      expect(preview.keptOriginalsKept, 1);
      expect(preview.totalBytes, 6000 + 5000 + 800 + 100);

      final res = await service.deleteLocalCopies(conferenceId: conf.id);
      expect(res.filesDeleted, 4);
      expect(res.bytesFreed, preview.totalBytes);
      expect(res.failedFiles, 0);

      expect(MediaPaths.resolve(root, segRel).existsSync(), isFalse);
      expect(wave.existsSync(), isFalse);
      // Kept originals are not in a normal export: they stay for
      // "Remove originals", which still finds them.
      expect(original.existsSync(), isTrue);
      expect(partial.existsSync(), isTrue);
      final after = await service.analyse();
      expect(after.keptOriginals.single.conferenceName, 'Deleted conference');
      expect(after.keptOriginals.single.activityTitle, isNull);
      await service.removeKeptOriginals(after.keptOriginals);
      expect(original.existsSync(), isFalse);
      expect(partial.existsSync(), isTrue);
      expect(await t.activities.get(act.id), isNull);
      expect(await t.conferences.get(conf.id), isNull);
      expect(await t.media.bookmarksFor(act.id), isEmpty);
    });

    test('FR-STO-06 private reflections in public notes need an export with '
        'private items', () async {
      final conf = await t.conference();
      final act = await t.activities.create(
        conferenceId: conf.id,
        typeId: builtinTypeId('session'),
        title: 'Talk',
        notesMd:
            'Public summary.\n\n'
            '${formatQuickThought('Ask Samlytics Data Services about pricing', isPrivate: true)}',
      );
      expect(act.isPrivate, isFalse);
      await segment(act.id, MediaPaths.segment(conf.id, act.id, 1), 1000);

      await exported(conf.id);
      var reason = (await service.analyse())
          .conferences
          .single
          .activities
          .single
          .deleteBlockedReason;
      expect(reason, contains('private items'));
      await expectLater(
        service.deleteLocalCopies(conferenceId: conf.id, activityId: act.id),
        throwsA(isA<StorageManagerException>()),
      );

      await exported(conf.id, scope: fullScope(includePrivate: true));
      reason = (await service.analyse())
          .conferences
          .single
          .activities
          .single
          .deleteBlockedReason;
      expect(reason, isNull);
    });

    test('FR-STO-06 kept originals are never in Delete local copies', () async {
      final conf = await t.conference();
      final act = await t.activity(conf.id, title: 'Workshop');
      await segment(act.id, MediaPaths.segment(conf.id, act.id, 1), 1000);
      final original = write(
        p.posix.join(MediaPaths.originalsFolder(conf.id, act.id), 'a.m4a'),
        900,
      );
      await exported(conf.id);

      final preview = await service.previewDeleteLocalCopies(
        conferenceId: conf.id,
        activityId: act.id,
      );
      expect(preview.keptOriginalsKept, 1);
      expect(preview.totalBytes, 1000);
      await service.deleteLocalCopies(
        conferenceId: conf.id,
        activityId: act.id,
      );
      expect(original.existsSync(), isTrue);
    });

    test('FR-STO-06 a damaged segment refuses Delete local copies', () async {
      final conf = await t.conference();
      final act = await t.activity(conf.id);
      final rel = MediaPaths.segment(conf.id, act.id, 1);
      final segId = await segment(act.id, rel, 1000);
      await t.media.setSegmentState(segId, SegmentState.damaged);
      await exported(conf.id);

      final c = (await service.analyse()).conferences.single;
      expect(c.activities.single.deleteBlockedReason, contains('damaged'));
      await expectLater(
        service.deleteLocalCopies(conferenceId: conf.id),
        throwsA(isA<StorageManagerException>()),
      );
      expect(MediaPaths.resolve(root, rel).existsSync(), isTrue);
    });

    test('FR-STO-06 a segment whose file is missing refuses Delete local '
        'copies', () async {
      final conf = await t.conference();
      final act = await t.activity(conf.id);
      final kept = MediaPaths.segment(conf.id, act.id, 1);
      final gone = MediaPaths.segment(conf.id, act.id, 2);
      await segment(act.id, kept, 1000);
      await segment(act.id, gone, 1000);
      MediaPaths.resolve(root, gone).deleteSync();
      await exported(conf.id);

      expect(
        (await service.analyse()).conferences.single.deleteBlockedReason,
        contains('missing'),
      );
      await expectLater(
        service.previewDeleteLocalCopies(conferenceId: conf.id),
        throwsA(isA<StorageManagerException>()),
      );
      expect(MediaPaths.resolve(root, kept).existsSync(), isTrue);
    });

    test('FR-STO-06 an edit made while the export ran is not covered by '
        'it', () async {
      final conf = await t.conference();
      final act = await t.activity(conf.id);
      await segment(act.id, MediaPaths.segment(conf.id, act.id, 1), 1000);

      t.clock.advance(const Duration(seconds: 1));
      final job = await t.exports.create(
        conferenceId: conf.id,
        scope: {...fullScope(), 'snapshot_at': t.clock().toIso8601String()},
        format: ExportFormat.folder,
        audioMode: ExportAudioMode.original,
      );
      t.clock.advance(const Duration(seconds: 1));
      await t.exports.markRunning(job.id);
      t.clock.advance(const Duration(minutes: 2));
      await t.media.addBookmark(
        activityId: act.id,
        source: BookmarkSource.ui,
        label: 'Added during the export',
      );
      t.clock.advance(const Duration(minutes: 2));
      await t.exports.complete(job.id, VerificationLevel.checksum);

      expect(
        (await service.analyse())
            .conferences
            .single
            .activities
            .single
            .deleteBlockedReason,
        contains('changed after'),
      );
      await expectLater(
        service.deleteLocalCopies(conferenceId: conf.id, activityId: act.id),
        throwsA(isA<StorageManagerException>()),
      );
    });

    test('FR-STO-06 a cut added after the export refuses Delete local '
        'copies', () async {
      final conf = await t.conference();
      final act = await t.activity(conf.id);
      await segment(act.id, MediaPaths.segment(conf.id, act.id, 1), 1000);
      await exported(conf.id);
      expect(
        (await service.analyse()).conferences.single.deleteBlockedReason,
        isNull,
      );

      t.clock.advance(const Duration(minutes: 1));
      await t.cuts.add(act.id, startOffsetMs: 0, endOffsetMs: 5000);
      expect(
        (await service.analyse()).conferences.single.deleteBlockedReason,
        contains('changed after'),
      );
      await expectLater(
        service.deleteLocalCopies(conferenceId: conf.id),
        throwsA(isA<StorageManagerException>()),
      );
    });

    test('FR-STO-06 a cut removed after the export refuses Delete local '
        'copies', () async {
      final conf = await t.conference();
      final act = await t.activity(conf.id);
      await segment(act.id, MediaPaths.segment(conf.id, act.id, 1), 1000);
      final cut = await t.cuts.add(act.id, startOffsetMs: 0, endOffsetMs: 5000);
      await exported(conf.id);
      expect(
        (await service.analyse()).conferences.single.deleteBlockedReason,
        isNull,
      );

      t.clock.advance(const Duration(minutes: 1));
      await t.cuts.remove(cut.id);
      expect(
        (await service.analyse()).conferences.single.deleteBlockedReason,
        contains('changed after'),
      );
    });

    test('FR-STO-06 a delete that fails on a locked file can be retried and '
        'finishes', () async {
      final conf = await t.conference();
      final act = await t.activity(conf.id);
      final first = MediaPaths.segment(conf.id, act.id, 1);
      final second = MediaPaths.segment(conf.id, act.id, 2);
      await segment(act.id, first, 1000);
      await segment(act.id, second, 2000);
      await exported(conf.id);
      locked.add(MediaPaths.resolve(root, second).path);

      var res = await service.deleteLocalCopies(conferenceId: conf.id);
      expect(res.failedFiles, 1);
      expect(res.activitiesDeleted, 0);
      expect(MediaPaths.resolve(root, first).existsSync(), isFalse);
      expect(MediaPaths.resolve(root, second).existsSync(), isTrue);
      // Only the row of the file still on disk is kept.
      expect((await t.media.segmentsFor(act.id)).map((s) => s.filePath), [
        second,
      ]);
      expect(await t.conferences.get(conf.id), isNotNull);

      locked.clear();
      res = await service.deleteLocalCopies(conferenceId: conf.id);
      expect(res.failedFiles, 0);
      expect(res.activitiesDeleted, 1);
      expect(MediaPaths.resolve(root, second).existsSync(), isFalse);
      expect(await t.activities.get(act.id), isNull);
      expect(await t.conferences.get(conf.id), isNull);
    });

    test('FR-STO-06 a goal edited after the export refuses deleting the '
        'conference; its activities can still go on their own', () async {
      final conf = await t.conference();
      final goal = await t.conferences.addGoal(conf.id, 'Meet two vendors');
      final act = await t.activity(conf.id);
      await segment(act.id, MediaPaths.segment(conf.id, act.id, 1), 1000);
      await exported(conf.id);
      expect(
        (await service.analyse()).conferences.single.deleteBlockedReason,
        isNull,
      );

      t.clock.advance(const Duration(minutes: 1));
      await t.conferences.updateGoal(goal.id, text: 'Meet three vendors');
      final c = (await service.analyse()).conferences.single;
      expect(c.deleteBlockedReason, contains('goals changed'));
      expect(c.activities.single.deleteBlockedReason, isNull);
      await expectLater(
        service.deleteLocalCopies(conferenceId: conf.id),
        throwsA(isA<StorageManagerException>()),
      );
      expect(await t.activities.get(act.id), isNotNull);

      final res = await service.deleteLocalCopies(
        conferenceId: conf.id,
        activityId: act.id,
      );
      expect(res.activitiesDeleted, 1);
      expect(await t.conferences.get(conf.id), isNotNull);
    });

    test('FR-STO-06 a goal removed or conference details edited after the '
        'export refuse deleting the conference', () async {
      final conf = await t.conference();
      final goal = await t.conferences.addGoal(conf.id, 'Meet two vendors');
      final act = await t.activity(conf.id);
      await segment(act.id, MediaPaths.segment(conf.id, act.id, 1), 1000);
      await exported(conf.id);

      t.clock.advance(const Duration(minutes: 1));
      await t.conferences.deleteGoal(goal.id);
      expect(
        (await service.analyse()).conferences.single.deleteBlockedReason,
        contains('goals changed'),
      );

      await exported(conf.id);
      expect(
        (await service.analyse()).conferences.single.deleteBlockedReason,
        isNull,
      );
      t.clock.advance(const Duration(minutes: 1));
      await t.conferences.update(
        conf.id,
        const ConferencesCompanion(venue: Value('ExCeL London')),
      );
      expect(
        (await service.analyse()).conferences.single.deleteBlockedReason,
        contains('details or goals changed'),
      );
    });

    test('FR-STO-06 a segment finalised after the export took its snapshot '
        'but before the job was created blocks deletion', () async {
      final conf = await t.conference();
      final act = await t.activity(conf.id);
      await segment(act.id, MediaPaths.segment(conf.id, act.id, 1), 1000);

      t.clock.advance(const Duration(seconds: 1));
      final snapshotAt = t.clock();
      // The export is planning; meanwhile the next segment finalises.
      t.clock.advance(const Duration(milliseconds: 200));
      await segment(act.id, MediaPaths.segment(conf.id, act.id, 2), 1000);
      t.clock.advance(const Duration(milliseconds: 200));
      final job = await t.exports.create(
        conferenceId: conf.id,
        scope: {...fullScope(), 'snapshot_at': snapshotAt.toIso8601String()},
        format: ExportFormat.folder,
        audioMode: ExportAudioMode.original,
      );
      t.clock.advance(const Duration(seconds: 5));
      await t.exports.complete(job.id, VerificationLevel.checksum);

      expect(
        (await service.analyse())
            .conferences
            .single
            .activities
            .single
            .deleteBlockedReason,
        contains('changed after'),
      );
      await expectLater(
        service.deleteLocalCopies(conferenceId: conf.id, activityId: act.id),
        throwsA(isA<StorageManagerException>()),
      );
    });

    test('FR-STO-06 an export without a recorded snapshot time never allows '
        'deleting', () async {
      final conf = await t.conference();
      final act = await t.activity(conf.id);
      await segment(act.id, MediaPaths.segment(conf.id, act.id, 1), 1000);
      t.clock.advance(const Duration(minutes: 1));
      final job = await t.exports.create(
        conferenceId: conf.id,
        scope: fullScope(),
        format: ExportFormat.folder,
        audioMode: ExportAudioMode.original,
      );
      await t.exports.complete(job.id, VerificationLevel.checksum);

      final c = (await service.analyse()).conferences.single;
      expect(c.activities.single.deleteBlockedReason, contains('Export again'));
      expect(c.deleteBlockedReason, contains('earlier version'));
    });

    test('FR-STO-06 FR-REC-09 a paused recording refuses deleting its '
        'activity and conference', () async {
      final conf = await t.conference();
      final act = await t.activity(conf.id);
      final recorder = RecordingService(
        engine: FakeCaptureEngine(),
        activities: t.activities,
        media: t.media,
        mediaRoot: () async => root,
        platform: CapturePlatform.android,
        clock: t.clock.call,
      );
      addTearDown(recorder.dispose);
      held = () => recorder.status.state.holdsActivity
          ? recorder.status.activityId
          : null;

      await recorder.start(act.id);
      t.clock.advance(const Duration(minutes: 1));
      await recorder.pause();
      expect(recorder.status.state, RecordingState.paused);
      await exported(conf.id, scope: fullScope(includePrivate: true));

      final c = (await service.analyse()).conferences.single;
      expect(
        c.activities.single.deleteBlockedReason,
        contains('Stop the recording'),
      );
      expect(c.deleteBlockedReason, contains('Stop the recording'));
      await expectLater(
        service.deleteLocalCopies(conferenceId: conf.id, activityId: act.id),
        throwsA(isA<StorageManagerException>()),
      );
      await expectLater(
        service.deleteLocalCopies(conferenceId: conf.id),
        throwsA(isA<StorageManagerException>()),
      );
      expect(await t.activities.get(act.id), isNotNull);
    });

    test('FR-STO-06 a photo whose full-size file is missing refuses Delete '
        'local copies and keeps its thumbnail', () async {
      final conf = await t.conference();
      final act = await t.activity(conf.id);
      await segment(act.id, MediaPaths.segment(conf.id, act.id, 1), 1000);
      await photo(conf.id, act.id, 'photo1');
      MediaPaths.resolve(
        root,
        MediaPaths.photo(conf.id, act.id, 'photo1'),
      ).deleteSync();
      final thumb = MediaPaths.resolve(
        root,
        MediaPaths.thumbnail(conf.id, act.id, 'photo1'),
      );
      await exported(conf.id);

      final c = (await service.analyse()).conferences.single;
      expect(c.activities.single.deleteBlockedReason, contains('photo'));
      expect(c.deleteBlockedReason, contains('photo'));
      await expectLater(
        service.deleteLocalCopies(conferenceId: conf.id, activityId: act.id),
        throwsA(isA<StorageManagerException>()),
      );
      expect(thumb.existsSync(), isTrue);
      expect(await t.media.photosFor(act.id), hasLength(1));
    });

    for (final lockThumbnail in [true, false]) {
      test('FR-STO-06 a locked '
          '${lockThumbnail ? 'thumbnail' : 'full-size photo'} keeps the '
          'photo file and row together, and a retry finishes', () async {
        final conf = await t.conference();
        final act = await t.activity(conf.id);
        await segment(act.id, MediaPaths.segment(conf.id, act.id, 1), 1000);
        await photo(conf.id, act.id, 'photo1');
        final full = MediaPaths.resolve(
          root,
          MediaPaths.photo(conf.id, act.id, 'photo1'),
        );
        final thumb = MediaPaths.resolve(
          root,
          MediaPaths.thumbnail(conf.id, act.id, 'photo1'),
        );
        await exported(conf.id);
        locked.add((lockThumbnail ? thumb : full).path);

        var res = await service.deleteLocalCopies(conferenceId: conf.id);
        expect(res.failedFiles, 1);
        expect(res.activitiesDeleted, 0);
        // The original and its row stay together.
        expect(full.existsSync(), isTrue);
        expect(thumb.existsSync(), lockThumbnail);
        expect(await t.media.photosFor(act.id), hasLength(1));
        expect(
          (await service.analyse())
              .conferences
              .single
              .activities
              .single
              .deleteBlockedReason,
          isNull,
        );

        locked.clear();
        res = await service.deleteLocalCopies(conferenceId: conf.id);
        expect(res.failedFiles, 0);
        expect(res.activitiesDeleted, 1);
        expect(full.existsSync(), isFalse);
        expect(thumb.existsSync(), isFalse);
        expect(await t.conferences.get(conf.id), isNull);
      });
    }

    test('FR-STO-06 ADR-036 a locked waveform on one side of a split keeps '
        'the shared recording for both sides, and a retry finishes', () async {
      final conf = await t.conference();
      final part1 = await t.activity(conf.id, title: 'Panel');
      final part2 = await t.activity(conf.id, title: 'Panel (Part 2)');
      final shared = MediaPaths.segment(conf.id, part1.id, 1);
      await segment(part1.id, shared, 8000);
      final seg2 = await segment(part2.id, shared, 8000);
      final wave2 = write(MediaPaths.waveform(conf.id, part2.id, seg2), 100);
      await exported(conf.id);
      locked.add(wave2.path);

      var res = await service.deleteLocalCopies(conferenceId: conf.id);
      expect(res.failedFiles, 1);
      expect(res.activitiesDeleted, 0);
      final audio = MediaPaths.resolve(root, shared);
      expect(audio.existsSync(), isTrue);
      expect((await t.media.segmentsFor(part1.id)).single.filePath, shared);
      expect((await t.media.segmentsFor(part2.id)).single.filePath, shared);

      locked.clear();
      res = await service.deleteLocalCopies(conferenceId: conf.id);
      expect(res.failedFiles, 0);
      expect(res.activitiesDeleted, 2);
      expect(audio.existsSync(), isFalse);
      expect(wave2.existsSync(), isFalse);
      expect(await t.conferences.get(conf.id), isNull);
    });

    test('FR-STO-06 a photo whose thumbnail was already missing loses its '
        'row with its file when another file is locked; the retry '
        'finishes', () async {
      final conf = await t.conference();
      final act = await t.activity(conf.id);
      final rel = MediaPaths.segment(conf.id, act.id, 1);
      await segment(act.id, rel, 1000);
      await photo(conf.id, act.id, 'photo1');
      MediaPaths.resolve(
        root,
        MediaPaths.thumbnail(conf.id, act.id, 'photo1'),
      ).deleteSync();
      final full = MediaPaths.resolve(
        root,
        MediaPaths.photo(conf.id, act.id, 'photo1'),
      );
      await exported(conf.id);
      locked.add(MediaPaths.resolve(root, rel).path);

      var res = await service.deleteLocalCopies(conferenceId: conf.id);
      expect(res.failedFiles, 1);
      expect(res.activitiesDeleted, 0);
      expect(full.existsSync(), isFalse);
      expect(await t.media.photosFor(act.id), isEmpty);
      expect(await t.media.segmentsFor(act.id), hasLength(1));
      expect(
        (await service.analyse())
            .conferences
            .single
            .activities
            .single
            .deleteBlockedReason,
        isNull,
      );

      locked.clear();
      res = await service.deleteLocalCopies(conferenceId: conf.id);
      expect(res.failedFiles, 0);
      expect(res.activitiesDeleted, 1);
      expect(MediaPaths.resolve(root, rel).existsSync(), isFalse);
      expect(await t.conferences.get(conf.id), isNull);
    });
  });
}

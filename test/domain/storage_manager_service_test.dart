import 'dart:io';

import 'package:attenlume/data/filesystem/media_paths.dart';
import 'package:attenlume/domain/models/enums.dart';
import 'package:attenlume/domain/models/storage_breakdown.dart';
import 'package:attenlume/domain/services/permanent_trim_service.dart';
import 'package:attenlume/domain/services/private_notes.dart';
import 'package:attenlume/domain/services/storage_manager_service.dart';
import 'package:attenlume/platform/audio_trimmer/mp4_sample_trimmer.dart';
import 'package:attenlume/platform/storage/free_space_probe.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

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

  setUp(() {
    t = TestData();
    sandbox = Directory.systemTemp.createTempSync('attenlume_storage_');
    root = Directory(p.join(sandbox.path, 'media'))..createSync();
    temp = Directory(p.join(sandbox.path, 'cache'))..createSync();
    exportRunning = false;
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
      mediaRoot: () async => root,
      tempRoot: () async => temp,
      freeSpaceProbe: const FixedFreeSpace(),
      removeOriginals: trim.removeOriginals,
      exportRunning: () => exportRunning,
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
    final job = await t.exports.create(
      conferenceId: confId,
      scope: scope ?? fullScope(),
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
        'rows ("delete means delete") but keeps partial recordings', () async {
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
      expect(preview.otherFiles, 2);
      expect(preview.bookmarkCount, 1);
      expect(preview.recoveryFilesKept, 1);
      expect(preview.totalBytes, 6000 + 5000 + 800 + 100 + 900);

      final res = await service.deleteLocalCopies(conferenceId: conf.id);
      expect(res.filesDeleted, 5);
      expect(res.bytesFreed, preview.totalBytes);
      expect(res.failedFiles, 0);

      expect(MediaPaths.resolve(root, segRel).existsSync(), isFalse);
      expect(wave.existsSync(), isFalse);
      expect(original.existsSync(), isFalse);
      expect(partial.existsSync(), isTrue);
      expect(await t.activities.get(act.id), isNull);
      expect(await t.conferences.get(conf.id), isNull);
      expect(await t.media.bookmarksFor(act.id), isEmpty);
    });
  });
}

import 'dart:io';

import 'package:attenlume/data/filesystem/media_paths.dart';
import 'package:attenlume/domain/models/enums.dart';
import 'package:attenlume/domain/models/media.dart';
import 'package:attenlume/domain/models/storage_breakdown.dart';
import 'package:attenlume/domain/services/storage_manager_service.dart';
import 'package:attenlume/platform/storage/free_space_probe.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../fixtures/fixtures.dart';

class FakeFreeSpaceProbe implements FreeSpaceProbe {
  FakeFreeSpaceProbe({
    this.availableBytes = 50 * 1024 * 1024 * 1024,
    this.totalBytes = 128 * 1024 * 1024 * 1024,
  });

  int? availableBytes;
  int? totalBytes;

  @override
  Future<FreeSpace?> query(String path) async {
    if (availableBytes == null || totalBytes == null) return null;
    return FreeSpace(availableBytes: availableBytes!, totalBytes: totalBytes!);
  }
}

void main() {
  late TestData t;
  late Directory tempMediaDir;
  late FakeFreeSpaceProbe fakeProbe;
  late StorageManagerService service;

  setUp(() async {
    t = TestData();
    tempMediaDir = await Directory.systemTemp.createTemp(
      'attenlume_storage_test_',
    );
    fakeProbe = FakeFreeSpaceProbe();
    service = StorageManagerService(
      conferences: t.conferences,
      activities: t.activities,
      media: t.media,
      exports: t.exports,
      mediaRoot: () async => tempMediaDir,
      freeSpaceProbe: fakeProbe,
    );
  });

  tearDown(() async {
    await t.close();
    if (tempMediaDir.existsSync()) {
      await tempMediaDir.delete(recursive: true);
    }
  });

  Future<RecordingSegment> createTestSegment(
    String activityId, {
    required String filePath,
    required int bytes,
    DateTime? start,
  }) async {
    final now = start ?? DateTime.utc(2026, 11, 4, 9, 30);
    final seg = await t.media.startSegment(
      activityId: activityId,
      filePath: filePath,
      requestedProfile: RecordingProfile.balanced,
      codec: 'aac_lc',
      container: 'm4a',
      channelCount: 1,
      sampleRateHz: 48000,
      requestedBitrateBps: 48000,
      inputRoute: 'built_in',
      startUtc: now,
    );
    return t.media.finaliseSegment(
      seg.id,
      endUtc: now.add(const Duration(seconds: 30)),
      endReason: SegmentEndReason.userStop,
      durationMs: 30000,
      bytes: bytes,
      sha256: 'f' * 64,
      observedBitrateBps: 48000,
    );
  }

  group('StorageManagerService analyzeStorage (FR-STO-05)', () {
    test('FR-STO-05 reports empty breakdown when no data exists', () async {
      final breakdown = await service.analyzeStorage();
      expect(breakdown.appTotalBytes, 0);
      expect(breakdown.conferences, isEmpty);
      expect(breakdown.totalDeviceFreeBytes, 50 * 1024 * 1024 * 1024);
      expect(breakdown.totalDeviceCapacityBytes, 128 * 1024 * 1024 * 1024);
      expect(breakdown.safeTemporaryBytes, 0);
      expect(breakdown.keptOriginalsCount, 0);
    });

    test('FR-STO-05 calculates breakdown across audio, photos, thumbnails, kept originals and waveforms', () async {
      final conf = await t.conference(name: 'Data Summit London');
      final act = await t.activity(conf.id, title: 'Keynote');

      // 1. Audio segment: 10,000 bytes.
      final segPath = MediaPaths.segment(conf.id, act.id, 1);
      final segFile = MediaPaths.resolve(tempMediaDir, segPath);
      await segFile.parent.create(recursive: true);
      await segFile.writeAsBytes(List.filled(10000, 1));
      await createTestSegment(act.id, filePath: segPath, bytes: 10000);

      // 2. Photo: 5,000 bytes.
      final photoRel = MediaPaths.photo(conf.id, act.id, 'photo1');
      final thumbRel = MediaPaths.thumbnail(conf.id, act.id, 'photo1');
      final pFile = MediaPaths.resolve(tempMediaDir, photoRel);
      await pFile.parent.create(recursive: true);
      await pFile.writeAsBytes(List.filled(5000, 2));

      final thumbFile = MediaPaths.resolve(tempMediaDir, thumbRel);
      await thumbFile.parent.create(recursive: true);
      await thumbFile.writeAsBytes(List.filled(800, 3));

      await t.media.addPhoto(
        id: 'photo1',
        activityId: act.id,
        filePath: photoRel,
        thumbnailPath: thumbRel,
        takenUtc: DateTime.utc(2026, 11, 4, 9, 30),
        source: PhotoSource.inApp,
        bytes: 5000,
      );

      // 3. Kept original in audio/originals/: 20,000 bytes.
      final origDir = Directory(
        p.join(tempMediaDir.path, MediaPaths.originalsFolder(conf.id, act.id)),
      );
      await origDir.create(recursive: true);
      final origFile = File(p.join(origDir.path, 'segment-001-orig.m4a'));
      await origFile.writeAsBytes(List.filled(20000, 4));

      // 4. Waveform summary in waveforms/: 1,200 bytes.
      final waveDir = Directory(
        p.join(
          tempMediaDir.path,
          MediaPaths.activityFolder(conf.id, act.id),
          'waveforms',
        ),
      );
      await waveDir.create(recursive: true);
      final waveFile = File(p.join(waveDir.path, 'seg1.wave'));
      await waveFile.writeAsBytes(List.filled(1200, 5));

      final breakdown = await service.analyzeStorage();

      expect(breakdown.conferences.length, 1);
      final confBreakdown = breakdown.conferences.single;
      expect(confBreakdown.conferenceName, 'Data Summit London');
      expect(confBreakdown.exportStatus, ExportStatus.notExported);

      // Activity breakdown
      expect(confBreakdown.activities.length, 1);
      final actBreakdown = confBreakdown.activities.single;
      expect(actBreakdown.sizes.audioBytes, 10000);
      expect(actBreakdown.sizes.photoBytes, 5000);
      expect(actBreakdown.sizes.thumbnailBytes, 800);
      expect(actBreakdown.sizes.keptOriginalBytes, 20000);
      expect(actBreakdown.sizes.derivedBytes, 1200);
      expect(actBreakdown.keptOriginalsCount, 1);
      expect(actBreakdown.totalBytes, 10000 + 5000 + 800 + 20000 + 1200);

      // Conference & App totals
      expect(confBreakdown.sizes.audioBytes, 10000);
      expect(confBreakdown.sizes.photoBytes, 5000);
      expect(confBreakdown.sizes.thumbnailBytes, 800);
      expect(confBreakdown.sizes.keptOriginalBytes, 20000);
      expect(confBreakdown.sizes.derivedBytes, 1200);
      expect(confBreakdown.totalBytes, actBreakdown.totalBytes);

      expect(breakdown.keptOriginalsCount, 1);
      expect(breakdown.keptOriginalsTotalBytes, 20000);
      expect(breakdown.safeTemporaryBytes, 1200); // waveforms
    });

    test('FR-STO-05 shared audio files are deduplicated across activities (ADR-036)', () async {
      final conf = await t.conference();
      final act1 = await t.activity(conf.id, title: 'Part 1');
      final act2 = await t.activity(conf.id, title: 'Part 2');

      // Both activities share the exact same audio file (as resulting from split, ADR-036)
      const sharedPath = 'conferences/c1/activities/a1/audio/segment-001.m4a';
      final sharedFile = MediaPaths.resolve(tempMediaDir, sharedPath);
      await sharedFile.parent.create(recursive: true);
      await sharedFile.writeAsBytes(List.filled(15000, 1));

      await createTestSegment(act1.id, filePath: sharedPath, bytes: 15000);
      await createTestSegment(act2.id, filePath: sharedPath, bytes: 15000);

      final breakdown = await service.analyzeStorage();
      final confBreakdown = breakdown.conferences.single;

      // Each activity reports using the 15,000 bytes
      expect(confBreakdown.activities[0].sizes.audioBytes, 15000);
      expect(confBreakdown.activities[1].sizes.audioBytes, 15000);

      // BUT conference total and app total count the file ONLY ONCE
      expect(confBreakdown.sizes.audioBytes, 15000);
      expect(breakdown.appTotalBytes, 15000);
    });

    test('FR-STO-05 export status ranks completed jobs correctly', () async {
      final conf = await t.conference();
      await t.activity(conf.id);

      // Initially not exported
      var breakdown = await service.analyzeStorage();
      expect(
        breakdown.conferences.single.exportStatus,
        ExportStatus.notExported,
      );

      // 1. Local export completed without checksum
      final job1 = await t.exports.create(
        conferenceId: conf.id,
        scope: const {'kind': 'conference'},
        format: ExportFormat.zip,
        audioMode: ExportAudioMode.original,
        destination: ExportDestination.local,
      );
      await t.exports.complete(job1.id, VerificationLevel.none);

      breakdown = await service.analyzeStorage();
      expect(
        breakdown.conferences.single.exportStatus,
        ExportStatus.exportedLocally,
      );

      // 2. Cloud upload completed
      final job2 = await t.exports.create(
        conferenceId: conf.id,
        scope: const {'kind': 'conference'},
        format: ExportFormat.folder,
        audioMode: ExportAudioMode.original,
        destination: ExportDestination.googleDrive,
      );
      await t.exports.complete(job2.id, VerificationLevel.size);

      breakdown = await service.analyzeStorage();
      expect(breakdown.conferences.single.exportStatus, ExportStatus.uploaded);

      // 3. Verified export completed with checksum
      final job3 = await t.exports.create(
        conferenceId: conf.id,
        scope: const {'kind': 'conference'},
        format: ExportFormat.folder,
        audioMode: ExportAudioMode.original,
        destination: ExportDestination.local,
      );
      await t.exports.complete(job3.id, VerificationLevel.checksum);

      breakdown = await service.analyzeStorage();
      expect(breakdown.conferences.single.exportStatus, ExportStatus.verified);
      expect(breakdown.conferences.single.exportStatus.isVerified, isTrue);
    });

    test('FR-STO-05 activity-scoped export jobs assign status to relevant activities only', () async {
      final conf = await t.conference();
      final act1 = await t.activity(conf.id, title: 'Act 1');
      final act2 = await t.activity(conf.id, title: 'Act 2');

      final job = await t.exports.create(
        conferenceId: conf.id,
        scope: {
          'kind': 'activities',
          'activity_ids': [act1.id],
        },
        format: ExportFormat.folder,
        audioMode: ExportAudioMode.original,
      );
      await t.exports.complete(job.id, VerificationLevel.checksum);

      final breakdown = await service.analyzeStorage();
      final confBreakdown = breakdown.conferences.single;

      final act1Breakdown = confBreakdown.activities.singleWhere(
        (a) => a.activityId == act1.id,
      );
      final act2Breakdown = confBreakdown.activities.singleWhere(
        (a) => a.activityId == act2.id,
      );

      expect(act1Breakdown.exportStatus, ExportStatus.verified);
      expect(act2Breakdown.exportStatus, ExportStatus.notExported);
    });
  });

  group('StorageManagerService safe cleanup (FR-STO-06)', () {
    test('FR-STO-06 FR-REC-08 cleanup preserves orphaned partial recordings, originals and photos', () async {
      final conf = await t.conference();
      final act = await t.activity(conf.id);

      // Create permanent recording
      final segPath = MediaPaths.segment(conf.id, act.id, 1);
      final segFile = MediaPaths.resolve(tempMediaDir, segPath);
      await segFile.parent.create(recursive: true);
      await segFile.writeAsBytes(List.filled(1000, 1));
      await createTestSegment(act.id, filePath: segPath, bytes: 1000);

      // Create photo
      final photoPath = MediaPaths.photo(conf.id, act.id, 'p1');
      final photoFile = MediaPaths.resolve(tempMediaDir, photoPath);
      await photoFile.parent.create(recursive: true);
      await photoFile.writeAsBytes(List.filled(2000, 2));

      // Create temporary safe files:
      // 1. Waveform summary
      final wavePath = MediaPaths.waveform(conf.id, act.id, 'seg1');
      final waveFile = MediaPaths.resolve(tempMediaDir, wavePath);
      await waveFile.parent.create(recursive: true);
      await waveFile.writeAsBytes(List.filled(300, 3));

      // 2. Orphaned partial file
      final partialFile = MediaPaths.resolve(
        tempMediaDir,
        MediaPaths.partial(MediaPaths.segment(conf.id, act.id, 2)),
      );
      await partialFile.parent.create(recursive: true);
      await partialFile.writeAsBytes(List.filled(500, 4));

      // 3. Export scratch file
      final scratchDir = Directory(p.join(tempMediaDir.path, 'exports'));
      await scratchDir.create(recursive: true);
      final scratchFile = File(p.join(scratchDir.path, 'temp_archive.zip'));
      await scratchFile.writeAsBytes(List.filled(400, 5));

      final res = await service.clearSafeTemporaryFiles();
      expect(res.filesDeleted, 2);
      expect(res.bytesFreed, 300 + 400);

      // Permanent files must stay intact
      expect(segFile.existsSync(), isTrue);
      expect(photoFile.existsSync(), isTrue);

      // Safe temporary files must be gone
      expect(waveFile.existsSync(), isFalse);
      expect(partialFile.readAsBytesSync(), List.filled(500, 4));
      expect(scratchFile.existsSync(), isFalse);
    });

    test('FR-STO-06 removeKeptOriginals removes unlinked files in audio/originals/ and preserves files named by segments', () async {
      final conf = await t.conference();
      final act = await t.activity(conf.id);

      final origDir = Directory(
        p.join(tempMediaDir.path, MediaPaths.originalsFolder(conf.id, act.id)),
      );
      await origDir.create(recursive: true);

      // File 1: true kept original, no segment row names it
      final unlinkedOriginal = File(
        p.join(origDir.path, 'trimmed_original.m4a'),
      );
      await unlinkedOriginal.writeAsBytes(List.filled(7000, 1));

      // File 2: named by a segment row (edge case: segment still points to it)
      final namedPath = p.posix.join(
        MediaPaths.activityFolder(conf.id, act.id),
        'audio',
        'originals',
        'named_original.m4a',
      );
      final namedFile = MediaPaths.resolve(tempMediaDir, namedPath);
      await namedFile.parent.create(recursive: true);
      await namedFile.writeAsBytes(List.filled(3000, 2));

      await createTestSegment(act.id, filePath: namedPath, bytes: 3000);

      final res = await service.removeKeptOriginals();
      expect(res.filesDeleted, 1);
      expect(res.bytesFreed, 7000);

      expect(unlinkedOriginal.existsSync(), isFalse);
      expect(namedFile.existsSync(), isTrue);
    });
  });

  group('StorageManagerService Delete local copies (FR-STO-06, FR-STO-07)', () {
    test('FR-STO-06 preview and delete throw StorageManagerException when export is not verified', () async {
      final conf = await t.conference();
      await t.activity(conf.id);

      expect(
        () => service.previewDeleteLocalCopies(
          conferenceId: conf.id,
          keepLightweightIndex: true,
        ),
        throwsA(isA<StorageManagerException>()),
      );

      expect(
        () => service.deleteLocalCopies(
          conferenceId: conf.id,
          keepLightweightIndex: true,
        ),
        throwsA(isA<StorageManagerException>()),
      );
    });

    test('FR-STO-06 previewDeleteLocalCopies calculates preview numbers and preserves shared files (ADR-036)', () async {
      final conf = await t.conference();
      final act1 = await t.activity(conf.id, title: 'Session A');
      final act2 = await t.activity(conf.id, title: 'Session B');

      // Shared audio file between act1 and act2
      const sharedPath = 'conferences/c1/activities/a1/audio/shared.m4a';
      final sharedFile = MediaPaths.resolve(tempMediaDir, sharedPath);
      await sharedFile.parent.create(recursive: true);
      await sharedFile.writeAsBytes(List.filled(8000, 1));

      await createTestSegment(act1.id, filePath: sharedPath, bytes: 8000);
      await createTestSegment(act2.id, filePath: sharedPath, bytes: 8000);

      // Distinct audio file for act1
      final unsharedPath = MediaPaths.segment(conf.id, act1.id, 2);
      final unsharedFile = MediaPaths.resolve(tempMediaDir, unsharedPath);
      await unsharedFile.parent.create(recursive: true);
      await unsharedFile.writeAsBytes(List.filled(4000, 2));

      await createTestSegment(act1.id, filePath: unsharedPath, bytes: 4000);

      // Verified export for conference
      final job = await t.exports.create(
        conferenceId: conf.id,
        scope: const {'kind': 'conference'},
        format: ExportFormat.folder,
        audioMode: ExportAudioMode.original,
      );
      await t.exports.complete(job.id, VerificationLevel.checksum);

      // Preview delete for act1 only
      final preview = await service.previewDeleteLocalCopies(
        conferenceId: conf.id,
        activityId: act1.id,
        keepLightweightIndex: true,
      );

      expect(
        preview.audioFilesCount,
        1,
      ); // Only the unshared file is eligible to delete
      expect(preview.audioBytes, 4000);
      expect(preview.sharedFilesPreservedCount, 1); // Shared file is preserved!
      expect(preview.totalBytesToFree, 4000);
    });

    test('FR-STO-06 & FR-STO-07 deleteLocalCopies with keepLightweightIndex=true deletes audio and full photos but keeps thumbnails, bookmarks, notes, and activity rows', () async {
      final conf = await t.conference();
      final act = await t.activity(conf.id, title: 'Keynote');

      // Add audio
      final segPath = MediaPaths.segment(conf.id, act.id, 1);
      final segFile = MediaPaths.resolve(tempMediaDir, segPath);
      await segFile.parent.create(recursive: true);
      await segFile.writeAsBytes(List.filled(6000, 1));
      await createTestSegment(act.id, filePath: segPath, bytes: 6000);

      // Add photo + thumbnail
      final photoPath = MediaPaths.photo(conf.id, act.id, 'p1');
      final thumbPath = MediaPaths.thumbnail(conf.id, act.id, 'p1');
      final pFile = MediaPaths.resolve(tempMediaDir, photoPath);
      final tFile = MediaPaths.resolve(tempMediaDir, thumbPath);
      await pFile.parent.create(recursive: true);
      await pFile.writeAsBytes(List.filled(3000, 2));
      await tFile.parent.create(recursive: true);
      await tFile.writeAsBytes(List.filled(500, 3));

      await t.media.addPhoto(
        id: 'p1',
        activityId: act.id,
        filePath: photoPath,
        thumbnailPath: thumbPath,
        takenUtc: DateTime.utc(2026, 11, 4, 10),
        source: PhotoSource.inApp,
        bytes: 3000,
      );

      // Add bookmark
      await t.media.addBookmark(
        activityId: act.id,
        source: BookmarkSource.ui,
        label: 'Important slide',
      );

      // Verified export
      final job = await t.exports.create(
        conferenceId: conf.id,
        scope: const {'kind': 'conference'},
        format: ExportFormat.folder,
        audioMode: ExportAudioMode.original,
      );
      await t.exports.complete(job.id, VerificationLevel.checksum);

      // Execute delete local copies with lightweight index preserved
      final res = await service.deleteLocalCopies(
        conferenceId: conf.id,
        activityId: act.id,
        keepLightweightIndex: true,
      );

      expect(res.keptIndex, isTrue);
      expect(res.bytesFreed, 6000 + 3000);

      // Files on disk:
      expect(segFile.existsSync(), isFalse); // Audio deleted
      expect(pFile.existsSync(), isFalse); // Full photo deleted
      expect(tFile.existsSync(), isTrue); // Thumbnail KEPT!

      // Database rows:
      final remainingAct = await t.activities.get(act.id);
      expect(remainingAct, isNotNull); // Activity record KEPT
      final remainingBookmarks = await t.media.bookmarksFor(act.id);
      expect(remainingBookmarks.length, 1); // Bookmarks KEPT
      final remainingPhotos = await t.media.photosFor(act.id);
      expect(remainingPhotos.length, 1); // Photo row with thumbnail KEPT
      final remainingSegs = await t.media.segmentsFor(act.id);
      expect(remainingSegs, isEmpty); // Audio segment row removed
    });

    test('FR-STO-06 & FR-STO-07 deleteLocalCopies with keepLightweightIndex=false deletes all media files and database rows ("delete means delete")', () async {
      final conf = await t.conference();
      final act = await t.activity(conf.id, title: 'Panel');

      final segPath = MediaPaths.segment(conf.id, act.id, 1);
      final segFile = MediaPaths.resolve(tempMediaDir, segPath);
      await segFile.parent.create(recursive: true);
      await segFile.writeAsBytes(List.filled(4000, 1));
      await createTestSegment(act.id, filePath: segPath, bytes: 4000);

      final photoPath = MediaPaths.photo(conf.id, act.id, 'p1');
      final thumbPath = MediaPaths.thumbnail(conf.id, act.id, 'p1');
      final pFile = MediaPaths.resolve(tempMediaDir, photoPath);
      final tFile = MediaPaths.resolve(tempMediaDir, thumbPath);
      await pFile.parent.create(recursive: true);
      await pFile.writeAsBytes(List.filled(2000, 2));
      await tFile.parent.create(recursive: true);
      await tFile.writeAsBytes(List.filled(400, 3));

      await t.media.addPhoto(
        id: 'p1',
        activityId: act.id,
        filePath: photoPath,
        thumbnailPath: thumbPath,
        takenUtc: DateTime.utc(2026, 11, 4, 11),
        source: PhotoSource.inApp,
        bytes: 2000,
      );

      // Verified export
      final job = await t.exports.create(
        conferenceId: conf.id,
        scope: const {'kind': 'conference'},
        format: ExportFormat.folder,
        audioMode: ExportAudioMode.original,
      );
      await t.exports.complete(job.id, VerificationLevel.checksum);

      // Execute "delete means delete"
      final res = await service.deleteLocalCopies(
        conferenceId: conf.id,
        activityId: act.id,
        keepLightweightIndex: false,
      );

      expect(res.keptIndex, isFalse);
      expect(segFile.existsSync(), isFalse);
      expect(pFile.existsSync(), isFalse);
      expect(tFile.existsSync(), isFalse); // Thumbnail deleted

      final actAfter = await t.activities.get(act.id);
      expect(actAfter, isNull); // Activity deleted
    });
  });
}

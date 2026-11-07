import 'dart:io';

import 'package:attenlume/data/filesystem/export_writer.dart';
import 'package:attenlume/data/filesystem/media_paths.dart';
import 'package:attenlume/data/local_database/database_provider.dart';
import 'package:attenlume/data/repositories/repository_providers.dart';
import 'package:attenlume/domain/models/enums.dart';
import 'package:attenlume/domain/services/audio_import_service.dart';
import 'package:attenlume/domain/services/export_import_service.dart';
import 'package:attenlume/domain/services/export_service.dart';
import 'package:attenlume/features/capture/recording_providers.dart';
import 'package:attenlume/features/transcription/transcription_providers.dart';
import 'package:attenlume/platform/audio_import/audio_file_inspector.dart';
import 'package:attenlume/platform/audio_import/audio_file_picker.dart';
import 'package:crypto/crypto.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../fixtures/fake_free_space_probe.dart';
import '../fixtures/fixtures.dart';

class _FakePicker implements AudioFilePicker {
  _FakePicker([this.picked]);

  XFile? picked;

  @override
  Future<XFile?> pickAudio() async => picked;
}

class _FakeInspector implements AudioFileInspector {
  _FakeInspector({
    this.info = const InspectedAudioInfo(
      duration: Duration(minutes: 10, seconds: 30),
      channelCount: 2,
      sampleRateHz: 44100,
      codec: 'mp3',
      container: 'mp3',
      bitrateBps: 128000,
    ),
    this.shouldThrow = false,
  });

  InspectedAudioInfo info;
  bool shouldThrow;

  @override
  Future<InspectedAudioInfo> inspect(File file) async {
    if (shouldThrow) {
      throw const AudioInspectionException('Simulated unreadable file');
    }
    return info;
  }
}

Future<ExportWriteResult> _inlineWriter(
  ExportWritePlan plan, {
  void Function(ExportWriteProgress progress)? onProgress,
  Future<void>? cancel,
}) => writeExport(plan, onProgress: onProgress);

void main() {
  late TestData t;
  late Directory tempDir;
  late Directory mediaRoot;
  late Directory sourceDir;

  setUp(() async {
    t = TestData();
    tempDir = await Directory.systemTemp.createTemp('audio_import_test');
    mediaRoot = Directory(p.join(tempDir.path, 'media'))
      ..createSync(recursive: true);
    sourceDir = Directory(p.join(tempDir.path, 'source'))
      ..createSync(recursive: true);
  });

  tearDown(() async {
    await t.close();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  AudioImportService makeService({
    AudioFilePicker? picker,
    AudioFileInspector? inspector,
    FakeFreeSpaceProbe? freeSpace,
    bool Function()? isRecordingActive,
    int? safetyMarginBytes,
  }) {
    return AudioImportService(
      activities: t.activities,
      conferences: t.conferences,
      media: t.media,
      mediaRoot: () async => mediaRoot,
      picker: picker ?? const FileSelectorAudioPicker(),
      inspector: inspector ?? const DefaultAudioFileInspector(),
      freeSpace:
          freeSpace ??
          FakeFreeSpaceProbe(10 * 1024 * 1024 * 1024), // 10 GB free
      isRecordingActive: isRecordingActive ?? () => false,
      safetyMarginBytes:
          safetyMarginBytes ?? defaultAudioImportSafetyMarginBytes,
      clock: t.clock.call,
      newId: t.ids.call,
    );
  }

  test('P2-13 FR-TRN-03 successful import copies bytes exactly and leaves the source untouched', () async {
    final conf = await t.conference(name: 'Samlytics Conference 2026');

    // Create a source file in external storage
    final sourceBytes = List<int>.generate(8192, (i) => (i * 13 + 7) % 256);
    final sourceFile = File(p.join(sourceDir.path, 'Sample Lecture 01.mp3'));
    await sourceFile.writeAsBytes(sourceBytes, flush: true);
    final sourceSha = (await sha256.bind(sourceFile.openRead()).first)
        .toString();
    final sourceLastModified = sourceFile.lastModifiedSync();

    final picker = _FakePicker(XFile(sourceFile.path));
    final inspector = _FakeInspector(
      info: const InspectedAudioInfo(
        duration: Duration(minutes: 5, seconds: 12),
        channelCount: 2,
        sampleRateHz: 44100,
        codec: 'mp3',
        container: 'mp3',
        bitrateBps: 128000,
      ),
    );

    final service = makeService(picker: picker, inspector: inspector);
    final outcome = await service.importAudio(conferenceId: conf.id);

    expect(outcome, isA<AudioImportSuccess>());
    final success = outcome as AudioImportSuccess;

    // Verify activity metadata
    expect(success.activity.title, 'Sample Lecture 01');
    expect(success.activity.conferenceId, conf.id);
    expect(success.activity.status, ActivityStatus.completed);
    expect(success.activity.tags, contains(importedAudioTag));
    expect(isActivityImported(success.activity), isTrue);

    // Verify segment metadata
    expect(success.segment.activityId, success.activity.id);
    expect(success.segment.sequence, 1);
    expect(success.segment.state, SegmentState.finalised);
    expect(success.segment.inputRoute, importedInputRoute);
    expect(success.segment.container, 'mp3');
    expect(success.segment.codec, 'mp3');
    expect(success.segment.channelCount, 2);
    expect(success.segment.sampleRateHz, 44100);
    expect(
      success.segment.durationMs,
      const Duration(minutes: 5, seconds: 12).inMilliseconds,
    );
    expect(success.segment.bytes, sourceBytes.length);
    expect(success.segment.sha256, sourceSha);
    expect(isActivityImported(success.activity, [success.segment]), isTrue);

    // Verify imported file in media storage
    final storedFile = MediaPaths.resolve(mediaRoot, success.segment.filePath);
    expect(storedFile.existsSync(), isTrue);
    expect(storedFile.readAsBytesSync(), sourceBytes);
    expect(
      (await sha256.bind(storedFile.openRead()).first).toString(),
      sourceSha,
    );

    // Verify source file was untouched: never moved, modified or deleted
    expect(sourceFile.existsSync(), isTrue);
    expect(sourceFile.readAsBytesSync(), sourceBytes);
    expect(sourceFile.lastModifiedSync(), sourceLastModified);
  });

  test('P2-13 FR-TRN-03 unsupported extension rejected with plain message and leaves storage untouched', () async {
    final conf = await t.conference(name: 'Samlytics Conference 2026');
    final unsupportedFile = File(p.join(sourceDir.path, 'document.pdf'))
      ..writeAsStringSync('not an audio file');

    final picker = _FakePicker(XFile(unsupportedFile.path));
    final service = makeService(picker: picker);

    final outcome = await service.importAudio(conferenceId: conf.id);
    expect(outcome, isA<AudioImportFailure>());

    final failure = outcome as AudioImportFailure;
    expect(failure.reason, AudioImportFailureReason.unsupportedFormat);
    expect(
      failure.userMessage,
      'Unsupported audio format. Attenlume imports .m4a, .mp3, .wav and .aac files.',
    );

    // No activity created in DB
    final acts = await t.activities.listForConference(conf.id);
    expect(acts, isEmpty);

    // No files created in media storage
    expect(mediaRoot.listSync(recursive: true), isEmpty);

    // Source untouched
    expect(unsupportedFile.existsSync(), isTrue);
  });

  test('P2-13 FR-TRN-03 unreadable file rejected with plain message and leaves storage untouched', () async {
    final conf = await t.conference(name: 'Samlytics Conference 2026');
    final damagedFile = File(p.join(sourceDir.path, 'damaged.wav'))
      ..writeAsBytesSync([1, 2, 3]);

    final picker = _FakePicker(XFile(damagedFile.path));
    final inspector = _FakeInspector(shouldThrow: true);
    final service = makeService(picker: picker, inspector: inspector);

    final outcome = await service.importAudio(conferenceId: conf.id);
    expect(outcome, isA<AudioImportFailure>());

    final failure = outcome as AudioImportFailure;
    expect(failure.reason, AudioImportFailureReason.unreadableFile);
    expect(
      failure.userMessage,
      'The audio file could not be read. Check the file is not damaged.',
    );

    final acts = await t.activities.listForConference(conf.id);
    expect(acts, isEmpty);
    expect(mediaRoot.listSync(recursive: true), isEmpty);
    expect(damagedFile.existsSync(), isTrue);
  });

  test('P2-13 FR-TRN-03 low free space rejected with plain message and leaves storage untouched', () async {
    final conf = await t.conference(name: 'Samlytics Conference 2026');
    final audioFile = File(p.join(sourceDir.path, 'large.m4a'))
      ..writeAsBytesSync(List<int>.filled(50 * 1024 * 1024, 0)); // 50 MB file

    final picker = _FakePicker(XFile(audioFile.path));
    final inspector = _FakeInspector(
      info: const InspectedAudioInfo(
        duration: Duration(minutes: 60),
        channelCount: 1,
        sampleRateHz: 48000,
        codec: 'aac_lc',
        container: 'm4a',
      ),
    );

    // Probe reports 120 MB free, which is less than 50 MB + 100 MB safety margin (150 MB needed)
    final probe = FakeFreeSpaceProbe(120 * 1024 * 1024);
    final service = makeService(
      picker: picker,
      inspector: inspector,
      freeSpace: probe,
      safetyMarginBytes: 100 * 1024 * 1024,
    );

    final outcome = await service.importAudio(conferenceId: conf.id);
    expect(outcome, isA<AudioImportFailure>());

    final failure = outcome as AudioImportFailure;
    expect(failure.reason, AudioImportFailureReason.lowStorage);
    expect(
      failure.userMessage,
      'Storage space is low. Free some space before importing.',
    );

    final acts = await t.activities.listForConference(conf.id);
    expect(acts, isEmpty);
    expect(mediaRoot.listSync(recursive: true), isEmpty);
    expect(audioFile.existsSync(), isTrue);
  });

  test(
    'P2-13 FR-TRN-03 cancelled picker does not create activity or files',
    () async {
      final conf = await t.conference(name: 'Samlytics Conference 2026');
      final picker = _FakePicker(null); // Cancelled
      final service = makeService(picker: picker);

      final outcome = await service.importAudio(conferenceId: conf.id);
      expect(outcome, isA<AudioImportCancelled>());

      final acts = await t.activities.listForConference(conf.id);
      expect(acts, isEmpty);
      expect(mediaRoot.listSync(recursive: true), isEmpty);
    },
  );

  test('P2-13 FR-TRN-03 blocked during recording with reason', () async {
    final conf = await t.conference(name: 'Samlytics Conference 2026');
    final audioFile = File(p.join(sourceDir.path, 'note.aac'))
      ..writeAsBytesSync([1, 2, 3]);

    final picker = _FakePicker(XFile(audioFile.path));
    final service = makeService(
      picker: picker,
      isRecordingActive: () => true, // Recording actively in progress
    );

    final outcome = await service.importAudio(conferenceId: conf.id);
    expect(outcome, isA<AudioImportFailure>());

    final failure = outcome as AudioImportFailure;
    expect(failure.reason, AudioImportFailureReason.recordingActive);
    expect(
      failure.userMessage,
      'Cannot import audio while a recording is in progress. Stop recording first to avoid interruptions.',
    );

    final acts = await t.activities.listForConference(conf.id);
    expect(acts, isEmpty);
    expect(mediaRoot.listSync(recursive: true), isEmpty);
    expect(audioFile.existsSync(), isTrue);
  });

  test('P2-13 FR-TRN-03 failure mid-copy leaves no file or activity', () async {
    final conf = await t.conference(name: 'Samlytics Conference 2026');
    final audioFile = File(p.join(sourceDir.path, 'source.mp3'))
      ..writeAsBytesSync([1, 2, 3, 4]);

    // Block destination folder creation by creating the target 'audio' as a file
    final blockedTargetAudio = File(
      p.join(
        mediaRoot.path,
        'conferences',
        conf.id,
        'activities',
        'aaaaaaaa-0000-4000-8000-000000000002',
        'audio',
      ),
    );
    blockedTargetAudio.parent.createSync(recursive: true);
    blockedTargetAudio.writeAsStringSync('blocker');

    final picker = _FakePicker(XFile(audioFile.path));
    final inspector = _FakeInspector();

    final service = makeService(picker: picker, inspector: inspector);
    final outcome = await service.importAudio(conferenceId: conf.id);

    expect(outcome, isA<AudioImportFailure>());
    final failure = outcome as AudioImportFailure;
    expect(failure.reason, AudioImportFailureReason.ioError);

    // Verify no activity created in DB
    final acts = await t.activities.listForConference(conf.id);
    expect(acts, isEmpty);
    expect(audioFile.existsSync(), isTrue);
  });

  test('P2-13 FR-TRN-03 imported activity offered for transcription', () async {
    final conf = await t.conference(name: 'Samlytics Conference 2026');
    final audioFile = File(p.join(sourceDir.path, 'voice_memo.m4a'))
      ..writeAsBytesSync([0x00, 0x01, 0x02, 0x03]);

    final picker = _FakePicker(XFile(audioFile.path));
    final inspector = _FakeInspector(
      info: const InspectedAudioInfo(
        duration: Duration(seconds: 45),
        channelCount: 1,
        sampleRateHz: 48000,
        codec: 'aac_lc',
        container: 'm4a',
      ),
    );

    final service = makeService(picker: picker, inspector: inspector);
    final outcome = await service.importAudio(conferenceId: conf.id);
    expect(outcome, isA<AudioImportSuccess>());
    final success = outcome as AudioImportSuccess;
    expect(success.activity.tags, contains('imported'));

    // Read transcription sources via transcriptionSourcesProvider
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(t.db),
        mediaAssetRepositoryProvider.overrideWithValue(t.media),
        cutRangeRepositoryProvider.overrideWithValue(t.cuts),
        mediaRootProvider.overrideWithValue(() async => mediaRoot),
      ],
    );
    addTearDown(container.dispose);

    final sources = await container.read(
      transcriptionSourcesProvider(success.activity.id).future,
    );

    expect(sources, hasLength(1));
    expect(sources.first.activityId, success.activity.id);
    expect(sources.first.segmentId, success.segment.id);
    final expectedPath = await File(
      MediaPaths.resolve(mediaRoot, success.segment.filePath).path,
    ).resolveSymbolicLinks();
    expect(sources.first.audioPath, expectedPath);
    expect(File(sources.first.audioPath).existsSync(), isTrue);
  });

  test('P2-13 FR-TRN-03 export and re-import preserves imported audio activity and segment', () async {
    final conf = await t.conference(name: 'Samlytics Conference 2026');
    final audioFile = File(p.join(sourceDir.path, 'imported_lecture.mp3'))
      ..writeAsBytesSync(List.generate(2048, (i) => (i * 3) % 256));

    final picker = _FakePicker(XFile(audioFile.path));
    final inspector = _FakeInspector(
      info: const InspectedAudioInfo(
        duration: Duration(minutes: 3),
        channelCount: 2,
        sampleRateHz: 44100,
        codec: 'mp3',
        container: 'mp3',
        bitrateBps: 128000,
      ),
    );

    final service = makeService(picker: picker, inspector: inspector);
    final outcome = await service.importAudio(conferenceId: conf.id);
    expect(outcome, isA<AudioImportSuccess>());
    final success = outcome as AudioImportSuccess;
    expect(success.activity.tags, contains('imported'));

    // Export conference
    final dest = Directory(p.join(tempDir.path, 'dest'))..createSync();
    final exporter = ExportService(
      conferences: t.conferences,
      activities: t.activities,
      media: t.media,
      cuts: t.cuts,
      jobs: t.exports,
      mediaRoot: () async => mediaRoot,
      tempRoot: () async => Directory(p.join(tempDir.path, 'cache')),
      freeSpace: FakeFreeSpaceProbe(64 << 30),
      reserveBytes: 0,
      writer: _inlineWriter,
      clock: t.clock.call,
    );

    final exportOutcome = await exporter.run(
      ExportRequest(
        conferenceId: conf.id,
        format: ExportFormat.folder,
        audioMode: ExportAudioMode.original,
      ),
      destinationParent: dest.path,
    );

    // Verify activity.json in export contains tags: ['imported'] and input_route: 'imported'
    final activityJsonFiles =
        Directory(p.join(exportOutcome.outputPath, 'activities'))
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => p.basename(f.path) == 'activity.json')
            .toList();
    expect(activityJsonFiles, hasLength(1));
    final activityJsonFile = activityJsonFiles.single;
    expect(activityJsonFile.existsSync(), isTrue);
    final content = activityJsonFile.readAsStringSync();
    expect(content, contains('"imported"'));

    // Re-import into a fresh database u and fresh media directory
    final u = TestData();
    addTearDown(u.close);
    final newMediaRoot = Directory(p.join(tempDir.path, 'new_media'))
      ..createSync();

    final importer = ExportImportService(
      db: u.db,
      activities: u.activities,
      mediaRoot: () async => newMediaRoot,
      freeSpace: FakeFreeSpaceProbe(64 << 30),
      reserveBytes: 0,
      clock: () => DateTime.utc(2026, 12, 1, 10),
      newId: SequentialIds().call,
    );

    final prepared = await importer.prepare(exportOutcome.outputPath);
    expect(prepared.preview.canImport, isTrue);

    final summary = await importer.commit(prepared);
    expect(summary.activities, 1);
    expect(summary.segments, 1);

    final importedActs = await u.activities.listForConference(
      summary.conferenceId,
    );
    expect(importedActs, hasLength(1));
    final reimportedAct = importedActs.first;
    expect(reimportedAct.title, 'imported_lecture');
    expect(reimportedAct.tags, contains('imported'));
    expect(isActivityImported(reimportedAct), isTrue);

    final reimportedSegments = await u.media.segmentsFor(reimportedAct.id);
    expect(reimportedSegments, hasLength(1));
    expect(reimportedSegments.first.inputRoute, importedInputRoute);
    expect(reimportedSegments.first.container, 'mp3');
    expect(reimportedSegments.first.state, SegmentState.finalised);

    final reimportedFile = MediaPaths.resolve(
      newMediaRoot,
      reimportedSegments.first.filePath,
    );
    expect(reimportedFile.existsSync(), isTrue);
    expect(reimportedFile.lengthSync(), 2048);
  });
}

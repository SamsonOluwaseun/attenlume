import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:attenlume/data/filesystem/export_writer.dart';
import 'package:attenlume/data/filesystem/media_paths.dart';
import 'package:attenlume/data/local_database/database_provider.dart';
import 'package:attenlume/data/repositories/media_asset_repository.dart';
import 'package:attenlume/data/repositories/repository_providers.dart';
import 'package:attenlume/domain/models/enums.dart';
import 'package:attenlume/domain/models/media.dart';
import 'package:attenlume/domain/services/audio_import_service.dart';
import 'package:attenlume/domain/services/capture_settings.dart';
import 'package:attenlume/domain/services/crash_recovery_service.dart';
import 'package:attenlume/domain/services/export_import_service.dart';
import 'package:attenlume/domain/services/export_service.dart';
import 'package:attenlume/domain/services/permanent_trim_service.dart';
import 'package:attenlume/domain/services/recording_service.dart';
import 'package:attenlume/domain/services/recording_state.dart';
import 'package:attenlume/features/capture/recording_providers.dart';
import 'package:attenlume/features/transcription/transcription_providers.dart';
import 'package:attenlume/platform/audio_import/audio_file_inspector.dart';
import 'package:attenlume/platform/audio_import/audio_file_picker.dart';
import 'package:attenlume/platform/audio_trimmer/mp4_sample_trimmer.dart';
import 'package:audio_decoder/audio_decoder.dart';
import 'package:crypto/crypto.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../fixtures/fake_capture_engine.dart';
import '../fixtures/fake_free_space_probe.dart';
import '../fixtures/fixtures.dart';
import '../fixtures/m4a_builder.dart';

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

class _HookInspector implements AudioFileInspector {
  const _HookInspector({required this.delegate, required this.afterInspect});

  final AudioFileInspector delegate;
  final void Function() afterInspect;

  @override
  Future<InspectedAudioInfo> inspect(File file) async {
    final res = await delegate.inspect(file);
    afterInspect();
    return res;
  }
}

class _FailingSegmentMediaRepository extends MediaAssetRepository {
  _FailingSegmentMediaRepository(super.db, {super.clock, super.newId});

  @override
  Future<RecordingSegment> addImportedSegment({
    String? id,
    required String activityId,
    required String filePath,
    required RecordingProfile requestedProfile,
    required String codec,
    required String container,
    required int channelCount,
    required int sampleRateHz,
    required int requestedBitrateBps,
    int? observedBitrateBps,
    String? inputRoute,
    required DateTime startUtc,
    required DateTime endUtc,
    required int durationMs,
    required int bytes,
    required String sha256,
  }) async {
    throw const FileSystemException('Database segment constraint failed');
  }
}

class _SlowSink implements IOSink {
  _SlowSink(
    this.realSink, {
    this.flushDelay = const Duration(milliseconds: 10),
  });

  final IOSink realSink;
  final Duration flushDelay;

  int bufferedChunks = 0;
  int maxBufferedChunks = 0;

  @override
  void add(List<int> data) {
    bufferedChunks++;
    if (bufferedChunks > maxBufferedChunks) {
      maxBufferedChunks = bufferedChunks;
    }
    realSink.add(data);
  }

  @override
  Future<void> flush() async {
    if (flushDelay > Duration.zero) {
      await Future<void>.delayed(flushDelay);
    }
    await realSink.flush();
    bufferedChunks = 0;
  }

  @override
  Future<void> close() => realSink.close();

  @override
  Future<void> get done => realSink.done;

  @override
  void addError(Object error, [StackTrace? stackTrace]) =>
      realSink.addError(error, stackTrace);

  @override
  Future<dynamic> addStream(Stream<List<int>> stream) =>
      realSink.addStream(stream);

  @override
  Encoding get encoding => realSink.encoding;

  @override
  set encoding(Encoding encoding) => realSink.encoding = encoding;

  @override
  void write(Object? object) => realSink.write(object);

  @override
  void writeAll(Iterable<dynamic> objects, [String separator = '']) =>
      realSink.writeAll(objects, separator);

  @override
  void writeCharCode(int charCode) => realSink.writeCharCode(charCode);

  @override
  void writeln([Object? object = '']) => realSink.writeln(object);
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
    Future<T> Function<T>(Future<T> Function() action)? withRecordingGuard,
    int? safetyMarginBytes,
    Stream<List<int>> Function(File file)? openRead,
    IOSink Function(File file)? openWrite,
  }) {
    return AudioImportService(
      db: t.db,
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
      withRecordingGuard: withRecordingGuard,
      safetyMarginBytes:
          safetyMarginBytes ?? defaultAudioImportSafetyMarginBytes,
      clock: t.clock.call,
      newId: t.ids.call,
      openRead: openRead,
      openWrite: openWrite,
    );
  }

  test('P2-13 FR-TRN-03 cancel while waiting for the commit guard leaves no import', () async {
    final conf = await t.conference(name: 'Samlytics Conference 2026');
    final source = File(p.join(sourceDir.path, 'cancel-queued.mp3'))
      ..writeAsBytesSync(List.filled(128, 7));
    final queued = Completer<void>();
    final release = Completer<void>();
    var cancelled = false;
    Future<T> guard<T>(Future<T> Function() action) async {
      queued.complete();
      await release.future;
      return action();
    }
    final service = makeService(
      picker: _FakePicker(XFile(source.path)),
      inspector: _FakeInspector(),
      withRecordingGuard: guard,
    );
    final pending = service.importAudio(
      conferenceId: conf.id,
      isCancelled: () => cancelled,
    );
    await queued.future;
    cancelled = true;
    release.complete();
    expect(await pending, isA<AudioImportCancelled>());
    expect(await t.activities.listForConference(conf.id), isEmpty);
    expect(source.readAsBytesSync(), List.filled(128, 7));
    expect(mediaRoot.listSync(recursive: true).whereType<File>(), isEmpty);
  });

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
    expect(isActivityImported(success.activity, [success.segment]), isTrue);
    expect(
      isActivityImported(success.activity),
      isFalse,
    ); // Provenance required, not tag alone

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

  test('P2-13 FR-TRN-03 failure mid-copy after bytes written leaves no file, activity or segment', () async {
    final conf = await t.conference(name: 'Samlytics Conference 2026');
    final audioFile = File(p.join(sourceDir.path, 'source.mp3'))
      ..writeAsBytesSync(List.filled(16384, 0x42));

    final picker = _FakePicker(XFile(audioFile.path));
    final inspector = _FakeInspector();

    // Stream that yields some bytes first (so partial file has bytes), then throws
    final service = makeService(
      picker: picker,
      inspector: inspector,
      openRead: (file) async* {
        yield [1, 2, 3, 4, 5, 6, 7, 8];
        throw const FileSystemException('Injected mid-copy disk failure');
      },
    );

    final outcome = await service.importAudio(conferenceId: conf.id);

    expect(outcome, isA<AudioImportFailure>());
    final failure = outcome as AudioImportFailure;
    expect(failure.reason, AudioImportFailureReason.ioError);

    // Verify no activity created in DB
    final acts = await t.activities.listForConference(conf.id);
    expect(acts, isEmpty);

    // Verify no segments in DB
    final segs = await t.media.segmentPaths();
    expect(segs, isEmpty);

    // Verify no partial file or target file exists in mediaRoot
    final mediaFiles = mediaRoot.listSync(recursive: true).whereType<File>();
    expect(mediaFiles, isEmpty);

    // Source file untouched
    expect(audioFile.existsSync(), isTrue);
    expect(audioFile.lengthSync(), 16384);
  });

  test('P2-13 FR-TRN-03 database transaction rolls back activity and removes files on segment failure', () async {
    final conf = await t.conference(name: 'Samlytics Conference 2026');
    final audioFile = File(p.join(sourceDir.path, 'source.mp3'))
      ..writeAsBytesSync([1, 2, 3, 4, 5, 6, 7, 8]);

    final picker = _FakePicker(XFile(audioFile.path));
    final inspector = _FakeInspector();

    final failingMedia = _FailingSegmentMediaRepository(
      t.db,
      clock: t.clock.call,
      newId: t.ids.call,
    );

    final service = AudioImportService(
      db: t.db,
      activities: t.activities,
      conferences: t.conferences,
      media: failingMedia,
      mediaRoot: () async => mediaRoot,
      picker: picker,
      inspector: inspector,
      freeSpace: FakeFreeSpaceProbe(10 * 1024 * 1024 * 1024),
      clock: t.clock.call,
      newId: t.ids.call,
    );

    final outcome = await service.importAudio(conferenceId: conf.id);
    expect(outcome, isA<AudioImportFailure>());
    final failure = outcome as AudioImportFailure;
    expect(failure.reason, AudioImportFailureReason.ioError);

    // Assert transaction rolled back activity creation: no activity remains in DB
    final acts = await t.activities.listForConference(conf.id);
    expect(acts, isEmpty);

    // Assert no segments in DB
    final segs = await t.media.segmentPaths();
    expect(segs, isEmpty);

    // Assert no file remains in mediaRoot
    final mediaFiles = mediaRoot.listSync(recursive: true).whereType<File>();
    expect(mediaFiles, isEmpty);

    // Source file untouched
    expect(audioFile.existsSync(), isTrue);
  });

  test('P2-13 FR-TRN-03 stream copy reports bounded progress and supports clean cancellation', () async {
    final conf = await t.conference(name: 'Samlytics Conference 2026');
    final audioFile = File(p.join(sourceDir.path, 'large_file.mp3'))
      ..writeAsBytesSync(List.filled(65536, 0x55));

    final picker = _FakePicker(XFile(audioFile.path));
    final inspector = _FakeInspector();

    final progressReports = <AudioImportProgress>[];
    final service = makeService(picker: picker, inspector: inspector);

    // 1. Progress test
    final outcome = await service.importAudio(
      conferenceId: conf.id,
      onProgress: progressReports.add,
    );
    expect(outcome, isA<AudioImportSuccess>());
    expect(progressReports, isNotEmpty);
    expect(progressReports.last.bytesDone, 65536);
    expect(progressReports.last.fraction, 1.0);

    // 2. Cancellation test mid-stream
    var cancelTriggered = false;
    final cancelService = makeService(
      picker: picker,
      inspector: inspector,
      openRead: (file) async* {
        yield List.filled(1024, 0x11);
        cancelTriggered = true;
        yield List.filled(1024, 0x22);
      },
    );

    final cancelOutcome = await cancelService.importAudio(
      conferenceId: conf.id,
      isCancelled: () => cancelTriggered,
    );
    expect(cancelOutcome, isA<AudioImportCancelled>());

    // Cleaned up on cancel: no partial files remain for the second import
    final acts = await t.activities.listForConference(conf.id);
    expect(acts, hasLength(1)); // only the first successful import
    final allFiles = mediaRoot.listSync(recursive: true).whereType<File>();
    expect(allFiles.every((f) => !MediaPaths.isPartial(f.path)), isTrue);
  });

  test('P2-13 FR-TRN-03 recording starting during copy or before commit stops import cleanly', () async {
    final conf = await t.conference(name: 'Samlytics Conference 2026');
    final audioFile = File(p.join(sourceDir.path, 'lecture.mp3'))
      ..writeAsBytesSync(List.filled(16384, 0x33));

    final picker = _FakePicker(XFile(audioFile.path));
    final inspector = _FakeInspector();

    // Case A: recording starts during stream copy
    var recordingActive = false;
    final serviceCopyInterrupted = makeService(
      picker: picker,
      inspector: inspector,
      isRecordingActive: () => recordingActive,
      openRead: (file) async* {
        yield List.filled(1024, 0x01);
        recordingActive = true;
        yield List.filled(1024, 0x02);
      },
    );

    final outcomeA = await serviceCopyInterrupted.importAudio(
      conferenceId: conf.id,
    );
    expect(outcomeA, isA<AudioImportFailure>());
    expect(
      (outcomeA as AudioImportFailure).reason,
      AudioImportFailureReason.recordingActive,
    );

    // Assert no files and no activities
    var acts = await t.activities.listForConference(conf.id);
    expect(acts, isEmpty);
    var files = mediaRoot.listSync(recursive: true).whereType<File>();
    expect(files, isEmpty);

    // Case B: recording active immediately after copy, before DB transaction
    var copyFinished = false;
    final serviceCommitInterrupted = makeService(
      picker: picker,
      inspector: inspector,
      isRecordingActive: () => copyFinished,
      openRead: (file) async* {
        yield List.filled(1024, 0x01);
        copyFinished = true;
      },
    );

    final outcomeB = await serviceCommitInterrupted.importAudio(
      conferenceId: conf.id,
    );
    expect(outcomeB, isA<AudioImportFailure>());
    expect(
      (outcomeB as AudioImportFailure).reason,
      AudioImportFailureReason.recordingActive,
    );

    acts = await t.activities.listForConference(conf.id);
    expect(acts, isEmpty);
    files = mediaRoot.listSync(recursive: true).whereType<File>();
    expect(files, isEmpty);
  });

  test('P2-13 FR-TRN-03 temporary copy uses import staging suffix and startup cleanup removes abandoned imports', () async {
    // 1. AudioImportService.importStagingSuffix convention check
    const targetRel = 'conferences/c1/activities/a1/audio/segment-001.mp3';
    const stagingRel = '$targetRel${AudioImportService.importStagingSuffix}';
    expect(AudioImportService.isImportStagingPath(stagingRel), isTrue);
    expect(
      stagingRel,
      'conferences/c1/activities/a1/audio/segment-001.mp3.importing',
    );

    // 2. Cleanup of abandoned imports left on disk after simulated crash/kill
    final abandonedFile = File(
      p.join(
        mediaRoot.path,
        'conferences',
        'conf-abandoned',
        'activities',
        'act-abandoned',
        'audio',
        'segment-001.mp3.importing',
      ),
    );
    abandonedFile.parent.createSync(recursive: true);
    abandonedFile.writeAsStringSync('abandoned partial copy bytes');
    expect(abandonedFile.existsSync(), isTrue);

    final cleanedCount = await AudioImportService.cleanupAbandonedImports(
      root: mediaRoot,
      media: t.media,
    );
    expect(cleanedCount, 1);
    expect(abandonedFile.existsSync(), isFalse);
    expect(abandonedFile.parent.existsSync(), isFalse);
  });

  test('P2-13 FR-TRN-03 M4A file with metadata but missing/empty mdat payload is rejected', () async {
    final conf = await t.conference(name: 'Samlytics Conference 2026');
    // Build M4A with valid metadata and duration, but 0 mediaDataBytes (empty mdat box)
    final emptyMdatBytes = buildM4a(mediaDataBytes: 0);
    final emptyMdatFile = File(p.join(sourceDir.path, 'no_audio.m4a'))
      ..writeAsBytesSync(emptyMdatBytes);

    // Default inspector rejects it
    const inspector = DefaultAudioFileInspector();
    expect(
      () => inspector.inspect(emptyMdatFile),
      throwsA(
        isA<AudioInspectionException>().having(
          (e) => e.message,
          'message',
          contains('mdat box is missing or empty'),
        ),
      ),
    );

    final picker = _FakePicker(XFile(emptyMdatFile.path));
    final service = makeService(picker: picker, inspector: inspector);
    final outcome = await service.importAudio(conferenceId: conf.id);

    expect(outcome, isA<AudioImportFailure>());
    expect(
      (outcome as AudioImportFailure).reason,
      AudioImportFailureReason.unreadableFile,
    );

    final acts = await t.activities.listForConference(conf.id);
    expect(acts, isEmpty);
  });

  test('P2-13 FR-TRN-03 trimmed export and permanent trim blocked for imported non-M4A audio', () async {
    final conf = await t.conference(name: 'Samlytics Conference 2026');
    final audioFile = File(p.join(sourceDir.path, 'imported.mp3'))
      ..writeAsBytesSync(List.filled(2048, 0x12));

    final picker = _FakePicker(XFile(audioFile.path));
    final inspector = _FakeInspector(
      info: const InspectedAudioInfo(
        duration: Duration(seconds: 120),
        channelCount: 2,
        sampleRateHz: 44100,
        codec: 'mp3',
        container: 'mp3',
      ),
    );

    final service = makeService(picker: picker, inspector: inspector);
    final outcome = await service.importAudio(conferenceId: conf.id);
    expect(outcome, isA<AudioImportSuccess>());
    final success = outcome as AudioImportSuccess;

    // Add an active cut on the imported MP3 activity
    await t.cuts.add(
      success.activity.id,
      startOffsetMs: 10000,
      endOffsetMs: 30000,
      reason: 'Trim middle',
    );

    // Verify ExportService blocks trimmed export
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

    final dest = Directory(p.join(tempDir.path, 'dest_trim'))..createSync();
    expect(
      () => exporter.run(
        ExportRequest(
          conferenceId: conf.id,
          format: ExportFormat.folder,
          audioMode: ExportAudioMode.trimmed,
        ),
        destinationParent: dest.path,
      ),
      throwsA(
        isA<ExportException>().having(
          (e) => e.message,
          'message',
          contains(
            'Trimmed export is not supported for imported non-M4A audio',
          ),
        ),
      ),
    );

    // Verify PermanentTrimService blocks permanent trimming
    final trimmer = PermanentTrimService(
      activities: t.activities,
      media: t.media,
      cuts: t.cuts,
      trimmer: const Mp4SampleTrimmer(),
      mediaRoot: () async => mediaRoot,
      freeSpace: FakeFreeSpaceProbe(64 << 30),
      newId: t.ids.call,
    );

    expect(
      () => trimmer.plan(success.activity.id),
      throwsA(
        isA<PermanentTrimException>().having(
          (e) => e.message,
          'message',
          contains(
            'Permanent trimming is not supported for imported non-M4A audio',
          ),
        ),
      ),
    );
  });

  test('P2-13 FR-TRN-03 provenance decides imported status, not user tag alone', () async {
    final conf = await t.conference(name: 'Samlytics Conference 2026');
    final recordedAct = await t.activities.create(
      conferenceId: conf.id,
      title: 'Microphone Recording',
      typeId: (await t.activities.types()).first.id,
      tags: const ['imported'], // User added tag 'imported'
    );

    final normalSegment = await t.media.startSegment(
      activityId: recordedAct.id,
      filePath:
          'conferences/${conf.id}/activities/${recordedAct.id}/audio/segment-001.m4a',
      startUtc: DateTime.utc(2026, 11, 7, 9),
      requestedProfile: conf.defaultRecordingProfile,
      codec: 'aac_lc',
      container: 'm4a',
      channelCount: 1,
      sampleRateHz: 48000,
      requestedBitrateBps: 96000,
      inputRoute: 'builtin_mic',
    );

    // When segments are known: provenance is microphone, so NOT imported
    expect(isActivityImported(recordedAct, [normalSegment]), isFalse);

    // When segments is null: user-editable tag alone NEVER decides imported status
    expect(isActivityImported(recordedAct), isFalse);

    // When segment has inputRoute == 'imported': isActivityImported is true
    final importedAct = await t.activities.create(
      conferenceId: conf.id,
      title: 'Real Import',
      typeId: (await t.activities.types()).first.id,
      tags: const [], // No tags at all
    );

    final importedSegment = await t.media.addImportedSegment(
      activityId: importedAct.id,
      filePath:
          'conferences/${conf.id}/activities/${importedAct.id}/audio/segment-001.m4a',
      requestedProfile: conf.defaultRecordingProfile,
      codec: 'aac_lc',
      container: 'm4a',
      channelCount: 1,
      sampleRateHz: 48000,
      requestedBitrateBps: 96000,
      inputRoute: importedInputRoute,
      startUtc: DateTime.utc(2026, 11, 7, 10),
      endUtc: DateTime.utc(2026, 11, 7, 10, 1),
      durationMs: 60000,
      bytes: 1024,
      sha256: 'beefcafe',
    );

    expect(isActivityImported(importedAct, [importedSegment]), isTrue);
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
    final reimportedSegments = await u.media.segmentsFor(reimportedAct.id);
    expect(reimportedSegments, hasLength(1));
    expect(reimportedSegments.first.inputRoute, importedInputRoute);
    expect(reimportedSegments.first.container, 'mp3');
    expect(reimportedSegments.first.state, SegmentState.finalised);
    expect(isActivityImported(reimportedAct, reimportedSegments), isTrue);
    expect(isActivityImported(reimportedAct), isFalse);

    final reimportedFile = MediaPaths.resolve(
      newMediaRoot,
      reimportedSegments.first.filePath,
    );
    expect(reimportedFile.existsSync(), isTrue);
    expect(reimportedFile.lengthSync(), 2048);
  });

  test('P2-13 FR-TRN-03 stream copy provides write backpressure with bounded chunk buffer on slow sink', () async {
    final conf = await t.conference(name: 'Samlytics Conference 2026');
    final sourceFile = File(p.join(sourceDir.path, 'large_file.mp3'))
      ..writeAsBytesSync(List.filled(2048, 0x55));

    final picker = _FakePicker(XFile(sourceFile.path));
    final inspector = _FakeInspector(
      info: const InspectedAudioInfo(
        duration: Duration(minutes: 5),
        channelCount: 2,
        sampleRateHz: 44100,
        codec: 'mp3',
        container: 'mp3',
      ),
    );

    // Rapidly emit 20 chunks from the read stream
    final chunks = List.generate(20, (i) => List.filled(100, i));
    Stream<List<int>> fastRead(File f) => Stream.fromIterable(chunks);

    _SlowSink? slowSink;
    final service = makeService(
      picker: picker,
      inspector: inspector,
      openRead: fastRead,
      openWrite: (file) {
        slowSink = _SlowSink(
          file.openWrite(),
          flushDelay: const Duration(milliseconds: 5),
        );
        return slowSink!;
      },
    );

    final outcome = await service.importAudio(conferenceId: conf.id);
    expect(outcome, isA<AudioImportSuccess>());

    // Backpressure ensures that each chunk write/flush is awaited so at most a few chunks
    // can ever be buffered simultaneously in memory
    expect(slowSink, isNotNull);
    expect(slowSink!.maxBufferedChunks, lessThanOrEqualTo(2));
  });

  test('P2-13 FR-TRN-03 recording startup during import commit waits for commit and succeeds', () async {
    final conf = await t.conference(name: 'Samlytics Conference 2026');
    final liveActivity = await t.activity(conf.id, title: 'Live Meeting');

    final sourceFile = File(p.join(sourceDir.path, 'commit_race.mp3'))
      ..writeAsBytesSync(List.filled(1024, 0x11));
    final picker = _FakePicker(XFile(sourceFile.path));
    final inspector = _FakeInspector();

    final engine = FakeCaptureEngine();
    final recorder = RecordingService(
      engine: engine,
      activities: t.activities,
      media: t.media,
      mediaRoot: () async => mediaRoot,
      platform: CapturePlatform.android,
      clock: t.clock.call,
    );
    addTearDown(recorder.dispose);

    final commitStarted = Completer<void>();
    final allowCommitFinish = Completer<void>();
    Future<StartOutcome>? recordingStartFuture;

    Future<T> commitGuardHook<T>(Future<T> Function() action) {
      return recorder.runWithCommitLock(() async {
        commitStarted.complete();
        // Wait until recording start has been invoked
        await allowCommitFinish.future;
        return await action();
      });
    }

    final service = makeService(
      picker: picker,
      inspector: inspector,
      isRecordingActive: () => recorder.status.state.holdsActivity,
      withRecordingGuard: commitGuardHook,
    );

    // 1. Start import
    final importFuture = service.importAudio(conferenceId: conf.id);

    // 2. Wait until commit is executing under the lock
    await commitStarted.future;

    // 3. Request recording start while import is committing
    recordingStartFuture = recorder.start(liveActivity.id);

    // 4. Release commit so import completes
    allowCommitFinish.complete();

    final importOutcome = await importFuture;
    expect(importOutcome, isA<AudioImportSuccess>());

    // 5. Recording start was queued on the lock, awaited commit completion and started cleanly
    final recOutcome = await recordingStartFuture;
    expect(recOutcome, StartOutcome.started);
    expect(recorder.status.state, RecordingState.recording);
    expect(recorder.status.activityId, liveActivity.id);
  });

  test('P2-13 FR-TRN-03 second import during first copy is rejected and does not delete active staging file', () async {
    final conf = await t.conference(name: 'Samlytics Conference 2026');
    final source1 = File(p.join(sourceDir.path, 'first.mp3'))
      ..writeAsBytesSync(List.filled(2048, 0x01));
    final source2 = File(p.join(sourceDir.path, 'second.mp3'))
      ..writeAsBytesSync(List.filled(2048, 0x02));

    final pauseCopy = Completer<void>();
    final firstChunkWritten = Completer<void>();

    Stream<List<int>> controllableRead(File f) async* {
      yield List.filled(1024, 0x01);
      firstChunkWritten.complete();
      await pauseCopy.future;
      yield List.filled(1024, 0x01);
    }

    final service = makeService(
      inspector: _FakeInspector(),
      openRead: controllableRead,
    );

    // Start first import
    final import1Future = service.importAudio(
      conferenceId: conf.id,
      sourceFileOverride: XFile(source1.path),
    );

    await firstChunkWritten.future;

    // Verify first import staging file is present on disk
    final stagingFilesBefore = mediaRoot
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => AudioImportService.isImportStagingPath(f.path))
        .toList();
    expect(stagingFilesBefore, hasLength(1));
    final firstStagingFile = stagingFilesBefore.first;
    expect(firstStagingFile.existsSync(), isTrue);

    // Attempt second import while first is actively copying
    final import2Outcome = await service.importAudio(
      conferenceId: conf.id,
      sourceFileOverride: XFile(source2.path),
    );

    expect(import2Outcome, isA<AudioImportFailure>());
    final failure = import2Outcome as AudioImportFailure;
    expect(failure.reason, AudioImportFailureReason.importAlreadyRunning);
    expect(
      failure.userMessage,
      'An audio import is already in progress. Please wait for it to finish.',
    );

    // Verify first import staging file was NOT deleted by second import
    expect(firstStagingFile.existsSync(), isTrue);

    // Let first import finish
    pauseCopy.complete();
    final import1Outcome = await import1Future;
    expect(import1Outcome, isA<AudioImportSuccess>());
  });

  test(
    'P2-13 FR-TRN-03 abandoned import staging files are cleaned up on startup',
    () async {
      final conf = await t.conference(name: 'Samlytics Conference 2026');

      // Simulate orphaned import staging files (.importing) left behind
      // because an interruption occurred before commit
      final orphanDir = Directory(
        p.join(
          mediaRoot.path,
          'conferences',
          conf.id,
          'activities',
          'orphaned_act',
          'audio',
        ),
      )..createSync(recursive: true);
      final orphanMp3 = File(
        p.join(orphanDir.path, 'segment-001.mp3.importing'),
      )..writeAsBytesSync(List.filled(4096, 0xAA));
      final orphanWav = File(
        p.join(orphanDir.path, 'segment-001.wav.importing'),
      )..writeAsBytesSync(List.filled(4096, 0xBB));

      expect(orphanMp3.existsSync(), isTrue);
      expect(orphanWav.existsSync(), isTrue);

      // Verify neither file is linked to any database segment
      final knownPaths = await t.media.segmentPaths();
      expect(knownPaths, isEmpty);

      // Run startup / pre-import cleanup
      final cleaned = await AudioImportService.cleanupAbandonedImports(
        root: mediaRoot,
        media: t.media,
      );

      expect(cleaned, greaterThanOrEqualTo(2));
      expect(orphanMp3.existsSync(), isFalse);
      expect(orphanWav.existsSync(), isFalse);
      expect(orphanDir.existsSync(), isFalse);
    },
  );

  test('P2-13 FR-TRN-03 M4A file with positive mdat size and valid metadata but unreadable audio payload is rejected by sample decoder', () async {
    final conf = await t.conference(name: 'Samlytics Conference 2026');

    // Create an M4A file with valid container box headers and non-zero mdat payload
    final m4aBytes = buildM4a(mediaDataBytes: 4096);
    final unreadableM4aFile = File(
      p.join(sourceDir.path, 'unreadable_payload.m4a'),
    )..writeAsBytesSync(m4aBytes);

    // DefaultAudioFileInspector configured with platform decoder where metadata succeeds,
    // but sample decoding fails (proving production validation of actual samples)
    final inspector = DefaultAudioFileInspector(
      audioInfoProvider: (path) async => const AudioInfo(
        duration: Duration(seconds: 10),
        sampleRate: 44100,
        channels: 2,
        bitRate: 128000,
        format: 'aac',
      ),
      sampleDecoder: (inputPath, outputPath, start, end) async {
        throw AudioConversionException(
          'AAC decoder: bitstream corrupt or unreadable samples',
        );
      },
    );

    // Verify inspector throws AudioInspectionException
    expect(
      () => inspector.inspect(unreadableM4aFile),
      throwsA(isA<AudioInspectionException>()),
    );

    final picker = _FakePicker(XFile(unreadableM4aFile.path));
    final service = makeService(picker: picker, inspector: inspector);
    final outcome = await service.importAudio(conferenceId: conf.id);

    expect(outcome, isA<AudioImportFailure>());
    expect(
      (outcome as AudioImportFailure).reason,
      AudioImportFailureReason.unreadableFile,
    );

    final acts = await t.activities.listForConference(conf.id);
    expect(acts, isEmpty);
  });

  test('P2-13 FR-TRN-03 source file deleted after inspection gives a failure message and leaves storage untouched', () async {
    final conf = await t.conference(name: 'Samlytics Conference 2026');

    final sourceFile = File(p.join(sourceDir.path, 'vanish_after_inspect.mp3'))
      ..writeAsBytesSync(List.filled(4096, 0x11));

    final baseInspector = _FakeInspector(
      info: const InspectedAudioInfo(
        duration: Duration(minutes: 1),
        channelCount: 2,
        sampleRateHz: 44100,
        codec: 'mp3',
        container: 'mp3',
      ),
    );

    // Hook inspector that deletes the source file immediately after inspection completes
    final inspector = _HookInspector(
      delegate: baseInspector,
      afterInspect: () {
        if (sourceFile.existsSync()) {
          sourceFile.deleteSync();
        }
      },
    );

    final picker = _FakePicker(XFile(sourceFile.path));
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
    final files = mediaRoot
        .listSync(recursive: true)
        .whereType<File>()
        .toList();
    expect(files, isEmpty);
  });

  test('P2-13 FR-TRN-03 recording-style orphans (partial and renamed final) survive cleanup and are recovered by CrashRecoveryService while abandoned import staging is removed', () async {
    final conf = await t.conference(name: 'Crash Recovery Test Conf');

    // 1. Setup a recording in progress (partial file and DB row pointing to .partial.m4a)
    final act1 = await t.activity(conf.id, title: 'Active Recording Session 1');
    final seg1RelPath = MediaPaths.segment(conf.id, act1.id, 1);
    final seg1PartialRelPath = MediaPaths.partial(seg1RelPath);
    await t.media.startSegment(
      activityId: act1.id,
      filePath: seg1PartialRelPath,
      requestedProfile: RecordingProfile.balanced,
      codec: 'aac_lc',
      container: 'm4a',
      channelCount: 1,
      sampleRateHz: 48000,
      requestedBitrateBps: 48000,
      startUtc: t.clock.now,
    );
    final seg1File = MediaPaths.resolve(mediaRoot, seg1PartialRelPath)
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(
        buildM4a(channels: 1, sampleRateHz: 48000, durationUnits: 48000 * 3),
      );

    // 2. Setup a recording renamed final (DB row points to .partial.m4a, but file on disk was renamed to final .m4a before crash)
    final act2 = await t.activity(conf.id, title: 'Active Recording Session 2');
    final seg2RelPath = MediaPaths.segment(conf.id, act2.id, 1);
    final seg2PartialRelPath = MediaPaths.partial(seg2RelPath);
    final seg2 = await t.media.startSegment(
      activityId: act2.id,
      filePath: seg2PartialRelPath,
      requestedProfile: RecordingProfile.balanced,
      codec: 'aac_lc',
      container: 'm4a',
      channelCount: 1,
      sampleRateHz: 48000,
      requestedBitrateBps: 48000,
      startUtc: t.clock.now,
    );
    final seg2FinalFile = MediaPaths.resolve(mediaRoot, seg2RelPath)
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(
        buildM4a(channels: 1, sampleRateHz: 48000, durationUnits: 48000 * 4),
      );

    // 3. Setup an abandoned import staging file (.importing suffix)
    final importStagingRelPath = p.posix.join(
      'conferences',
      conf.id,
      'activities',
      'abandoned_import_act',
      'audio',
      'segment-001.m4a.importing',
    );
    final importStagingFile =
        MediaPaths.resolve(mediaRoot, importStagingRelPath)
          ..parent.createSync(recursive: true)
          ..writeAsBytesSync(List.filled(2048, 0xEE));

    expect(seg1File.existsSync(), isTrue);
    expect(seg2FinalFile.existsSync(), isTrue);
    expect(importStagingFile.existsSync(), isTrue);

    // Run cleanupAbandonedImports
    final cleaned = await AudioImportService.cleanupAbandonedImports(
      root: mediaRoot,
      media: t.media,
    );

    // Staging file should be cleaned up
    expect(cleaned, greaterThanOrEqualTo(1));
    expect(importStagingFile.existsSync(), isFalse);

    // Crucial: Recording-style orphans MUST survive cleanup!
    expect(
      seg1File.existsSync(),
      isTrue,
      reason: 'Partial recording file must survive import cleanup',
    );
    expect(
      seg2FinalFile.existsSync(),
      isTrue,
      reason: 'Renamed final recording file must survive import cleanup',
    );

    // Run CrashRecoveryService reconcile and verify both are found and recovered
    final crashRecovery = CrashRecoveryService(
      activities: t.activities,
      media: t.media,
      mediaRoot: () async => mediaRoot,
    );
    final report = await crashRecovery.reconcile();
    expect(report.activities, isNotEmpty);

    expect(seg1File.parent.existsSync(), isTrue);
    final finalSeg1File = MediaPaths.resolve(mediaRoot, seg1RelPath);
    expect(
      finalSeg1File.existsSync(),
      isTrue,
      reason: 'Crash recovery finalises partial recording',
    );
    expect(
      seg2FinalFile.existsSync(),
      isTrue,
      reason: 'Crash recovery reconciles renamed final recording',
    );

    final updatedSeg2 = (await t.media.segmentsFor(act2.id))
        .singleWhere((s) => s.id == seg2.id);
    expect(updatedSeg2.state, SegmentState.recovered);
    expect(updatedSeg2.filePath, seg2RelPath);
  });
  test('P2-13 FR-TRN-03 an import committed but not renamed before a kill is completed at next start', () async {
    final conf = await t.conference(name: 'Samlytics Conference 2026');
    final act = await t.activity(conf.id, title: 'Imported lecture');
    final finalRel = p.posix.join(
      'conferences',
      conf.id,
      'activities',
      act.id,
      'audio',
      'segment-001.mp3',
    );
    // The database committed the segment at its final path...
    await t.media.addImportedSegment(
      id: 'imported-seg',
      activityId: act.id,
      filePath: finalRel,
      requestedProfile: RecordingProfile.balanced,
      codec: 'mp3',
      container: 'mp3',
      channelCount: 1,
      sampleRateHz: 44100,
      requestedBitrateBps: 128000,
      inputRoute: importedInputRoute,
      startUtc: t.clock.now,
      endUtc: t.clock.now.add(const Duration(seconds: 5)),
      durationMs: 5000,
      bytes: 3,
      sha256: 'x',
    );
    // ...but the app stopped before the staging file was renamed.
    final staging = MediaPaths.resolve(mediaRoot, '$finalRel.importing')
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([1, 2, 3]);

    final cleaned = await AudioImportService.cleanupAbandonedImports(
      root: mediaRoot,
      media: t.media,
    );
    expect(cleaned, 0);
    expect(staging.existsSync(), isFalse);
    expect(MediaPaths.resolve(mediaRoot, finalRel).readAsBytesSync(), [
      1,
      2,
      3,
    ]);
  });
  test('P2-13 FR-TRN-03 a committed import whose rename fails is kept for the next start', () async {
    final conf = await t.conference(name: 'Samlytics Conference 2026');
    final act = await t.activity(conf.id, title: 'Imported lecture');
    final finalRel = p.posix.join(
      'conferences',
      conf.id,
      'activities',
      act.id,
      'audio',
      'segment-001.wav',
    );
    await t.media.addImportedSegment(
      id: 'imported-seg-2',
      activityId: act.id,
      filePath: finalRel,
      requestedProfile: RecordingProfile.balanced,
      codec: 'pcm',
      container: 'wav',
      channelCount: 1,
      sampleRateHz: 16000,
      requestedBitrateBps: 256000,
      inputRoute: importedInputRoute,
      startUtc: t.clock.now,
      endUtc: t.clock.now.add(const Duration(seconds: 5)),
      durationMs: 5000,
      bytes: 3,
      sha256: 'x',
    );
    final staging = MediaPaths.resolve(mediaRoot, '$finalRel.importing')
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([4, 5, 6]);
    // A folder in the way makes the rename fail.
    Directory(MediaPaths.resolve(mediaRoot, finalRel).path).createSync();

    await AudioImportService.cleanupAbandonedImports(
      root: mediaRoot,
      media: t.media,
    );
    expect(staging.readAsBytesSync(), [4, 5, 6]);
  });
}

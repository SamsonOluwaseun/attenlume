import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:file_selector/file_selector.dart';
import 'package:path/path.dart' as p;

import '../../data/filesystem/media_paths.dart';
import '../../data/local_database/builtin_activity_types.dart';
import '../../data/repositories/activity_repository.dart';
import '../../data/repositories/conference_repository.dart';
import '../../data/repositories/media_asset_repository.dart';
import '../../data/repositories/repository_support.dart';
import '../../platform/audio_import/audio_file_inspector.dart';
import '../../platform/audio_import/audio_file_picker.dart';
import '../../platform/storage/free_space_probe.dart';
import '../models/activity.dart';
import '../models/enums.dart';
import '../models/media.dart';

/// Supported audio extensions for imported audio files (FR-TRN-03) [P2-13].
const supportedAudioExtensions = {'.m4a', '.mp3', '.wav', '.aac'};

/// Default safety margin (100 MB) on top of imported file size (FR-STO-04, FR-TRN-03).
const defaultAudioImportSafetyMarginBytes = 100 * 1024 * 1024;

/// Tag applied to activities whose audio was imported (FR-TRN-03) [P2-13].
const importedAudioTag = 'imported';

/// Input route marker for segments copied from an external audio file (FR-TRN-03) [P2-13].
const importedInputRoute = 'imported';

/// Checks if an activity was imported rather than recorded directly in Attenlume.
bool isActivityImported(
  Activity activity, [
  Iterable<RecordingSegment>? segments,
]) {
  if (activity.tags.contains(importedAudioTag)) return true;
  if (segments != null &&
      segments.any((s) => s.inputRoute == importedInputRoute)) {
    return true;
  }
  return false;
}

/// Derives a clean activity title from the imported file name (FR-TRN-03) [P2-13].
String activityTitleFromFileName(String fileName) {
  final stem = p.basenameWithoutExtension(fileName).trim();
  return stem.isEmpty ? 'Imported audio' : stem;
}

/// Outcome of attempting to import an audio file.
sealed class AudioImportOutcome {
  const AudioImportOutcome();
}

/// Import finished successfully.
class AudioImportSuccess extends AudioImportOutcome {
  const AudioImportSuccess({required this.activity, required this.segment});

  final Activity activity;
  final RecordingSegment segment;
}

/// The user cancelled the file picker dialog.
class AudioImportCancelled extends AudioImportOutcome {
  const AudioImportCancelled();
}

/// Why audio import could not finish.
enum AudioImportFailureReason {
  recordingActive,
  unsupportedFormat,
  unreadableFile,
  lowStorage,
  ioError,
}

/// Import failed with an explained reason.
class AudioImportFailure extends AudioImportOutcome {
  const AudioImportFailure(this.reason, {this.details});

  final AudioImportFailureReason reason;
  final String? details;

  /// Plain UK English message for user display.
  String get userMessage {
    switch (reason) {
      case AudioImportFailureReason.recordingActive:
        return 'Cannot import audio while a recording is in progress. '
            'Stop recording first to avoid interruptions.';
      case AudioImportFailureReason.unsupportedFormat:
        return 'Unsupported audio format. Attenlume imports .m4a, .mp3, .wav and .aac files.';
      case AudioImportFailureReason.unreadableFile:
        return 'The audio file could not be read. Check the file is not damaged.';
      case AudioImportFailureReason.lowStorage:
        return 'Storage space is low. Free some space before importing.';
      case AudioImportFailureReason.ioError:
        return 'Could not import the audio file. Your device storage was unchanged.';
    }
  }
}

/// Service that imports an audio file recorded elsewhere into an activity (FR-TRN-03) [P2-13].
///
/// Features:
/// - Reuses injectable [AudioFilePicker] and [AudioFileInspector].
/// - Validates extensions (.m4a, .mp3, .wav, .aac) and reads duration before copying.
/// - Checks free space via [FreeSpaceProbe] with safety margin.
/// - Performs atomic stream copy to `.partial` and renames only on complete copy.
/// - If copy fails or cancels mid-way, leaves no file and no database activity.
/// - Leaves the original source file completely untouched (never moved, modified or deleted).
/// - Marks activity and segment as imported (`imported` tag and `imported` inputRoute).
/// - Refuses import while recording is active to avoid microphone/resource conflicts.
class AudioImportService {
  AudioImportService({
    required this.activities,
    required this.conferences,
    required this.media,
    required this.mediaRoot,
    this.picker = const FileSelectorAudioPicker(),
    this.inspector = const DefaultAudioFileInspector(),
    this.freeSpace = const UnknownFreeSpaceProbe(),
    this.safetyMarginBytes = defaultAudioImportSafetyMarginBytes,
    this.isRecordingActive,
    this.clock = systemUtcClock,
    this.newId = uuidV4,
  });

  final ActivityRepository activities;
  final ConferenceRepository conferences;
  final MediaAssetRepository media;
  final Future<Directory> Function() mediaRoot;
  final AudioFilePicker picker;
  final AudioFileInspector inspector;
  final FreeSpaceProbe freeSpace;
  final int safetyMarginBytes;
  final bool Function()? isRecordingActive;
  final UtcClock clock;
  final IdGenerator newId;

  /// Prompts the user to pick an audio file and imports it into [conferenceId].
  ///
  /// Optionally accepts [sourceFileOverride] (for direct testing or programmatic calls).
  Future<AudioImportOutcome> importAudio({
    required String conferenceId,
    String? typeId,
    XFile? sourceFileOverride,
  }) async {
    // 1. Refuse import while recording is active (FR-TRN-03 item 6)
    if (isRecordingActive?.call() == true) {
      return const AudioImportFailure(AudioImportFailureReason.recordingActive);
    }

    // 2. Pick audio file
    final picked = sourceFileOverride ?? await picker.pickAudio();
    if (picked == null) {
      return const AudioImportCancelled();
    }

    // 3. Check format / extension
    final ext = p
        .extension(picked.name.isNotEmpty ? picked.name : picked.path)
        .toLowerCase();
    if (!supportedAudioExtensions.contains(ext)) {
      return AudioImportFailure(
        AudioImportFailureReason.unsupportedFormat,
        details: 'Extension "$ext" is not supported',
      );
    }

    final sourceFile = File(picked.path);
    if (!sourceFile.existsSync()) {
      return const AudioImportFailure(
        AudioImportFailureReason.unreadableFile,
        details: 'Source file does not exist',
      );
    }

    // 4. Inspect audio duration and format before copying
    final InspectedAudioInfo inspected;
    try {
      inspected = await inspector.inspect(sourceFile);
      if (inspected.duration <= Duration.zero) {
        return const AudioImportFailure(
          AudioImportFailureReason.unreadableFile,
          details: 'Audio duration is zero',
        );
      }
    } catch (e) {
      return AudioImportFailure(
        AudioImportFailureReason.unreadableFile,
        details: e.toString(),
      );
    }

    // 5. Check free space with safety margin
    final fileBytes = await sourceFile.length();
    final root = await mediaRoot();
    final space = await freeSpace.query(root.path);
    if (space != null && space.availableBytes - fileBytes < safetyMarginBytes) {
      return AudioImportFailure(
        AudioImportFailureReason.lowStorage,
        details:
            'Available: ${space.availableBytes}, needed: ${fileBytes + safetyMarginBytes}',
      );
    }

    // 6. Resolve activity and segment targets
    final conf = await conferences.get(conferenceId);
    if (conf == null) {
      return const AudioImportFailure(
        AudioImportFailureReason.ioError,
        details: 'Conference not found',
      );
    }

    final effectiveTypeId = typeId ?? await _defaultTypeId();
    final activityId = newId();
    final segmentId = newId();

    final relAudioDir = p.posix.join(
      'conferences',
      conferenceId,
      'activities',
      activityId,
      'audio',
    );
    final fileName = 'segment-001$ext';
    final relFilePath = p.posix.join(relAudioDir, fileName);

    final targetFile = MediaPaths.resolve(root, relFilePath);
    final partialFile = File('${targetFile.path}.partial');

    // 7. Atomic copy to temporary name (.partial) and rename
    final String sha256Hex;
    try {
      partialFile.parent.createSync(recursive: true);
      sourceFile.copySync(partialFile.path);
      // Atomic rename once copy is complete
      partialFile.renameSync(targetFile.path);

      // Compute SHA-256 checksum in chunks
      final raf = targetFile.openSync();
      try {
        final digestSink = _DigestSink();
        final hasher = sha256.startChunkedConversion(digestSink);
        while (true) {
          final chunk = raf.readSync(64 * 1024);
          if (chunk.isEmpty) break;
          hasher.add(chunk);
        }
        hasher.close();
        sha256Hex = digestSink.value.toString();
      } finally {
        raf.closeSync();
      }
    } catch (e) {
      // Failure mid-copy leaves no file
      try {
        if (partialFile.existsSync()) partialFile.deleteSync();
        if (targetFile.existsSync()) targetFile.deleteSync();
        if (partialFile.parent.existsSync() &&
            partialFile.parent.listSync().isEmpty) {
          partialFile.parent.deleteSync();
        }
      } catch (_) {}
      return AudioImportFailure(
        AudioImportFailureReason.ioError,
        details: 'Copy failed: $e',
      );
    }
    final now = clock().toUtc();
    final title = activityTitleFromFileName(
      picked.name.isNotEmpty ? picked.name : p.basename(picked.path),
    );

    // 8. Commit activity and segment to database
    try {
      final activity = await activities.create(
        id: activityId,
        conferenceId: conferenceId,
        typeId: effectiveTypeId,
        title: title,
        actualStart: now,
        actualEnd: now.add(inspected.duration),
        status: ActivityStatus.completed,
        recordingPermissionStatus: RecordingPermissionStatus.permitted,
        tags: const [importedAudioTag],
      );

      final segment = await media.addImportedSegment(
        id: segmentId,
        activityId: activityId,
        filePath: relFilePath,
        requestedProfile: conf.defaultRecordingProfile,
        codec: inspected.codec,
        container: inspected.container,
        channelCount: inspected.channelCount,
        sampleRateHz: inspected.sampleRateHz,
        requestedBitrateBps:
            inspected.bitrateBps ??
            conf.defaultRecordingProfile.targetBitrateBps,
        observedBitrateBps: inspected.bitrateBps,
        inputRoute: importedInputRoute,
        startUtc: now,
        endUtc: now.add(inspected.duration),
        durationMs: inspected.duration.inMilliseconds,
        bytes: fileBytes,
        sha256: sha256Hex,
      );

      return AudioImportSuccess(activity: activity, segment: segment);
    } catch (e) {
      // If DB fails, clean up target file to leave no orphaned audio
      try {
        if (targetFile.existsSync()) targetFile.deleteSync();
        if (targetFile.parent.existsSync() &&
            targetFile.parent.listSync().isEmpty) {
          targetFile.parent.deleteSync();
        }
      } catch (_) {}
      return AudioImportFailure(
        AudioImportFailureReason.ioError,
        details: 'Database insert failed: $e',
      );
    }
  }

  Future<String> _defaultTypeId() async {
    final types = await activities.types();
    for (final t in types) {
      if (t.key == 'session') return t.id;
    }
    return types.isNotEmpty ? types.first.id : builtinActivityTypes.first.id;
  }
}

class _DigestSink implements Sink<Digest> {
  late Digest value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}

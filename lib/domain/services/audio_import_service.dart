import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:file_selector/file_selector.dart';
import 'package:path/path.dart' as p;

import '../../data/filesystem/media_paths.dart';
import '../../data/local_database/app_database.dart';
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
///
/// Decides imported status from segment provenance ([RecordingSegment.inputRoute] == 'imported')
/// when segments are known. Never decides imported status from user-editable tags alone.
bool isActivityImported(
  Activity activity, [
  Iterable<RecordingSegment>? segments,
]) {
  if (segments != null) {
    return segments.any((s) => s.inputRoute == importedInputRoute);
  }
  return false;
}

/// Derives a clean activity title from the imported file name (FR-TRN-03) [P2-13].
String activityTitleFromFileName(String fileName) {
  final stem = p.basenameWithoutExtension(fileName).trim();
  return stem.isEmpty ? 'Imported audio' : stem;
}

/// Progress of an audio import copy.
class AudioImportProgress {
  const AudioImportProgress({
    required this.bytesDone,
    required this.bytesTotal,
  });

  final int bytesDone;
  final int bytesTotal;

  double get fraction =>
      bytesTotal <= 0 ? 0.0 : (bytesDone / bytesTotal).clamp(0.0, 1.0);
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
  importAlreadyRunning,
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
      case AudioImportFailureReason.importAlreadyRunning:
        return 'An audio import is already in progress. Please wait for it to finish.';
    }
  }
}

/// Service that imports an audio file recorded elsewhere into an activity (FR-TRN-03) [P2-13].
///
/// Features:
/// - Reuses injectable [AudioFilePicker] and [AudioFileInspector].
/// - Validates extensions (.m4a, .mp3, .wav, .aac) and reads duration before copying.
/// - Checks free space via [FreeSpaceProbe] with safety margin.
/// - Performs atomic stream copy to `.partial` with backpressure and renames only on complete copy.
/// - If copy fails or cancels mid-way, leaves no file and no database activity.
/// - Leaves the original source file completely untouched (never moved, modified or deleted).
/// - Marks activity and segment as imported (`imported` tag and `imported` inputRoute).
/// - Refuses import while recording is active to avoid microphone/resource conflicts.
/// - Allows only one import at a time and protects active staging files from cleanup.
class AudioImportService {
  AudioImportService({
    this.db,
    required this.activities,
    required this.conferences,
    required this.media,
    required this.mediaRoot,
    this.picker = const FileSelectorAudioPicker(),
    this.inspector = const DefaultAudioFileInspector(),
    this.freeSpace = const UnknownFreeSpaceProbe(),
    this.safetyMarginBytes = defaultAudioImportSafetyMarginBytes,
    this.isRecordingActive,
    this.withRecordingGuard,
    this.clock = systemUtcClock,
    this.newId = uuidV4,
    this.openRead,
    this.openWrite,
  });

  final AppDatabase? db;
  final ActivityRepository activities;
  final ConferenceRepository conferences;
  final MediaAssetRepository media;
  final Future<Directory> Function() mediaRoot;
  final AudioFilePicker picker;
  final AudioFileInspector inspector;
  final FreeSpaceProbe freeSpace;
  final int safetyMarginBytes;
  final bool Function()? isRecordingActive;
  final Future<T> Function<T>(Future<T> Function() action)? withRecordingGuard;
  final UtcClock clock;
  final IdGenerator newId;
  final Stream<List<int>> Function(File file)? openRead;
  final IOSink Function(File file)? openWrite;

  /// Active staging files currently being written by in-progress imports.
  static final Set<String> _activeStagingRelativePaths = <String>{};

  /// Suffix used for temporary files while streaming imported audio into place.
  static const importStagingSuffix = '.importing';

  /// Whether [relativePath] is positively identified as an import staging file.
  static bool isImportStagingPath(String relativePath) {
    final lower = relativePath.toLowerCase();
    return lower.endsWith(importStagingSuffix) ||
        lower.contains('/import-staging/') ||
        lower.contains(r'\import-staging\');
  }

  /// Whether an import is currently in progress across the application.
  static bool _isAnyImportActive = false;

  /// Removes abandoned import staging files left behind if the app was killed
  /// during an import before a database record could be committed.
  ///
  /// Cleans ONLY files positively identified as abandoned import staging files
  /// (e.g. files with [.importing] suffix or within an `import-staging` folder).
  /// Never deletes recording files, partial recordings, or anything handled
  /// by [CrashRecoveryService].
  static Future<int> cleanupAbandonedImports({
    required Directory root,
    MediaAssetRepository? media,
    Set<String>? activeStagingPaths,
  }) async {
    final conferencesDir = Directory(p.join(root.path, 'conferences'));
    if (!conferencesDir.existsSync()) return 0;

    final activePaths = activeStagingPaths ?? _activeStagingRelativePaths;
    // Final paths saved segments point at: a staging file for one of these
    // was committed but not yet renamed when the app stopped.
    final committed = await media?.segmentPaths() ?? const <String>{};
    var cleaned = 0;

    final entities = conferencesDir.listSync(recursive: true);
    for (final entity in entities) {
      if (entity is! File) continue;
      final rel = p.posix.joinAll(
        p.split(p.relative(entity.path, from: root.path)),
      );
      if (activePaths.contains(rel)) continue;

      if (isImportStagingPath(rel)) {
        final finalRel = rel.toLowerCase().endsWith(importStagingSuffix)
            ? rel.substring(0, rel.length - importStagingSuffix.length)
            : null;
        if (finalRel != null && committed.contains(finalRel)) {
          final target = File(
            p.join(root.path, p.joinAll(p.posix.split(finalRel))),
          );
          try {
            if (!target.existsSync()) {
              entity.renameSync(target.path);
              continue;
            }
          } catch (_) {}
        }
        try {
          entity.deleteSync();
          cleaned++;
          final parent = entity.parent;
          if (parent.existsSync() && parent.listSync().isEmpty) {
            parent.deleteSync();
            final grandParent = parent.parent;
            if (grandParent.existsSync() && grandParent.listSync().isEmpty) {
              grandParent.deleteSync();
            }
          }
        } catch (_) {}
      }
    }
    return cleaned;
  }

  /// Prompts the user to pick an audio file and imports it into [conferenceId].
  ///
  /// Optionally accepts [sourceFileOverride] (for direct testing or programmatic calls).
  Future<AudioImportOutcome> importAudio({
    required String conferenceId,
    String? typeId,
    XFile? sourceFileOverride,
    void Function(AudioImportProgress progress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    // 0. Only allow one import at a time (FR-TRN-03) [P2-13].
    if (_isAnyImportActive) {
      return const AudioImportFailure(
        AudioImportFailureReason.importAlreadyRunning,
        details: 'Another audio import is currently in progress',
      );
    }

    // 1. Refuse import while recording is active (FR-TRN-03 item 6)
    if (isRecordingActive?.call() == true) {
      return const AudioImportFailure(AudioImportFailureReason.recordingActive);
    }

    if (isCancelled?.call() == true) {
      return const AudioImportCancelled();
    }

    _isAnyImportActive = true;
    try {
      final root = await mediaRoot();

      // Clean up any abandoned partial files from previous interrupted imports
      await cleanupAbandonedImports(root: root, media: media);

      // 2. Pick audio file
      final picked = sourceFileOverride ?? await picker.pickAudio();
      if (picked == null) {
        return const AudioImportCancelled();
      }

      if (isCancelled?.call() == true) {
        return const AudioImportCancelled();
      }

      // 3. Check recording active again after picker await
      if (isRecordingActive?.call() == true) {
        return const AudioImportFailure(
          AudioImportFailureReason.recordingActive,
        );
      }

      // 4. Check format / extension
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

      // 5. Inspect audio duration and format before copying
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

      if (isCancelled?.call() == true) {
        return const AudioImportCancelled();
      }

      // Check recording again after inspection await
      if (isRecordingActive?.call() == true) {
        return const AudioImportFailure(
          AudioImportFailureReason.recordingActive,
        );
      }

      // 6. Check free space with safety margin
      final int fileBytes;
      try {
        if (!sourceFile.existsSync()) {
          return const AudioImportFailure(
            AudioImportFailureReason.unreadableFile,
            details: 'Source audio file does not exist',
          );
        }
        fileBytes = await sourceFile.length();
      } catch (e) {
        return AudioImportFailure(
          AudioImportFailureReason.unreadableFile,
          details: 'Could not read source audio file: $e',
        );
      }

      final space = await freeSpace.query(root.path);
      if (space != null &&
          space.availableBytes - fileBytes < safetyMarginBytes) {
        return AudioImportFailure(
          AudioImportFailureReason.lowStorage,
          details:
              'Available: ${space.availableBytes}, needed: ${fileBytes + safetyMarginBytes}',
        );
      }

      // 7. Resolve activity and segment targets
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
      final relStagingPath = '$relFilePath$importStagingSuffix';

      final targetFile = MediaPaths.resolve(root, relFilePath);
      final stagingFile = MediaPaths.resolve(root, relStagingPath);

      _activeStagingRelativePaths.add(relStagingPath);
      try {
        // 8. Streamed copy to temporary staging name (.importing) with backpressure and concurrent SHA-256 calculation
        final String sha256Hex;
        try {
          stagingFile.parent.createSync(recursive: true);

          final digestSink = _DigestSink();
          final hasher = sha256.startChunkedConversion(digestSink);

          final stream = openRead != null
              ? openRead!(sourceFile)
              : sourceFile.openRead();
          final sink = openWrite != null
              ? openWrite!(stagingFile)
              : stagingFile.openWrite();

          var bytesCopied = 0;
          var wasCancelled = false;
          var wasInterruptedByRecording = false;

          try {
            await for (final chunk in stream) {
              if (isCancelled?.call() == true) {
                wasCancelled = true;
                break;
              }
              if (isRecordingActive?.call() == true) {
                wasInterruptedByRecording = true;
                break;
              }

              hasher.add(chunk);
              sink.add(chunk);
              await sink.flush();
              bytesCopied += chunk.length;
              onProgress?.call(
                AudioImportProgress(
                  bytesDone: bytesCopied,
                  bytesTotal: fileBytes,
                ),
              );
            }
          } finally {
            await sink.close();
          }

          if (wasCancelled) {
            _cleanupFiles(stagingFile, targetFile);
            return const AudioImportCancelled();
          }

          if (wasInterruptedByRecording) {
            _cleanupFiles(stagingFile, targetFile);
            return const AudioImportFailure(
              AudioImportFailureReason.recordingActive,
            );
          }

          hasher.close();
          sha256Hex = digestSink.value.toString();

          // Check recording again immediately before committing the import
          if (isRecordingActive?.call() == true) {
            _cleanupFiles(stagingFile, targetFile);
            return const AudioImportFailure(
              AudioImportFailureReason.recordingActive,
            );
          }

          if (isCancelled?.call() == true) {
            _cleanupFiles(stagingFile, targetFile);
            return const AudioImportCancelled();
          }
        } catch (e) {
          _cleanupFiles(stagingFile, targetFile);
          return AudioImportFailure(
            AudioImportFailureReason.ioError,
            details: 'Copy failed: $e',
          );
        }

        final now = clock().toUtc();
        final title = activityTitleFromFileName(
          picked.name.isNotEmpty ? picked.name : p.basename(picked.path),
        );

        // Check recording again immediately before database transaction
        if (isRecordingActive?.call() == true) {
          _cleanupFiles(stagingFile, targetFile);
          return const AudioImportFailure(
            AudioImportFailureReason.recordingActive,
          );
        }

        // 9. Commit activity and segment to database in one single transaction under recording guard
        Future<AudioImportOutcome> performCommit() async {
          if (isRecordingActive?.call() == true) {
            _cleanupFiles(stagingFile, targetFile);
            return const AudioImportFailure(
              AudioImportFailureReason.recordingActive,
            );
          }

          try {
            Activity? activity;
            RecordingSegment? segment;

            Future<void> performInserts() async {
              activity = await activities.create(
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

              segment = await media.addImportedSegment(
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
            }

            if (db != null) {
              await db!.transaction(performInserts);
            } else {
              await performInserts();
            }

            // Rename only after the rows are committed. A kill between the
            // two leaves a staging file whose final path a segment names;
            // cleanupAbandonedImports finishes that rename at next start.
            try {
              stagingFile.renameSync(targetFile.path);
            } on FileSystemException {
              await activities.delete(activityId);
              rethrow;
            }

            return AudioImportSuccess(activity: activity!, segment: segment!);
          } catch (e) {
            // If DB fails, clean up target and staging files to leave no orphaned audio
            _cleanupFiles(stagingFile, targetFile);
            return AudioImportFailure(
              AudioImportFailureReason.ioError,
              details: 'Database insert failed: $e',
            );
          }
        }

        if (withRecordingGuard != null) {
          return await withRecordingGuard!(performCommit);
        } else {
          return await performCommit();
        }
      } finally {
        _activeStagingRelativePaths.remove(relStagingPath);
      }
    } catch (e) {
      return AudioImportFailure(
        AudioImportFailureReason.unreadableFile,
        details: 'The audio file could not be read: $e',
      );
    } finally {
      _isAnyImportActive = false;
    }
  }

  static void _cleanupFiles(File stagingFile, File targetFile) {
    try {
      if (stagingFile.existsSync()) stagingFile.deleteSync();
      if (targetFile.existsSync()) targetFile.deleteSync();
      final parent = stagingFile.parent;
      if (parent.existsSync() && parent.listSync().isEmpty) {
        parent.deleteSync();
        final grandParent = parent.parent;
        if (grandParent.existsSync() && grandParent.listSync().isEmpty) {
          grandParent.deleteSync();
        }
      }
    } catch (_) {}
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

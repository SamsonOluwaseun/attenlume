import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../data/filesystem/media_paths.dart';
import '../../data/repositories/repository_providers.dart';
import '../../domain/services/capture_settings.dart';
import '../../domain/services/recording_service.dart';
import '../../domain/services/recording_state.dart';
import '../../platform/audio_capture/audio_capture_engine.dart';
import '../../platform/audio_capture/record_capture_engine.dart';

// Recording wiring [P1-04]. Tests override audioCaptureEngineProvider and
// mediaRootProvider.

/// The platform this build runs on, for encoder settings (ADR-002).
CapturePlatform currentCapturePlatform() {
  if (Platform.isWindows) return CapturePlatform.windows;
  if (Platform.isIOS) return CapturePlatform.ios;
  return CapturePlatform.android;
}

final audioCaptureEngineProvider = Provider<AudioCaptureEngine>(
  (ref) => RecordCaptureEngine(),
);

/// `<app documents>/media/` (BUILD_GUIDE 9.5).
final mediaRootProvider = Provider<Future<Directory> Function()>(
  (ref) =>
      () async => Directory(
        p.join(
          (await getApplicationDocumentsDirectory()).path,
          MediaPaths.rootFolderName,
        ),
      ),
);

/// The single recorder for the app (NFR-04, FR-REC-09).
final recordingServiceProvider = Provider<RecordingService>((ref) {
  final service = RecordingService(
    engine: ref.watch(audioCaptureEngineProvider),
    activities: ref.watch(activityRepositoryProvider),
    media: ref.watch(mediaAssetRepositoryProvider),
    mediaRoot: ref.watch(mediaRootProvider),
    platform: currentCapturePlatform(),
  );
  ref.onDispose(service.dispose);
  return service;
});

final recordingStatusProvider = StreamProvider<RecordingStatus>((ref) async* {
  final service = ref.watch(recordingServiceProvider);
  yield service.status;
  yield* service.statusStream;
});

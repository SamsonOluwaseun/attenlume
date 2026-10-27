import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../data/filesystem/media_paths.dart';
import '../../data/repositories/repository_providers.dart';
import '../../domain/services/capture_settings.dart';
import '../../domain/services/crash_recovery_service.dart';
import '../../domain/services/interruption_coordinator.dart';
import '../../domain/services/one_active_coordinator.dart';
import '../../domain/services/recording_service.dart';
import '../../domain/services/recording_state.dart';
import '../../platform/audio_capture/audio_capture_engine.dart';
import '../../platform/audio_capture/record_capture_engine.dart';
import '../../platform/audio_route/audio_route_probe.dart';
import '../../platform/audio_route/audio_session_route_probe.dart';
import '../../platform/audio_route/engine_route_probe.dart';
import '../../platform/interruptions/audio_interruption_source.dart';
import '../../platform/interruptions/audio_session_interruption_source.dart';

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

/// Which microphone is in use (ADR-016) [P0-07]. Windows only lists the
/// engine's inputs.
final audioRouteProbeProvider = Provider<AudioRouteProbe>(
  (ref) => Platform.isWindows
      ? EngineRouteProbe(ref.watch(audioCaptureEngineProvider))
      : AudioSessionRouteProbe(),
);

/// Audio session and interruption events (ADR-013). Windows has none.
final audioInterruptionSourceProvider = Provider<AudioInterruptionSource>(
  (ref) => Platform.isWindows
      ? const NoAudioInterruptions()
      : AudioSessionInterruptionSource(),
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
    routes: ref.watch(audioRouteProbeProvider),
    session: ref.watch(audioInterruptionSourceProvider),
  );
  ref.onDispose(service.dispose);
  return service;
});

final recordingStatusProvider = StreamProvider<RecordingStatus>((ref) async* {
  final service = ref.watch(recordingServiceProvider);
  yield service.status;
  yield* service.statusStream;
});

/// Confirmations for shortcut and voice starts, shown in the app until
/// notifications (P1-11) and haptics take over [P1-06].
final triggerConfirmationsProvider = Provider<InAppTriggerConfirmations>((ref) {
  final sink = InAppTriggerConfirmations();
  ref.onDispose(sink.dispose);
  return sink;
});

/// Interruption notices, shown in the app until the P1-11 notification
/// takes over [P1-07].
final interruptionNoticesProvider = Provider<InAppInterruptionNotices>((ref) {
  final sink = InAppInterruptionNotices();
  ref.onDispose(sink.dispose);
  return sink;
});

/// Listens for calls, alarms, other apps, the camera and device changes
/// while the recorder exists (FR-REC-05, FR-PHO-07) [P1-07].
final interruptionCoordinatorProvider = Provider<InterruptionCoordinator>((
  ref,
) {
  final coordinator = InterruptionCoordinator(
    recorder: ref.watch(recordingServiceProvider),
    source: ref.watch(audioInterruptionSourceProvider),
    notices: ref.watch(interruptionNoticesProvider),
    // Only iOS reports the active input (ADR-016).
    forceRouteRoll: !Platform.isIOS,
  )..start();
  ref.onDispose(coordinator.dispose);
  return coordinator;
});

/// Every start goes through here so the one-active rule holds for all
/// triggers (FR-REC-04) [P1-06]. Creating it also starts the
/// [interruptionCoordinatorProvider], so no recording runs unwatched.
final oneActiveCoordinatorProvider = Provider<OneActiveCoordinator>((ref) {
  ref.watch(interruptionCoordinatorProvider);
  return OneActiveCoordinator(
    recorder: ref.watch(recordingServiceProvider),
    activities: ref.watch(activityRepositoryProvider),
    media: ref.watch(mediaAssetRepositoryProvider),
    confirmations: ref.watch(triggerConfirmationsProvider),
  );
});

/// Reconciles the database with segment files (FR-REC-08) [P1-08].
final crashRecoveryServiceProvider = Provider<CrashRecoveryService>(
  (ref) => CrashRecoveryService(
    activities: ref.watch(activityRepositoryProvider),
    media: ref.watch(mediaAssetRepositoryProvider),
    mediaRoot: ref.watch(mediaRootProvider),
    recorderStatus: () => ref.read(recordingServiceProvider).status,
  ),
);

/// Runs recovery once per app start. The `CrashRecoveryGate` shows the
/// result.
final crashRecoveryReportProvider = FutureProvider<RecoveryReport>(
  (ref) => ref.watch(crashRecoveryServiceProvider).reconcile(),
);

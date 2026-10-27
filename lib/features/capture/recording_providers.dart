import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../data/filesystem/app_data_directory.dart';
import '../../data/filesystem/media_paths.dart';
import '../../data/repositories/repository_providers.dart';
import '../../domain/services/capture_settings.dart';
import '../../domain/services/crash_recovery_service.dart';
import '../../domain/services/foreground_service_coordinator.dart';
import '../../domain/services/interruption_coordinator.dart';
import '../../domain/services/one_active_coordinator.dart';
import '../../domain/services/photo_capture_service.dart';
import '../../domain/services/recording_service.dart';
import '../../domain/services/recording_state.dart';
import '../../domain/services/safety_prompt_service.dart';
import '../../domain/services/storage_budget_service.dart';
import '../../platform/audio_capture/audio_capture_engine.dart';
import '../../platform/audio_capture/record_capture_engine.dart';
import '../../platform/audio_route/audio_route_probe.dart';
import '../../platform/audio_route/audio_session_route_probe.dart';
import '../../platform/audio_route/engine_route_probe.dart';
import '../../platform/camera/photo_camera.dart';
import '../../platform/camera/plugin_photo_camera.dart';
import '../../platform/diagnostics/battery_probe.dart';
import '../../platform/foreground_service/foreground_service_bridge.dart';
import '../../platform/interruptions/audio_interruption_source.dart';
import '../../platform/interruptions/audio_session_interruption_source.dart';
import '../../platform/storage/free_space_probe.dart';

// Recording wiring [P1-04]. Tests override audioCaptureEngineProvider and
// mediaRootProvider.

/// The platform this build runs on, for encoder settings (ADR-002).
CapturePlatform currentCapturePlatform() {
  if (Platform.isWindows) return CapturePlatform.windows;
  if (Platform.isIOS) return CapturePlatform.ios;
  return CapturePlatform.android;
}

/// The platform for encoder settings and estimates. Tests override it.
final capturePlatformProvider = Provider<CapturePlatform>(
  (ref) => currentCapturePlatform(),
);

final audioCaptureEngineProvider = Provider<AudioCaptureEngine>(
  (ref) => RecordCaptureEngine(),
);

/// Camera for still photos during recording (ADR-017, FR-UI-03).
final photoCameraProvider = Provider<PhotoCamera>((ref) {
  final camera = PluginPhotoCamera();
  ref.onDispose(camera.close);
  return camera;
});

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

/// `<app data>/media/` (BUILD_GUIDE 9.5, ADR-028).
final mediaRootProvider = Provider<Future<Directory> Function()>(
  (ref) =>
      () async => Directory(
        p.join((await appDataDirectory()).path, MediaPaths.rootFolderName),
      ),
);

/// Free-space query for the volume that holds recordings (P0-11).
final freeSpaceProbeProvider = Provider<FreeSpaceProbe>(
  (ref) => FreeSpaceProbe.forPlatform(),
);

/// Bytes free where recordings are written, or null when unknown. Read
/// fresh each time a selector opens (FR-UI-08) [P1-09].
final mediaFreeBytesProvider = FutureProvider.autoDispose<int?>((ref) async {
  try {
    final root = await ref.watch(mediaRootProvider)();
    final space = await ref.watch(freeSpaceProbeProvider).query(root.path);
    return space?.availableBytes;
  } on Object {
    return null;
  }
});

/// The single recorder for the app (NFR-04, FR-REC-09).
final recordingServiceProvider = Provider<RecordingService>((ref) {
  final service = RecordingService(
    engine: ref.watch(audioCaptureEngineProvider),
    activities: ref.watch(activityRepositoryProvider),
    media: ref.watch(mediaAssetRepositoryProvider),
    mediaRoot: ref.watch(mediaRootProvider),
    platform: ref.watch(capturePlatformProvider),
    routes: ref.watch(audioRouteProbeProvider),
    session: ref.watch(audioInterruptionSourceProvider),
    freeSpaceProbe: ref.watch(freeSpaceProbeProvider),
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

/// Platform bridge for Android foreground service and ongoing notification [P1-11, FR-REC-10].
final foregroundServiceBridgeProvider = Provider<ForegroundServiceBridge>((
  ref,
) {
  if (Platform.isAndroid) {
    final bridge = MethodChannelForegroundServiceBridge();
    ref.onDispose(bridge.dispose);
    return bridge;
  }
  return const NoopForegroundServiceBridge();
});

/// Coordinates the foreground service and persistent notification with
/// the recording lifecycle, notification actions, and interruptions [P1-11, FR-REC-10].
final foregroundServiceCoordinatorProvider =
    Provider<ForegroundServiceCoordinator>((ref) {
      final coordinator = ForegroundServiceCoordinator(
        recorder: ref.watch(recordingServiceProvider),
        activities: ref.watch(activityRepositoryProvider),
        media: ref.watch(mediaAssetRepositoryProvider),
        bridge: ref.watch(foregroundServiceBridgeProvider),
        inAppNotices: ref.watch(interruptionNoticesProvider),
      )..start();
      ref.onDispose(coordinator.dispose);
      return coordinator;
    });

/// Listens for calls, alarms, other apps, the camera and device changes
/// while the recorder exists (FR-REC-05, FR-PHO-07) [P1-07].
final interruptionCoordinatorProvider = Provider<InterruptionCoordinator>((
  ref,
) {
  final coordinator = InterruptionCoordinator(
    recorder: ref.watch(recordingServiceProvider),
    source: ref.watch(audioInterruptionSourceProvider),
    notices: ref.watch(foregroundServiceCoordinatorProvider),
    // Only iOS reports the active input (ADR-016).
    forceRouteRoll: !Platform.isIOS,
  )..start();
  ref.onDispose(coordinator.dispose);
  return coordinator;
});

/// Battery level for the low-battery prompt (ADR-032).
final batteryProbeProvider = Provider<BatteryProbe>(
  (ref) => BatteryProbe.forPlatform(),
);

/// Still recording after 2 hours, near-silence, low battery (FR-REC-06)
/// [P1-13].
final safetyPromptServiceProvider = Provider<SafetyPromptService>((ref) {
  final engine = ref.watch(audioCaptureEngineProvider);
  final service = SafetyPromptService(
    recorder: ref.watch(recordingServiceProvider),
    level: engine.levelDbfs,
    battery: ref.watch(batteryProbeProvider),
  )..start();
  ref.onDispose(service.dispose);
  return service;
});

/// In-app photos with compression and thumbnails [P1-14].
final photoCaptureServiceProvider = Provider<PhotoCaptureService>(
  (ref) => PhotoCaptureService(
    camera: ref.watch(photoCameraProvider),
    activities: ref.watch(activityRepositoryProvider),
    media: ref.watch(mediaAssetRepositoryProvider),
    mediaRoot: ref.watch(mediaRootProvider),
    interruptions: ref.watch(interruptionCoordinatorProvider),
  ),
);

/// Tracks disk free space, rolling minutes left from measured file growth,
/// and enforces the hard stop reserve (FR-STO-01 to 04, FR-UI-07) [P1-12].
final storageBudgetServiceProvider = Provider<StorageBudgetService>((ref) {
  final service = StorageBudgetService(
    recorder: ref.watch(recordingServiceProvider),
    activities: ref.watch(activityRepositoryProvider),
    media: ref.watch(mediaAssetRepositoryProvider),
    mediaRoot: ref.watch(mediaRootProvider),
    freeSpaceProbe: ref.watch(freeSpaceProbeProvider),
    platform: ref.watch(capturePlatformProvider),
  )..start();
  ref.onDispose(service.dispose);
  return service;
});

final storageBudgetSnapshotProvider = StreamProvider<StorageBudgetSnapshot>((
  ref,
) async* {
  final service = ref.watch(storageBudgetServiceProvider);
  yield service.currentSnapshot;
  yield* service.snapshotStream;
});

/// Every start goes through here so the one-active rule holds for all
/// triggers (FR-REC-04) [P1-06]. Creating it also starts the
/// [interruptionCoordinatorProvider], [foregroundServiceCoordinatorProvider],
/// [storageBudgetServiceProvider] and [safetyPromptServiceProvider], so no
/// recording runs unwatched.
final oneActiveCoordinatorProvider = Provider<OneActiveCoordinator>((ref) {
  ref.watch(interruptionCoordinatorProvider);
  ref.watch(foregroundServiceCoordinatorProvider);
  ref.watch(storageBudgetServiceProvider);
  ref.watch(safetyPromptServiceProvider);
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

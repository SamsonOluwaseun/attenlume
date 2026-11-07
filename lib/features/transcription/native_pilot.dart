import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;

import '../../domain/transcription/transcription_engine.dart';
import '../../platform/transcription/whisper_cpu.dart';
import '../../platform/transcription/whisper_model_store.dart';
import '../../platform/transcription/whisper_transcription_engine.dart';
import 'transcription_controller.dart';

class NativeTranscriptionPilot {
  const NativeTranscriptionPilot(this.models, this.createEngine);
  final PilotModelManager models;
  final TranscriptionEngine Function() createEngine;
}

Future<NativeTranscriptionPilot> createNativePilot(
  Directory root, {
  WhisperCpu cpu = const PlatformWhisperCpu(),
}) async {
  requireWhisperCpu(cpu);
  // This pinned Android runtime ships arm64/x86_64 only. Keep the free capture
  // core usable on 32-bit devices without offering an unusable model download.
  if (Platform.isAndroid && ffi.sizeOf<ffi.IntPtr>() != 8) {
    throw UnsupportedError('The transcription pilot needs a 64-bit device.');
  }
  // The platform owns this root. Android can expose it through OS-managed
  // aliases (for example /data/user/0). Resolve that trusted boundary once;
  // model storage still rejects links introduced inside the owned directory.
  final canonicalRoot = await root.resolveSymbolicLinks();
  final store = WhisperModelStore(
    baseDirectory: Directory(p.join(canonicalRoot, 'transcription-models-v1')),
  );
  return NativeTranscriptionPilot(
    PilotModels(store),
    () => WhisperTranscriptionEngine(
      cpu: cpu,
      vadModelPath: () => store.installedPath(PilotModels.vad),
    ),
  );
}

/// The speech model plus the small Silero model that skips silence
/// [P2-11]. Both are one explicit download, removed together.
@visibleForTesting
class PilotModels implements PilotModelManager {
  PilotModels(this.store);
  final VerifiedModelStore store;
  static const descriptor = WhisperModelDescriptor.tinyEnQ5_1;
  static const vad = WhisperModelDescriptor.sileroVad;
  static const _all = [descriptor, vad];
  @override
  String get name => descriptor.name;
  @override
  int get downloadBytes => descriptor.sizeBytes + vad.sizeBytes;
  // Restrict native loading to the selected, explicitly installed model file.
  @override
  String get directory => p.join(store.baseDirectory.path, descriptor.fileName);

  /// Installs made before P2-11 have the speech model only, so they show as
  /// not installed and the next Download adds the missing silence model.
  @override
  Future<bool> isInstalled() async {
    for (final model in _all) {
      if (await store.installedPath(model) == null) return false;
    }
    return true;
  }

  @override
  Future<void> install(void Function(double) onProgress) async {
    final missing = [
      for (final model in _all)
        if (await store.installedPath(model) == null) model,
    ];
    final total = missing.fold<int>(0, (sum, m) => sum + m.sizeBytes);
    var done = 0;
    for (final model in missing) {
      await store.install(
        model,
        onProgress: (p) =>
            onProgress(total == 0 ? 1 : (done + p * model.sizeBytes) / total),
      );
      done += model.sizeBytes;
    }
  }

  @override
  Future<void> cancelInstall() async {
    for (final model in _all) {
      await store.cancelInstall(modelId: model.id);
    }
  }

  @override
  Future<void> remove() async {
    var removed = true;
    for (final model in _all) {
      removed = await store.remove(model) && removed;
    }
    if (!removed) throw StateError('Model removal did not complete');
  }
}

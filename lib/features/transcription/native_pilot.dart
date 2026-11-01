import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../domain/transcription/transcription_engine.dart';
import '../../platform/transcription/whisper_model_store.dart';
import '../../platform/transcription/whisper_transcription_engine.dart';
import 'transcription_controller.dart';

class NativeTranscriptionPilot {
  const NativeTranscriptionPilot(this.models, this.createEngine);
  final PilotModelManager models;
  final TranscriptionEngine Function() createEngine;
}

Future<NativeTranscriptionPilot> createNativePilot(Directory root) async {
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
    _PilotModels(store),
    WhisperTranscriptionEngine.new,
  );
}

class _PilotModels implements PilotModelManager {
  _PilotModels(this.store);
  final WhisperModelStore store;
  static const descriptor = WhisperModelDescriptor.tinyEnQ5_1;
  @override
  String get name => descriptor.name;
  @override
  int get downloadBytes => descriptor.sizeBytes;
  // Restrict native loading to the selected, explicitly installed model file.
  @override
  String get directory =>
      p.join(store.modelDirectory.path, descriptor.fileName);
  @override
  Future<bool> isInstalled() async =>
      await store.installedPath(descriptor) != null;
  @override
  Future<void> install(void Function(double) onProgress) async {
    await store.install(descriptor, onProgress: onProgress);
  }

  @override
  Future<void> cancelInstall() => store.cancelInstall(modelId: descriptor.id);
  @override
  Future<void> remove() async {
    if (!await store.remove(descriptor)) {
      throw StateError('Model removal did not complete');
    }
  }
}

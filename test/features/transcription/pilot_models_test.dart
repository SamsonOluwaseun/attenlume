import 'dart:io';

import 'package:attenlume/features/transcription/native_pilot.dart';
import 'package:attenlume/platform/transcription/whisper_model_store.dart';
import 'package:flutter_test/flutter_test.dart';

class _Store extends Fake implements VerifiedModelStore {
  _Store(this.installed);

  final Set<String> installed;
  final installs = <String>[];
  final removals = <String>[];
  final cancels = <String?>[];

  @override
  Directory get baseDirectory => Directory('models');

  @override
  Future<String?> installedPath(VerifiedModelDescriptor descriptor) async =>
      installed.contains(descriptor.id)
      ? 'models/${descriptor.fileName}'
      : null;

  @override
  Future<String> install(
    VerifiedModelDescriptor descriptor, {
    void Function(double)? onProgress,
  }) async {
    installs.add(descriptor.id);
    onProgress?.call(0.5);
    onProgress?.call(1);
    installed.add(descriptor.id);
    return 'models/${descriptor.fileName}';
  }

  @override
  Future<bool> remove(VerifiedModelDescriptor descriptor) async {
    removals.add(descriptor.id);
    installed.remove(descriptor.id);
    return true;
  }

  @override
  Future<void> cancelInstall({String? modelId}) async => cancels.add(modelId);
}

void main() {
  const speech = WhisperModelDescriptor.tinyEnQ5_1;
  const vad = WhisperModelDescriptor.sileroVad;

  group('P2-11 FR-TRN-10 speech and silence models install together', () {
    test('the silence model is pinned, small and checksummed', () {
      expect(vad.downloadUrl, contains('/resolve/9ffd54a1e1ee413ddf265af9913'));
      expect(vad.sizeBytes, 885098);
      expect(vad.sha256, hasLength(64));
      expect(vad.fileName, isNot(speech.fileName));
    });

    test('a fresh install downloads both with one progress bar', () async {
      final store = _Store({});
      final models = PilotModels(store);
      expect(await models.isInstalled(), isFalse);
      expect(models.downloadBytes, speech.sizeBytes + vad.sizeBytes);

      final progress = <double>[];
      await models.install(progress.add);
      expect(store.installs, [speech.id, vad.id]);
      expect(await models.isInstalled(), isTrue);
      expect(progress, orderedEquals([...progress]..sort()));
      expect(progress.last, closeTo(1, 1e-9));
    });

    test('an install from before P2-11 adds only the silence model', () async {
      final store = _Store({speech.id});
      final models = PilotModels(store);
      expect(await models.isInstalled(), isFalse);
      await models.install((_) {});
      expect(store.installs, [vad.id]);
      expect(await models.isInstalled(), isTrue);
    });

    test('remove and cancel cover both models', () async {
      final store = _Store({speech.id, vad.id});
      final models = PilotModels(store);
      await models.cancelInstall();
      await models.remove();
      expect(store.cancels, [speech.id, vad.id]);
      expect(store.removals, [speech.id, vad.id]);
      expect(await models.isInstalled(), isFalse);
    });

    test('the engine loads the speech model file, not the silence model', () {
      final models = PilotModels(_Store({}));
      expect(models.directory, endsWith(speech.fileName));
    });
  });
}

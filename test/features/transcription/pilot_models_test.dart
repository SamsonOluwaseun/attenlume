import 'dart:io';

import 'package:attenlume/features/transcription/native_pilot.dart';
import 'package:attenlume/platform/transcription/whisper_model_store.dart';
import 'package:flutter_test/flutter_test.dart';

class _Store extends Fake implements VerifiedModelStore {
  _Store(this.installed, {Directory? base})
    : baseDirectory = base ?? Directory('models-not-on-disk');

  final Set<String> installed;
  final installs = <String>[];
  final removals = <String>[];
  final cancels = <String?>[];

  @override
  final Directory baseDirectory;

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

  /// Ids whose removal fails although the file stays on disk.
  final stuck = <String>{};

  @override
  Future<bool> remove(VerifiedModelDescriptor descriptor) async {
    removals.add(descriptor.id);
    if (stuck.contains(descriptor.id)) return false;
    // Like the real store: false when there was no file to remove.
    return installed.remove(descriptor.id);
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

    test('an incomplete set reports its files and removes cleanly', () async {
      final store = _Store({speech.id});
      final models = PilotModels(store);
      expect(await models.isInstalled(), isFalse);
      expect(await models.hasFiles(), isTrue);
      // The silence model was never downloaded: that is not a failure.
      await models.remove();
      expect(store.removals, [speech.id, vad.id]);
      expect(await models.hasFiles(), isFalse);
    });

    test('a file that stays on disk makes removal fail', () async {
      final dir = Directory.systemTemp.createTempSync('pilot_models_');
      addTearDown(() => dir.deleteSync(recursive: true));
      File('${dir.path}/${vad.fileName}').writeAsStringSync('x');
      final store = _Store({speech.id, vad.id}, base: dir)..stuck.add(vad.id);
      await expectLater(PilotModels(store).remove(), throwsStateError);
      expect(store.removals, [speech.id, vad.id]);
    });

    test('the engine loads the speech model file, not the silence model', () {
      final models = PilotModels(_Store({}));
      expect(models.directory, endsWith(speech.fileName));
    });
  });
}

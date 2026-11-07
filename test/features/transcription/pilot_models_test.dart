import 'dart:io';

import 'package:attenlume/features/transcription/native_pilot.dart';
import 'package:attenlume/platform/transcription/whisper_model_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Keeps real files in a temporary folder; [verified] stands in for the
/// checksum marker that makes a file count as installed.
class _Store extends Fake implements VerifiedModelStore {
  _Store(this.baseDirectory, Set<String> verified) {
    for (final id in verified) {
      _write(id);
      this.verified.add(id);
    }
  }

  @override
  final Directory baseDirectory;
  final verified = <String>{};
  final installs = <String>[];
  final removals = <String>[];
  final cancels = <String?>[];

  /// Ids whose removal fails although the file stays on disk.
  final stuck = <String>{};

  static const _byId = {
    'tiny.en-q5_1': WhisperModelDescriptor.tinyEnQ5_1,
    'silero-v6.2.0': WhisperModelDescriptor.sileroVad,
  };

  File file(String id) => File(p.join(baseDirectory.path, _byId[id]!.fileName));

  void _write(String id) => file(id).writeAsStringSync('weights');

  @override
  Future<String?> installedPath(VerifiedModelDescriptor descriptor) async =>
      verified.contains(descriptor.id) ? file(descriptor.id).path : null;

  @override
  Future<String> install(
    VerifiedModelDescriptor descriptor, {
    void Function(double)? onProgress,
  }) async {
    installs.add(descriptor.id);
    onProgress?.call(0.5);
    onProgress?.call(1);
    _write(descriptor.id);
    verified.add(descriptor.id);
    return file(descriptor.id).path;
  }

  @override
  Future<bool> remove(VerifiedModelDescriptor descriptor) async {
    removals.add(descriptor.id);
    if (stuck.contains(descriptor.id)) return false;
    verified.remove(descriptor.id);
    // Like the real store: false when there was no file to remove.
    final f = file(descriptor.id);
    if (!f.existsSync()) return false;
    f.deleteSync();
    return true;
  }

  @override
  Future<void> cancelInstall({String? modelId}) async => cancels.add(modelId);
}

void main() {
  const speech = WhisperModelDescriptor.tinyEnQ5_1;
  const vad = WhisperModelDescriptor.sileroVad;
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('pilot_models_'));
  tearDown(() => dir.deleteSync(recursive: true));

  group('P2-11 FR-TRN-10 speech and silence models install together', () {
    test('the silence model is pinned, small and checksummed', () {
      expect(vad.downloadUrl, contains('/resolve/9ffd54a1e1ee413ddf265af9913'));
      expect(vad.sizeBytes, 885098);
      expect(vad.sha256, hasLength(64));
      expect(vad.fileName, isNot(speech.fileName));
    });

    test('a fresh install downloads both with one progress bar', () async {
      final store = _Store(dir, {});
      final models = PilotModels(store);
      expect(await models.isInstalled(), isFalse);
      expect(await models.hasFiles(), isFalse);
      expect(models.downloadBytes, speech.sizeBytes + vad.sizeBytes);

      final progress = <double>[];
      await models.install(progress.add);
      expect(store.installs, [speech.id, vad.id]);
      expect(await models.isInstalled(), isTrue);
      expect(progress, orderedEquals([...progress]..sort()));
      expect(progress.last, closeTo(1, 1e-9));
    });

    test('an install from before P2-11 adds only the silence model', () async {
      final store = _Store(dir, {speech.id});
      final models = PilotModels(store);
      expect(await models.isInstalled(), isFalse);
      await models.install((_) {});
      expect(store.installs, [vad.id]);
      expect(await models.isInstalled(), isTrue);
    });

    test('remove and cancel cover both models', () async {
      final store = _Store(dir, {speech.id, vad.id});
      final models = PilotModels(store);
      await models.cancelInstall();
      await models.remove();
      expect(store.cancels, [speech.id, vad.id]);
      expect(store.removals, [speech.id, vad.id]);
      expect(await models.isInstalled(), isFalse);
      expect(await models.hasFiles(), isFalse);
    });

    test('an incomplete set reports its files and removes cleanly', () async {
      final store = _Store(dir, {speech.id});
      final models = PilotModels(store);
      expect(await models.isInstalled(), isFalse);
      expect(await models.hasFiles(), isTrue);
      // The silence model was never downloaded: that is not a failure.
      await models.remove();
      expect(store.removals, [speech.id, vad.id]);
      expect(await models.hasFiles(), isFalse);
    });

    test(
      'a file without a valid checksum marker can still be removed',
      () async {
        // For example the download finished but writing its marker failed.
        final store = _Store(dir, {})..file(speech.id).writeAsStringSync('w');
        final models = PilotModels(store);
        expect(await models.isInstalled(), isFalse);
        expect(await models.hasFiles(), isTrue);
        await models.remove();
        expect(store.file(speech.id).existsSync(), isFalse);
        expect(await models.hasFiles(), isFalse);
      },
    );

    test('a file that stays on disk makes removal fail', () async {
      final store = _Store(dir, {speech.id, vad.id})..stuck.add(vad.id);
      await expectLater(PilotModels(store).remove(), throwsStateError);
      expect(store.removals, [speech.id, vad.id]);
      expect(await PilotModels(store).hasFiles(), isTrue);
    });

    test('the engine loads the speech model file, not the silence model', () {
      final models = PilotModels(_Store(dir, {}));
      expect(models.directory, endsWith(speech.fileName));
    });
  });
}

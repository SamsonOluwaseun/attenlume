import 'dart:io';

import 'package:attenlume/domain/transcription/transcript.dart';
import 'package:attenlume/platform/transcription/whisper_model_store.dart';
import 'package:attenlume/platform/transcription/whisper_transcription_engine.dart';
import 'package:audio_decoder/audio_decoder.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;

/// Explicit local-only evaluation. No microphone/camera or audio upload.
/// Audio path/output are supplied by the owner via --dart-define; never commit
/// private samples or text. A model may be downloaded ONLY when the separate
/// evaluation-install flag is true. Default execution skips this test.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const audioPath = String.fromEnvironment('TRANSCRIPTION_EVALUATION_AUDIO');
  const outputPath = String.fromEnvironment('TRANSCRIPTION_EVALUATION_OUTPUT');
  const allowInstall = bool.fromEnvironment('TRANSCRIPTION_EVALUATION_INSTALL');
  // Compare with and without silence skipping on the same audio [P2-11].
  const useVad = bool.fromEnvironment('TRANSCRIPTION_EVALUATION_VAD');

  testWidgets(
    'P2-08 FR-TRN-09 explicitly requested local audio evaluation',
    (tester) async {
      await tester.runAsync(() async {
        final output = await Directory(outputPath).create(recursive: true);
        final input = File(audioPath);
        final before = (await sha256.bind(input.openRead()).first).toString();
        final store = WhisperModelStore(
          baseDirectory: Directory(p.join(output.path, 'models')),
        );
        const descriptor = WhisperModelDescriptor.tinyEnQ5_1;
        var model = await store.installedPath(descriptor);
        if (model == null && allowInstall) {
          model = await store.install(descriptor);
        }
        expect(
          model,
          isNotNull,
          reason: 'explicit installation or existing verified model required',
        );
        const vad = WhisperModelDescriptor.sileroVad;
        if (useVad && allowInstall && await store.installedPath(vad) == null) {
          await store.install(vad);
        }
        final vadPath = useVad ? await store.installedPath(vad) : null;
        expect(
          useVad ? vadPath : null,
          useVad ? isNotNull : isNull,
          reason: 'VAD comparison needs an installed silence model',
        );
        final engine = WhisperTranscriptionEngine(
          vadModelPath: useVad ? () async => vadPath : null,
        );
        final info = await AudioDecoder.getAudioInfo(audioPath);
        await AudioDecoder.convertToWav(
          audioPath,
          p.join(output.path, 'decoded-sample.wav'),
          sampleRate: 16000,
          channels: 1,
          bitDepth: 16,
        );
        debugPrint(
          'Local source duration: ${info.duration.inMilliseconds} ms; diagnostic PCM saved privately.',
        );
        final watch = Stopwatch()..start();
        try {
          final spans = await engine.transcribe(
            audioPath: audioPath,
            modelDirectory: model!,
            onProgress: (_) {},
          );
          watch.stop();
          expect(
            spans,
            isNotEmpty,
            reason: 'speech must produce text; no accuracy score without reference wording',
          );
          final document = TranscriptDocument(
            activityId: 'local-evaluation',
            segmentId: 'sample',
            machineSpans: spans,
            createdAt: DateTime.now().toUtc(),
            modelId: descriptor.id,
          );
          await File(p.join(output.path, 'transcript.txt'))
              .writeAsString(renderTranscriptText(document), flush: true);
          await File(p.join(output.path, 'transcript.md'))
              .writeAsString(renderTranscriptMarkdown(document), flush: true);
          final after = (await sha256.bind(input.openRead()).first).toString();
          expect(
            after,
            before,
            reason: 'original sample remains byte-for-byte unchanged',
          );
          debugPrint(
            'Local evaluation (VAD ${useVad ? 'on' : 'off'}): ${spans.length} spans; ${watch.elapsedMilliseconds} ms. Text saved privately; accuracy not scored.',
          );
        } finally {
          await engine.dispose();
        }
      });
    },
    skip: audioPath.isEmpty || outputPath.isEmpty || !Platform.isWindows,
    timeout: const Timeout(Duration(minutes: 8)),
  );
}

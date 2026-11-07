import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/ai/summary_store.dart';
import '../../data/filesystem/app_data_directory.dart';
import '../../data/transcription/transcript_store.dart';
import '../../domain/ai/text_generation_engine.dart';
import '../../domain/transcription/transcript.dart';
import '../../platform/ai/language_model_store.dart';
import '../../platform/ai/llama_text_generation_engine.dart';
import '../ai/language_model_providers.dart';
import '../capture/recording_providers.dart';

/// Where summaries get their model (P3-01, P3-02b). Opening the Summary tab only
/// asks [unavailableReason]; the model is loaded when a summary starts.
abstract interface class SummaryModelAccess {
  /// Null when a summary can be made now, otherwise a sentence for the user.
  Future<String?> unavailableReason();

  /// Loads the model. The caller disposes the engine.
  Future<TextGenerationEngine> open();
}

/// Fallback or test stub representing an unavailable summary model.
class NoSummaryModel implements SummaryModelAccess {
  const NoSummaryModel();

  @override
  Future<String?> unavailableReason() async =>
      'Summaries need the on-device AI model, which is not in this version '
      'of Attenlume yet.';

  @override
  Future<TextGenerationEngine> open() =>
      throw StateError('No summary model on this device');
}

/// Real on-device language model access backed by [LanguageModelStore] and
/// [LlamaTextGenerationEngine] (P3-02b, FR-AI-02).
class OnDeviceSummaryModelAccess implements SummaryModelAccess {
  OnDeviceSummaryModelAccess({
    required this.getStore,
    required this.getDescriptor,
    bool? isIos,
    this.inferenceRunner,
    this.cancelRunner,
    this.contextLengthResolver,
  }) : isIos = isIos ?? Platform.isIOS;

  final Future<LanguageModelStore> Function() getStore;
  final Future<LanguageModelDescriptor> Function() getDescriptor;
  final bool isIos;
  final LlamaInferenceRunner? inferenceRunner;
  final LlamaCancelRunner? cancelRunner;
  final LlamaContextLengthResolver? contextLengthResolver;

  /// Models fully checksummed since this access was created; each model is
  /// verified before its own first load, also after switching (P3-11).
  final _verified = <String>{};

  @override
  Future<String?> unavailableReason() async {
    if (isIos) {
      return 'On-device AI is not supported on iOS for now.';
    }
    final store = await getStore();
    final descriptor = await getDescriptor();
    final path = await store.installedPath(descriptor);
    if (path == null) {
      return 'Download the AI model in Settings > Optional AI';
    }
    return null;
  }

  @override
  Future<TextGenerationEngine> open() async {
    if (isIos) {
      throw UnsupportedError('On-device AI is not supported on iOS for now.');
    }
    final store = await getStore();
    final descriptor = await getDescriptor();

    String? path;
    if (!_verified.contains(descriptor.id)) {
      path = await store.verifyInstalledPath(descriptor);
      if (path != null) {
        _verified.add(descriptor.id);
      }
    } else {
      path = await store.installedPath(descriptor);
    }

    if (path == null) {
      _verified.remove(descriptor.id);
      throw StateError('Download the AI model in Settings > Optional AI');
    }

    return LlamaTextGenerationEngine(
      modelPath: path,
      inferenceRunner: inferenceRunner,
      cancelRunner: cancelRunner,
      contextLengthResolver: contextLengthResolver,
    );
  }
}

final summaryModelAccessProvider = Provider<SummaryModelAccess>(
  (ref) => OnDeviceSummaryModelAccess(
    getStore: () => ref.read(languageModelStoreProvider.future),
    getDescriptor: () => ref.read(activeLanguageModelDescriptorProvider.future),
  ),
);

final summaryStoreProvider = Provider<Future<SummaryStore> Function()>(
  (ref) =>
      () async => SummaryStore(await appDataDirectory()),
);

/// Saved transcripts of one session, as the transcription screen keeps them.
final summaryTranscriptsProvider =
    Provider<Future<List<TranscriptDocument>> Function(String activityId)>(
      (ref) =>
          (activityId) async =>
              TranscriptStore(await appDataDirectory())
                  .listDocuments(activityId: activityId),
    );

/// True while a recording holds the recorder: a summary would compete with
/// it for the processor, so it waits (as transcription does, FR-TRN-03).
final summaryBlockedByRecordingProvider = Provider<bool Function()>(
  (ref) =>
      () => ref.read(recordingServiceProvider).status.state.holdsActivity,
);

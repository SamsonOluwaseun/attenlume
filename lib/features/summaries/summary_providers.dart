import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/ai/summary_store.dart';
import '../../data/filesystem/app_data_directory.dart';
import '../../data/transcription/transcript_store.dart';
import '../../domain/ai/text_generation_engine.dart';
import '../../domain/transcription/transcript.dart';
import '../capture/recording_providers.dart';

/// Where summaries get their model (P3-01). Opening the Summary tab only
/// asks [unavailableReason]; the model is loaded when a summary starts.
abstract interface class SummaryModelAccess {
  /// Null when a summary can be made now, otherwise a sentence for the user.
  Future<String?> unavailableReason();

  /// Loads the model. The caller disposes the engine.
  Future<TextGenerationEngine> open();
}

/// Until the on-device runtime (P3-01) is wired in, summaries say so.
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

final summaryModelAccessProvider = Provider<SummaryModelAccess>(
  (ref) => const NoSummaryModel(),
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

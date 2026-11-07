import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/repository_providers.dart';
import '../../domain/services/audio_import_service.dart';
import '../../platform/audio_import/audio_file_inspector.dart';
import '../../platform/audio_import/audio_file_picker.dart';
import '../capture/recording_providers.dart';

export '../../domain/services/audio_import_service.dart';
export '../../platform/audio_import/audio_file_inspector.dart';
export '../../platform/audio_import/audio_file_picker.dart';

/// Injectable audio file picker for audio import and transcription (FR-TRN-03) [P2-13].
final audioFilePickerProvider = Provider<AudioFilePicker>(
  (ref) => const FileSelectorAudioPicker(),
);

/// Injectable audio inspector for duration and format checks (FR-TRN-03) [P2-13].
final audioFileInspectorProvider = Provider<AudioFileInspector>(
  (ref) => const DefaultAudioFileInspector(),
);

/// Audio import service provider (FR-TRN-03) [P2-13].
final audioImportServiceProvider = Provider<AudioImportService>((ref) {
  return AudioImportService(
    activities: ref.watch(activityRepositoryProvider),
    conferences: ref.watch(conferenceRepositoryProvider),
    media: ref.watch(mediaAssetRepositoryProvider),
    mediaRoot: ref.watch(mediaRootProvider),
    picker: ref.watch(audioFilePickerProvider),
    inspector: ref.watch(audioFileInspectorProvider),
    freeSpace: ref.watch(freeSpaceProbeProvider),
    isRecordingActive: () {
      final status = ref.read(recordingStatusProvider).asData?.value;
      if (status != null) {
        return status.state.holdsActivity;
      }
      try {
        return ref.read(recordingServiceProvider).status.state.holdsActivity;
      } catch (_) {
        return false;
      }
    },
  );
});

import 'package:file_selector/file_selector.dart';

/// Injectable audio file picker for importing audio files recorded elsewhere
/// (FR-TRN-03) [P2-13].
abstract interface class AudioFilePicker {
  /// Prompts the user to pick an audio file. Returns null when cancelled.
  Future<XFile?> pickAudio();
}

/// Default system file picker implementation using `file_selector`.
class FileSelectorAudioPicker implements AudioFilePicker {
  const FileSelectorAudioPicker();

  @override
  Future<XFile?> pickAudio() => openFile(
    acceptedTypeGroups: const [
      XTypeGroup(
        label: 'Audio',
        extensions: ['m4a', 'mp3', 'wav', 'aac'],
        mimeTypes: [
          'audio/mp4',
          'audio/m4a',
          'audio/x-m4a',
          'audio/mpeg',
          'audio/mp3',
          'audio/wav',
          'audio/x-wav',
          'audio/aac',
          'audio/x-aac',
        ],
        uniformTypeIdentifiers: [
          'public.audio',
          'public.mp3',
          'public.mpeg-4-audio',
          'com.microsoft.waveform-audio',
        ],
      ),
    ],
    confirmButtonText: 'Import',
  );
}

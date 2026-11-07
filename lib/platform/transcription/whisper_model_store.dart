import 'dart:io';

import '../storage/verified_model_store.dart';
import 'transcription_exceptions.dart';

export '../storage/verified_model_store.dart'
    show ModelStorageException, VerifiedModelDescriptor, VerifiedModelStore;

/// Metadata for a verified Whisper GGML model.
class WhisperModelDescriptor extends VerifiedModelDescriptor {
  const WhisperModelDescriptor({
    required super.id,
    required super.name,
    required super.sizeBytes,
    required this.language,
    required super.sha256,
    required super.downloadUrl,
  }) : super(fileName: 'ggml-$id.bin', maxSizeBytes: 128 * 1024 * 1024);

  /// Supported language code ('en' for English-only, 'multilingual' for multi-language).
  final String language;

  /// Human-readable size string.
  String get sizeLabel {
    const mebibyte = 1024 * 1024;
    return '${(sizeBytes / mebibyte).toStringAsFixed(1)} MiB';
  }

  /// Package verified tiny English quantized model (~30.68 MiB).
  static const tinyEnQ5_1 = WhisperModelDescriptor(
    id: 'tiny.en-q5_1',
    name: 'Tiny English (quantized, ~31 MiB)',
    sizeBytes: 32166155,
    language: 'en',
    sha256: 'c77c5766f1cef09b6b7d47f21b546cbddd4157886b3b5d6d4f709e91e66c7c2b',
    downloadUrl: 'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.en-q5_1.bin',
  );

  /// Package verified tiny multilingual quantized model (~30.66 MiB).
  static const tinyQ5_1 = WhisperModelDescriptor(
    id: 'tiny-q5_1',
    name: 'Tiny Multilingual (quantized, ~31 MiB)',
    sizeBytes: 32152673,
    language: 'multilingual',
    sha256: '818710568da3ca15689e31a743197b520007872ff9576237bda97bd1b469c3d7',
    downloadUrl: 'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny-q5_1.bin',
  );

  /// Silero voice activity detection model (~0.84 MiB, MIT), installed with
  /// the speech model so Whisper skips long silences [P2-11, FR-TRN-10].
  /// Pinned to one Hugging Face revision of ggml-org/whisper-vad.
  static const sileroVad = WhisperModelDescriptor(
    id: 'silero-v6.2.0',
    name: 'Silero voice activity detection v6.2.0',
    sizeBytes: 885098,
    language: 'none',
    sha256: '2aa269b785eeb53a82983a20501ddf7c1d9c48e33ab63a41391ac6c9f7fb6987',
    downloadUrl: 'https://huggingface.co/ggml-org/whisper-vad/resolve/9ffd54a1e1ee413ddf265af9913beaf518d1639b/ggml-silero-v6.2.0.bin',
  );

  /// Default model for speech transcription.
  static const defaultModel = tinyEnQ5_1;

  /// Verified catalog of offline models.
  static const List<WhisperModelDescriptor> verifiedCatalog = [
    tinyEnQ5_1,
    tinyQ5_1,
  ];
}

/// App-managed storage and explicit lifecycle manager for Whisper GGML models.
///
/// Models are never downloaded automatically. Explicit user request triggers
/// free-space preflight, atomic streamed download to `.part`, checksum verification,
/// and safe cancellation/retry without deleting recordings or user transcripts.
class WhisperModelStore extends VerifiedModelStore {
  WhisperModelStore({
    required super.baseDirectory,
    super.freeSpaceProbe,
    super.httpClientFactory,
    super.safetyReserveBytes = 50 * 1024 * 1024,
  }) : super(exceptionFactory: WhisperStorageException.new);

  Directory get modelDirectory => baseDirectory;
}

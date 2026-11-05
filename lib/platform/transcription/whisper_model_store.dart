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

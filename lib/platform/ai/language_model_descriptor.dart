import '../storage/verified_model_store.dart';

/// Metadata for a verified on-device language model asset (Phase 3, FR-AI-01).
class LanguageModelDescriptor extends VerifiedModelDescriptor {
  const LanguageModelDescriptor({
    required super.id,
    required super.name,
    required super.sizeBytes,
    required super.sha256,
    required super.downloadUrl,
    required super.fileName,
    required this.licence,
    required this.deviceNotice,
    super.maxSizeBytes = 10 * 1024 * 1024 * 1024,
  });

  /// Open-source licence for the model weights (e.g. Apache 2.0).
  final String licence;

  /// Clear notice explaining on-device execution and data privacy.
  final String deviceNotice;

  /// Formatted size string for display (e.g. '2.65 GB').
  String get sizeLabel {
    const gigabyte = 1024 * 1024 * 1024;
    return '${(sizeBytes / gigabyte).toStringAsFixed(2)} GB';
  }

  /// Official pinned source for Gemma 4 E2B IT quantized (Q4_0).
  ///
  /// Pinned commit: 6938c58e698502037401a5f19f6905f2fb2f7dee
  /// Size: 2,841,481,184 bytes (~2.65 GB)
  /// SHA-256: 8e30dff3ac4c8434c49a7036fa15564bdbb6044e42bf04550bf1a096ad7e6a52
  static const gemma4E2B = LanguageModelDescriptor(
    id: 'gemma-4-E2B-it-Q4_0',
    name: 'Gemma 4 E2B, Fast',
    sizeBytes: 2841481184,
    sha256: '8e30dff3ac4c8434c49a7036fa15564bdbb6044e42bf04550bf1a096ad7e6a52',
    downloadUrl: 'https://huggingface.co/ggml-org/gemma-4-E2B-it-GGUF/resolve/6938c58e698502037401a5f19f6905f2fb2f7dee/gemma-4-E2B-it-Q4_0.gguf',
    fileName: 'gemma-4-E2B-it-Q4_0.gguf',
    licence: 'Apache 2.0',
    deviceNotice: 'Runs on this device. Nothing you record is sent anywhere.',
  );

  /// Default language model for summarisation and on-device AI.
  static const defaultModel = gemma4E2B;
}

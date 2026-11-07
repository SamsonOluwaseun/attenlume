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
    this.suitedTo = '',
    this.termsLinks = const [],
    super.maxSizeBytes = 10 * 1024 * 1024 * 1024,
  });

  /// Licence for the model weights (e.g. Apache 2.0).
  final String licence;

  /// Clear notice explaining on-device execution and data privacy.
  final String deviceNotice;

  /// Which devices it suits, shown beside the choice (e.g. '6 GB+ phones').
  final String suitedTo;

  /// Terms the user must be shown before downloading, as (label, url).
  /// Empty for plain open licences such as Apache 2.0 [P3-11].
  final List<(String, String)> termsLinks;

  /// Formatted size string for display (e.g. '2.65 GB' or '769 MB').
  String get sizeLabel {
    const megabyte = 1024 * 1024;
    const gigabyte = 1024 * megabyte;
    return sizeBytes >= gigabyte
        ? '${(sizeBytes / gigabyte).toStringAsFixed(2)} GB'
        : '${(sizeBytes / megabyte).round()} MB';
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
    suitedTo:
        'Best summaries. For phones with 6 GB of memory or more, and PCs.',
  );

  /// Smaller model for 4 GB phones [P3-11]. Owner chose it on 7 Nov 2026,
  /// knowing it uses the Gemma Terms of Use rather than Apache 2.0.
  ///
  /// Pinned commit: f9c28bcd85737ffc5aef028638d3341d49869c27
  /// Size: 806,058,240 bytes (~769 MB)
  /// SHA-256: 8ccc5cd1f1b3602548715ae25a66ed73fd5dc68a210412eea643eb20eb75a135
  static const gemma3_1B = LanguageModelDescriptor(
    id: 'gemma-3-1b-it-Q4_K_M',
    name: 'Gemma 3 1B, Small',
    sizeBytes: 806058240,
    sha256: '8ccc5cd1f1b3602548715ae25a66ed73fd5dc68a210412eea643eb20eb75a135',
    downloadUrl: 'https://huggingface.co/ggml-org/gemma-3-1b-it-GGUF/resolve/f9c28bcd85737ffc5aef028638d3341d49869c27/gemma-3-1b-it-Q4_K_M.gguf',
    fileName: 'gemma-3-1b-it-Q4_K_M.gguf',
    licence: 'Gemma Terms of Use',
    deviceNotice: 'Runs on this device. Nothing you record is sent anywhere.',
    suitedTo: 'Smaller and quicker, simpler summaries. For 4 GB phones.',
    termsLinks: [
      ('Gemma Terms of Use', 'https://ai.google.dev/gemma/terms'),
      (
        'Gemma Prohibited Use Policy',
        'https://ai.google.dev/gemma/prohibited_use_policy',
      ),
    ],
  );

  /// Default language model for summarisation and on-device AI.
  static const defaultModel = gemma4E2B;

  /// Every model the user can choose in Settings, largest first.
  static const catalogue = [gemma4E2B, gemma3_1B];

  /// The catalogue model with [id], or null for an unknown id.
  static LanguageModelDescriptor? byId(String? id) {
    for (final model in catalogue) {
      if (model.id == id) return model;
    }
    return null;
  }

  /// Devices reporting less than this have 4 GB or less (a 6 GB phone
  /// reports about 5.5 GiB), so the small model is recommended.
  static const smallModelBelowBytes = 4864 * 1024 * 1024;

  /// The model to recommend for a device with [totalMemoryBytes], or null
  /// when the memory is unknown.
  static LanguageModelDescriptor? recommendedFor(int? totalMemoryBytes) {
    if (totalMemoryBytes == null || totalMemoryBytes <= 0) return null;
    return totalMemoryBytes < smallModelBelowBytes ? gemma3_1B : gemma4E2B;
  }
}

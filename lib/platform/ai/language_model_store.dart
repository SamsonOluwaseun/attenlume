import 'dart:io';

import '../storage/verified_model_store.dart';

export '../storage/verified_model_store.dart'
    show ModelStorageException, VerifiedModelDescriptor, VerifiedModelStore;
export 'language_model_descriptor.dart';

/// App-managed storage and explicit lifecycle manager for on-device language models (P3-10, FR-AI-01).
///
/// Models are never downloaded automatically. Explicit user request triggers
/// free-space preflight (model size + 1 GB warning margin), atomic streamed
/// download to `.part`, checksum verification, and safe cancellation/retry
/// without deleting recordings or user transcripts.
class LanguageModelStore extends VerifiedModelStore {
  LanguageModelStore({
    required super.baseDirectory,
    super.freeSpaceProbe,
    super.httpClientFactory,
    super.safetyReserveBytes = 1024 * 1024 * 1024, // 1 GB warning margin
  });

  Directory get modelDirectory => baseDirectory;
}

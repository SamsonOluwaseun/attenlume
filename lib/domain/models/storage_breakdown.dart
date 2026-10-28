import 'enums.dart';

/// Categorised storage sizes in bytes (FR-STO-05) [P1-20].
class StorageKindSizes {
  const StorageKindSizes({
    this.audioBytes = 0,
    this.photoBytes = 0,
    this.thumbnailBytes = 0,
    this.transcriptBytes = 0,
    this.temporaryExportBytes = 0,
    this.modelBytes = 0,
    this.keptOriginalBytes = 0,
    this.derivedBytes = 0,
  });

  /// Audio recordings (deduplicated across segments).
  final int audioBytes;

  /// High-resolution / compressed photos.
  final int photoBytes;

  /// Small photo thumbnails in `thumbs/` (derived).
  final int thumbnailBytes;

  /// Transcripts in `transcripts/` or `transcript.md` (Phase 2).
  final int transcriptBytes;

  /// Staging or temporary export archives (FR-STO-05).
  final int temporaryExportBytes;

  /// Offline speech and AI models (Phase 2).
  final int modelBytes;

  /// Audio recordings kept after permanent trim in `audio/originals/` (ADR-037).
  final int keptOriginalBytes;

  /// Waveform summaries and other derived temporary files (ADR-034).
  final int derivedBytes;

  /// Total storage consumed across all kinds.
  int get totalBytes =>
      audioBytes +
      photoBytes +
      thumbnailBytes +
      transcriptBytes +
      temporaryExportBytes +
      modelBytes +
      keptOriginalBytes +
      derivedBytes;

  StorageKindSizes copyWith({
    int? audioBytes,
    int? photoBytes,
    int? thumbnailBytes,
    int? transcriptBytes,
    int? temporaryExportBytes,
    int? modelBytes,
    int? keptOriginalBytes,
    int? derivedBytes,
  }) {
    return StorageKindSizes(
      audioBytes: audioBytes ?? this.audioBytes,
      photoBytes: photoBytes ?? this.photoBytes,
      thumbnailBytes: thumbnailBytes ?? this.thumbnailBytes,
      transcriptBytes: transcriptBytes ?? this.transcriptBytes,
      temporaryExportBytes: temporaryExportBytes ?? this.temporaryExportBytes,
      modelBytes: modelBytes ?? this.modelBytes,
      keptOriginalBytes: keptOriginalBytes ?? this.keptOriginalBytes,
      derivedBytes: derivedBytes ?? this.derivedBytes,
    );
  }

  StorageKindSizes operator +(StorageKindSizes other) {
    return StorageKindSizes(
      audioBytes: audioBytes + other.audioBytes,
      photoBytes: photoBytes + other.photoBytes,
      thumbnailBytes: thumbnailBytes + other.thumbnailBytes,
      transcriptBytes: transcriptBytes + other.transcriptBytes,
      temporaryExportBytes: temporaryExportBytes + other.temporaryExportBytes,
      modelBytes: modelBytes + other.modelBytes,
      keptOriginalBytes: keptOriginalBytes + other.keptOriginalBytes,
      derivedBytes: derivedBytes + other.derivedBytes,
    );
  }

  static const zero = StorageKindSizes();
}

/// Export state of a conference or activity (FR-STO-05).
enum ExportStatus implements KeyedEnum {
  notExported('not_exported', 'Not exported'),
  exportedLocally('exported_locally', 'Exported locally'),
  uploaded('uploaded', 'Uploaded'),
  verified('verified', 'Verified');

  const ExportStatus(this.key, this.label);

  @override
  final String key;
  final String label;

  /// True if this item has reached verified integrity (checksum verified).
  bool get isVerified => this == ExportStatus.verified;
}

/// Storage breakdown for a single activity (FR-STO-05) [P1-20].
class ActivityStorageBreakdown {
  const ActivityStorageBreakdown({
    required this.activityId,
    required this.activityTitle,
    required this.activityTypeLabel,
    required this.exportStatus,
    required this.sizes,
    this.segmentCount = 0,
    this.photoCount = 0,
    this.keptOriginalsCount = 0,
  });

  final String activityId;
  final String activityTitle;
  final String activityTypeLabel;
  final ExportStatus exportStatus;
  final StorageKindSizes sizes;
  final int segmentCount;
  final int photoCount;
  final int keptOriginalsCount;

  int get totalBytes => sizes.totalBytes;
}

/// Storage breakdown for a conference, including its activities (FR-STO-05) [P1-20].
class ConferenceStorageBreakdown {
  const ConferenceStorageBreakdown({
    required this.conferenceId,
    required this.conferenceName,
    required this.isArchived,
    required this.exportStatus,
    required this.sizes,
    required this.activities,
  });

  final String conferenceId;
  final String conferenceName;
  final bool isArchived;
  final ExportStatus exportStatus;
  final StorageKindSizes sizes;
  final List<ActivityStorageBreakdown> activities;

  int get totalBytes => sizes.totalBytes;
}

/// Comprehensive app-wide storage breakdown (FR-STO-05) [P1-20].
class AppStorageBreakdown {
  const AppStorageBreakdown({
    required this.totalDeviceFreeBytes,
    required this.totalDeviceCapacityBytes,
    required this.appTotalBytes,
    required this.overallSizes,
    required this.conferences,
    required this.safeTemporaryBytes,
    required this.keptOriginalsTotalBytes,
    required this.keptOriginalsCount,
  });

  final int? totalDeviceFreeBytes;
  final int? totalDeviceCapacityBytes;
  final int appTotalBytes;
  final StorageKindSizes overallSizes;
  final List<ConferenceStorageBreakdown> conferences;
  final int safeTemporaryBytes;
  final int keptOriginalsTotalBytes;
  final int keptOriginalsCount;

  static const empty = AppStorageBreakdown(
    totalDeviceFreeBytes: null,
    totalDeviceCapacityBytes: null,
    appTotalBytes: 0,
    overallSizes: StorageKindSizes.zero,
    conferences: [],
    safeTemporaryBytes: 0,
    keptOriginalsTotalBytes: 0,
    keptOriginalsCount: 0,
  );
}

/// Result of clearing safe temporary files (FR-STO-06) [P1-20].
class SafeCleanupResult {
  const SafeCleanupResult({
    required this.filesDeleted,
    required this.bytesFreed,
  });

  final int filesDeleted;
  final int bytesFreed;
}

/// Preview of a "Delete local copies" action (FR-STO-06, FR-STO-07) [P1-20].
class DeleteLocalPreview {
  const DeleteLocalPreview({
    required this.conferenceId,
    required this.conferenceName,
    this.activityId,
    this.activityTitle,
    required this.keepLightweightIndex,
    required this.audioFilesCount,
    required this.audioBytes,
    required this.photoFilesCount,
    required this.photoBytes,
    required this.keptOriginalsCount,
    required this.keptOriginalsBytes,
    required this.derivedFilesCount,
    required this.derivedBytes,
    required this.sharedFilesPreservedCount,
    required this.totalFilesToDelete,
    required this.totalBytesToFree,
  });

  final String conferenceId;
  final String conferenceName;
  final String? activityId;
  final String? activityTitle;
  final bool keepLightweightIndex;
  final int audioFilesCount;
  final int audioBytes;
  final int photoFilesCount;
  final int photoBytes;
  final int keptOriginalsCount;
  final int keptOriginalsBytes;
  final int derivedFilesCount;
  final int derivedBytes;
  final int sharedFilesPreservedCount;
  final int totalFilesToDelete;
  final int totalBytesToFree;
}

/// Result of executing a "Delete local copies" action (FR-STO-06, FR-STO-07) [P1-20].
class DeleteLocalResult {
  const DeleteLocalResult({
    required this.filesDeleted,
    required this.bytesFreed,
    required this.sharedFilesPreserved,
    required this.keptIndex,
  });

  final int filesDeleted;
  final int bytesFreed;
  final int sharedFilesPreserved;
  final bool keptIndex;
}

/// Exceptions thrown during storage operations.
class StorageManagerException implements Exception {
  const StorageManagerException(this.message);

  /// Plain UK English message ready for display.
  final String message;

  @override
  String toString() => 'StorageManagerException: $message';
}

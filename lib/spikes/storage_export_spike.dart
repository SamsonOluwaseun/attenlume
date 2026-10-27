import 'dart:io';

import 'package:path/path.dart' as p;

import '../data/filesystem/folder_export.dart';
import '../data/filesystem/zip_export.dart';
import '../domain/services/storage_thresholds.dart';
import '../platform/storage/free_space_probe.dart';

/// Report from running [StorageExportSpike].
class StorageExportSpikeReport {
  const StorageExportSpikeReport({
    required this.deviceFreeBytes,
    required this.deviceTotalBytes,
    required this.thresholdAssessment,
    required this.testFileBytes,
    required this.folderExportMs,
    required this.folderExportPeakRssBytes,
    required this.folderExportDeltaRssBytes,
    required this.folderChecksumsValid,
    required this.zipExportMs,
    required this.zipExportPeakRssBytes,
    required this.zipExportDeltaRssBytes,
    required this.zipSizeBytes,
  });

  final int? deviceFreeBytes;
  final int? deviceTotalBytes;
  final StorageAssessment thresholdAssessment;
  final int testFileBytes;
  final int folderExportMs;
  final int folderExportPeakRssBytes;
  final int folderExportDeltaRssBytes;
  final bool folderChecksumsValid;
  final int zipExportMs;
  final int zipExportPeakRssBytes;
  final int zipExportDeltaRssBytes;
  final int zipSizeBytes;

  Map<String, Object?> toJson() => {
    'device_free_bytes': deviceFreeBytes,
    'device_total_bytes': deviceTotalBytes,
    'storage_level': thresholdAssessment.level.name,
    'minutes_left': thresholdAssessment.minutesLeft,
    'test_file_bytes': testFileBytes,
    'folder_export_ms': folderExportMs,
    'folder_peak_rss_mb': (folderExportPeakRssBytes / (1024 * 1024))
        .toStringAsFixed(1),
    'folder_delta_rss_mb': (folderExportDeltaRssBytes / (1024 * 1024))
        .toStringAsFixed(1),
    'folder_checksums_valid': folderChecksumsValid,
    'zip_export_ms': zipExportMs,
    'zip_peak_rss_mb': (zipExportPeakRssBytes / (1024 * 1024)).toStringAsFixed(
      1,
    ),
    'zip_delta_rss_mb': (zipExportDeltaRssBytes / (1024 * 1024))
        .toStringAsFixed(1),
    'zip_size_bytes': zipSizeBytes,
  };
}

/// Spike P0-11: low-storage simulation and streaming export with bounded
/// RAM [P0-11, FR-STO-01, FR-STO-02, FR-STO-04, FR-EXP-02, FR-EXP-04,
/// FR-EXP-05, FR-EXP-06, AT-STO-02, AT-STO-03].
///
/// Probes device free space, evaluates recording storage budget thresholds,
/// and streams a synthetic media file through both folder export and ZIP
/// export while tracking `ProcessInfo.currentRss` to verify bounded RAM.
class StorageExportSpike {
  StorageExportSpike({required this.workDir, FreeSpaceProbe? probe})
    : probe = probe ?? FreeSpaceProbe.forPlatform();

  final Directory workDir;
  final FreeSpaceProbe probe;

  Future<StorageExportSpikeReport> run({
    int syntheticFileBytes = 50 * 1024 * 1024,
  }) async {
    final space = await probe.query(workDir.path);
    final freeBytes = space?.availableBytes;
    final assessment = assessStorage(
      freeBytes: freeBytes ?? (2 * 1024 * 1024 * 1024),
      bytesPerSecond: 12000, // ~96 kbps on Windows
    );

    final sourceDir = Directory(p.join(workDir.path, 'source'));
    final destDir = Directory(p.join(workDir.path, 'dest'));
    await sourceDir.create(recursive: true);
    await destDir.create(recursive: true);

    final testFile = File(p.join(sourceDir.path, 'synthetic_audio.m4a'));
    final raf = await testFile.open(mode: FileMode.write);
    await raf.truncate(syntheticFileBytes);
    await raf.close();

    // Folder export run & RSS measurement
    final rssBeforeFolder = ProcessInfo.currentRss;
    var maxRssFolder = rssBeforeFolder;
    final swFolder = Stopwatch()..start();
    final folderResult = await exportFolder(
      source: sourceDir,
      destinationParent: destDir,
      folderName: 'folder_export',
      onFileDone: (_) {
        final current = ProcessInfo.currentRss;
        if (current > maxRssFolder) maxRssFolder = current;
      },
    );
    swFolder.stop();
    final folderChecksumFailures = await verifyChecksums(folderResult.folder);

    // ZIP export run & RSS measurement
    final rssBeforeZip = ProcessInfo.currentRss;
    var maxRssZip = rssBeforeZip;
    final swZip = Stopwatch()..start();
    final zipResult = await exportZip(
      source: sourceDir,
      destinationParent: destDir,
      zipName: 'zip_export',
      onFileDone: (_) {
        final current = ProcessInfo.currentRss;
        if (current > maxRssZip) maxRssZip = current;
      },
    );
    swZip.stop();

    return StorageExportSpikeReport(
      deviceFreeBytes: freeBytes,
      deviceTotalBytes: space?.totalBytes,
      thresholdAssessment: assessment,
      testFileBytes: syntheticFileBytes,
      folderExportMs: swFolder.elapsedMilliseconds,
      folderExportPeakRssBytes: maxRssFolder,
      folderExportDeltaRssBytes: maxRssFolder - rssBeforeFolder,
      folderChecksumsValid: folderChecksumFailures.isEmpty,
      zipExportMs: swZip.elapsedMilliseconds,
      zipExportPeakRssBytes: maxRssZip,
      zipExportDeltaRssBytes: maxRssZip - rssBeforeZip,
      zipSizeBytes: zipResult.zipFile.lengthSync(),
    );
  }
}

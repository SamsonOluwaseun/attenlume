import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../data/repositories/repository_providers.dart';
import '../../domain/models/storage_breakdown.dart';
import '../../domain/services/storage_manager_service.dart';
import '../capture/recording_providers.dart';
import '../export/export_providers.dart';
import '../playback_review/review_screen.dart'
    show permanentTrimServiceProvider;

/// The app cache folder, where exports stage (ADR-040). Tests override it.
final storageTempRootProvider = Provider<Future<Directory> Function()>(
  (ref) => getTemporaryDirectory,
);

/// [StorageManagerService] (FR-STO-05, FR-STO-06) [P1-20].
final storageManagerServiceProvider = Provider<StorageManagerService>((ref) {
  return StorageManagerService(
    conferences: ref.watch(conferenceRepositoryProvider),
    activities: ref.watch(activityRepositoryProvider),
    media: ref.watch(mediaAssetRepositoryProvider),
    exports: ref.watch(exportJobRepositoryProvider),
    mediaRoot: ref.watch(mediaRootProvider),
    tempRoot: ref.watch(storageTempRootProvider),
    freeSpaceProbe: ref.watch(freeSpaceProbeProvider),
    removeOriginals: ref.watch(permanentTrimServiceProvider).removeOriginals,
    exportRunning: () => ref.read(exportServiceProvider).isRunning,
  );
});

/// Current storage breakdown (FR-STO-05) [P1-20]. Invalidate to refresh.
final storageBreakdownProvider =
    FutureProvider.autoDispose<AppStorageBreakdown>(
      (ref) => ref.watch(storageManagerServiceProvider).analyse(),
    );

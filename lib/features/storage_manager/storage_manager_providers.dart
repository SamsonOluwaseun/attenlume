import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/repository_providers.dart';
import '../../domain/models/storage_breakdown.dart';
import '../../domain/services/storage_manager_service.dart';
import '../capture/recording_providers.dart';

/// Provider for [StorageManagerService] (FR-STO-05, FR-STO-06) [P1-20].
final storageManagerServiceProvider = Provider<StorageManagerService>((ref) {
  return StorageManagerService(
    conferences: ref.watch(conferenceRepositoryProvider),
    activities: ref.watch(activityRepositoryProvider),
    media: ref.watch(mediaAssetRepositoryProvider),
    exports: ref.watch(exportJobRepositoryProvider),
    mediaRoot: ref.watch(mediaRootProvider),
    freeSpaceProbe: ref.watch(freeSpaceProbeProvider),
  );
});

/// Current app storage breakdown (FR-STO-05) [P1-20]. Refreshed when invalidated.
final storageBreakdownProvider =
    FutureProvider.autoDispose<AppStorageBreakdown>((ref) async {
      return ref.watch(storageManagerServiceProvider).analyzeStorage();
    });

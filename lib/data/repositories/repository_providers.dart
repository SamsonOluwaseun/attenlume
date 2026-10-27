import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../local_database/database_provider.dart';
import 'activity_repository.dart';
import 'conference_repository.dart';
import 'cut_range_repository.dart';
import 'export_job_repository.dart';
import 'media_asset_repository.dart';
import 'settings_repository.dart';

// Repository providers [P0-09]. Tests override appDatabaseProvider.

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => SettingsRepository(ref.watch(appDatabaseProvider)),
);

final conferenceRepositoryProvider = Provider<ConferenceRepository>(
  (ref) => ConferenceRepository(ref.watch(appDatabaseProvider)),
);

final activityRepositoryProvider = Provider<ActivityRepository>(
  (ref) => ActivityRepository(ref.watch(appDatabaseProvider)),
);

final mediaAssetRepositoryProvider = Provider<MediaAssetRepository>(
  (ref) => MediaAssetRepository(ref.watch(appDatabaseProvider)),
);

final cutRangeRepositoryProvider = Provider<CutRangeRepository>(
  (ref) => CutRangeRepository(ref.watch(appDatabaseProvider)),
);

final exportJobRepositoryProvider = Provider<ExportJobRepository>(
  (ref) => ExportJobRepository(ref.watch(appDatabaseProvider)),
);

import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../data/filesystem/app_data_directory.dart';
import '../../data/repositories/repository_providers.dart';
import '../../domain/services/export_service.dart';
import '../../platform/share/export_sharer.dart';
import '../capture/recording_providers.dart';

/// Local export (FR-EXP-01 to 07, FR-EXP-10, ADR-040) [P1-21].
final exportServiceProvider = Provider<ExportService>(
  (ref) => ExportService(
    conferences: ref.watch(conferenceRepositoryProvider),
    activities: ref.watch(activityRepositoryProvider),
    media: ref.watch(mediaAssetRepositoryProvider),
    cuts: ref.watch(cutRangeRepositoryProvider),
    jobs: ref.watch(exportJobRepositoryProvider),
    mediaRoot: ref.watch(mediaRootProvider),
    tempRoot: getTemporaryDirectory,
    freeSpace: ref.watch(freeSpaceProbeProvider),
  ),
);

/// Where exports go (ADR-040).
abstract interface class ExportDestinations {
  /// The folder used when the user has not chosen one, or null when the
  /// user must choose (Windows).
  Future<String?> defaultFolder();

  /// Whether the user can pick a folder on this platform.
  bool get canChoose;

  /// Opens the system folder picker. Null when cancelled.
  Future<String?> choose();
}

/// Windows: the user picks a folder; nothing is assumed, because the
/// Documents folder is often synced to OneDrive (ADR-028). Android and
/// iOS: `<app documents>/exports/`.
class PlatformExportDestinations implements ExportDestinations {
  const PlatformExportDestinations();

  @override
  bool get canChoose => Platform.isWindows;

  @override
  Future<String?> defaultFolder() async {
    if (Platform.isWindows) return null;
    final dir = Directory(p.join((await appDataDirectory()).path, 'exports'));
    await dir.create(recursive: true);
    return dir.path;
  }

  @override
  Future<String?> choose() =>
      getDirectoryPath(confirmButtonText: 'Export here');
}

final exportDestinationsProvider = Provider<ExportDestinations>(
  (ref) => const PlatformExportDestinations(),
);

/// The system share sheet for exports on Android and iOS (ADR-042). Tests
/// override it with a fake.
final exportSharerProvider = Provider<ExportSharer>(
  (ref) => const SharePlusExportSharer(),
);

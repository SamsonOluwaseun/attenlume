import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import '../../domain/models/activity.dart';
import '../../domain/models/conference.dart';
import '../../domain/models/enums.dart';
import '../../domain/models/export_job.dart';
import '../../domain/models/media.dart';
import 'app_database.steps.dart';
import 'builtin_activity_types.dart';
import 'converters.dart';
import 'tables.dart';

export 'tables.dart';

part 'app_database.g.dart';

/// The on-device database (BUILD_GUIDE 9.4).
///
/// Schema history:
/// - v1 (P0-02): `app_settings`.
/// - v2 (P0-09): the Phase 1 tables of section 9.4 and built-in types.
@DriftDatabase(
  tables: [
    AppSettings,
    Conferences,
    Goals,
    ActivityTypes,
    Activities,
    RecordingSegments,
    Interruptions,
    Photos,
    Bookmarks,
    CutRanges,
    ExportJobs,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  /// Opens the on-device database file `attenlume.sqlite`.
  factory AppDatabase.open() => AppDatabase(driftDatabase(name: 'attenlume'));

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: stepByStep(
      from1To2: (m, schema) async {
        // Every 9.4 Phase 1 table and index is new in v2. Parents come
        // before children in the list, so foreign keys resolve.
        for (final entity in schema.entities) {
          if (entity == schema.appSettings) continue;
          await m.create(entity);
        }
      },
    ),
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
      await seedBuiltinActivityTypes();
    },
  );

  /// Inserts any missing built-in activity types (NFR-03). Existing rows
  /// are left alone, so this is safe on every open.
  Future<void> seedBuiltinActivityTypes() async {
    final now = DateTime.now().toUtc();
    await batch((b) {
      for (final (i, t) in builtinActivityTypes.indexed) {
        b.insert(
          activityTypes,
          ActivityTypesCompanion.insert(
            id: t.id,
            key: t.key,
            label: t.label,
            icon: t.icon,
            isBuiltin: true,
            sortOrder: i,
            createdAt: now,
            updatedAt: now,
          ),
          mode: InsertMode.insertOrIgnore,
        );
      }
    });
  }

  Future<String?> readSetting(String key) async {
    final row = await (select(
      appSettings,
    )..where((t) => t.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  Future<void> writeSetting(String key, String value) async {
    final now = DateTime.now().toUtc();
    await into(appSettings).insert(
      AppSettingsCompanion.insert(
        key: key,
        value: value,
        createdAt: now,
        updatedAt: now,
      ),
      onConflict: DoUpdate(
        (_) => AppSettingsCompanion(value: Value(value), updatedAt: Value(now)),
      ),
    );
  }
}

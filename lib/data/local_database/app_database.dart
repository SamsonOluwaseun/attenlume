import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'app_database.g.dart';

/// Key-value app settings (BUILD_GUIDE 9.4 `app_settings`).
///
/// The rest of the section 9.4 schema arrives in P0-09.
class AppSettings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}

@DriftDatabase(tables: [AppSettings])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  /// Opens the on-device database file `attenlume.sqlite`.
  factory AppDatabase.open() => AppDatabase(driftDatabase(name: 'attenlume'));

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

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

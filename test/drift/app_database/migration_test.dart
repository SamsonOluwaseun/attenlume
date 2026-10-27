import 'package:attenlume/data/local_database/app_database.dart';
import 'package:attenlume/data/local_database/builtin_activity_types.dart';
import 'package:drift/drift.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'generated/schema.dart';
import 'generated/schema_v1.dart' as v1;
import 'generated/schema_v2.dart' as v2;

// Schema dumps live in drift_schemas/. After bumping schemaVersion run:
//   dart run drift_dev make-migrations
// which writes the next dump, regenerates generated/ and the steps file.
// Then add a step to AppDatabase.migration and a data test here.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late SchemaVerifier verifier;

  setUpAll(() => verifier = SchemaVerifier(GeneratedHelper()));

  group('P0-09 schema migrations', () {
    const versions = GeneratedHelper.versions;
    test('P0-09 current schema matches the latest dump', () async {
      final schema = await verifier.schemaAt(versions.last);
      final db = AppDatabase(schema.newConnection());
      await verifier.migrateAndValidate(db, versions.last);
      await db.close();
    });
    for (final (i, fromVersion) in versions.indexed) {
      for (final toVersion in versions.skip(i + 1)) {
        test('P0-09 migrates v$fromVersion to v$toVersion', () async {
          final schema = await verifier.schemaAt(fromVersion);
          final db = AppDatabase(schema.newConnection());
          await verifier.migrateAndValidate(db, toVersion);
          await db.close();
        });
      }
    }

    test('P0-09 v1 to v2 keeps settings and seeds built-in types', () async {
      final at = DateTime.utc(2026, 10, 27, 9);
      final setting = v1.AppSettingsData(
        key: 'default_recording_profile',
        value: 'enhanced',
        createdAt: at.toIso8601String(),
        updatedAt: at.toIso8601String(),
      );

      await verifier.testWithDataIntegrity(
        oldVersion: 1,
        newVersion: 2,
        createOld: v1.DatabaseAtV1.new,
        createNew: v2.DatabaseAtV2.new,
        openTestedDatabase: AppDatabase.new,
        createItems: (batch, oldDb) => batch.insert(oldDb.appSettings, setting),
        validateItems: (newDb) async {
          final settings = await newDb.select(newDb.appSettings).get();
          expect(settings.single.value, 'enhanced');
          final types = await newDb.select(newDb.activityTypes).get();
          expect(
            types.map((t) => t.key).toSet(),
            builtinActivityTypes.map((t) => t.key).toSet(),
          );
        },
      );
    });
  });
}

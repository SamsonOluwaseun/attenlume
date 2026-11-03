import 'package:attenlume/data/local_database/app_database.dart';
import 'package:attenlume/data/local_database/builtin_activity_types.dart';
import 'package:drift/drift.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'generated/schema.dart';
import 'generated/schema_v1.dart' as v1;
import 'generated/schema_v2.dart' as v2;
import 'generated/schema_v3.dart' as v3;

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

    test('P2-07 v2 to v3 keeps conferences and activities and adds an empty '
        'planned_sessions table', () async {
      final at = DateTime.utc(2026, 11, 2, 21).toIso8601String();
      const conferenceId = 'aaaaaaaa-0000-4000-8000-000000000001';
      final conference = v2.ConferencesData(
        createdAt: at,
        updatedAt: at,
        id: conferenceId,
        name: 'Samlytics Conference 2026',
        timezone: 'Europe/London',
        requestedOutputs: '[]',
        defaultRecordingProfile: 'balanced',
      );
      final type = v2.ActivityTypesData(
        createdAt: at,
        updatedAt: at,
        id: builtinActivityTypes.first.id,
        key: builtinActivityTypes.first.key,
        label: builtinActivityTypes.first.label,
        icon: builtinActivityTypes.first.icon,
        isBuiltin: 1,
        sortOrder: 0,
      );
      final activity = v2.ActivitiesData(
        createdAt: at,
        updatedAt: at,
        id: 'aaaaaaaa-0000-4000-8000-000000000002',
        conferenceId: conferenceId,
        typeId: builtinActivityTypes.first.id,
        title: 'Data Mesh in Practice',
        speakerNames: '["Samlytics Data Services"]',
        tags: '[]',
        status: 'completed',
        recordingPermissionStatus: 'permitted',
        isPrivate: 0,
      );

      await verifier.testWithDataIntegrity(
        oldVersion: 2,
        newVersion: 3,
        createOld: v2.DatabaseAtV2.new,
        createNew: v3.DatabaseAtV3.new,
        openTestedDatabase: AppDatabase.new,
        createItems: (batch, oldDb) {
          batch.insert(oldDb.conferences, conference);
          batch.insert(oldDb.activityTypes, type);
          batch.insert(oldDb.activities, activity);
        },
        validateItems: (newDb) async {
          final conferences = await newDb.select(newDb.conferences).get();
          expect(conferences.single.name, 'Samlytics Conference 2026');
          final activities = await newDb.select(newDb.activities).get();
          expect(activities.single.title, 'Data Mesh in Practice');
          expect(await newDb.select(newDb.plannedSessions).get(), isEmpty);
        },
      );
    });
  });
}

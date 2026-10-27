import 'package:attenlume/data/local_database/app_database.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'generated/schema.dart';

// Schema dumps live in drift_schemas/. After bumping schemaVersion run:
//   dart run drift_dev make-migrations
//   dart run drift_dev schema generate drift_schemas/app_database/ test/data/local_database/generated/
// and add a migration test from the previous version here.
void main() {
  group('P0-02 schema migrations', () {
    late SchemaVerifier verifier;
    setUpAll(() => verifier = SchemaVerifier(GeneratedHelper()));

    test('P0-02 v1 schema matches the dumped drift_schemas', () async {
      final schema = await verifier.schemaAt(1);
      final migrated = AppDatabase(schema.newConnection());
      await verifier.migrateAndValidate(migrated, 1);
      await migrated.close();
    });
  });
}

import 'package:attenlume/data/local_database/app_database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('P0-02 app_settings writes, reads and overwrites a value', () async {
    expect(await db.readSetting('default_recording_profile'), isNull);
    await db.writeSetting('default_recording_profile', 'balanced');
    await db.writeSetting('default_recording_profile', 'enhanced');
    expect(await db.readSetting('default_recording_profile'), 'enhanced');
    expect(await db.select(db.appSettings).get(), hasLength(1));
  });

  test('P0-02 timestamps are stored as UTC ISO 8601 text', () async {
    await db.writeSetting('k', 'v');
    final raw = await db
        .customSelect(
          'SELECT created_at, typeof(created_at) AS t FROM app_settings',
        )
        .getSingle();
    expect(raw.read<String>('t'), 'text');
    final stored = raw.read<String>('created_at');
    expect(DateTime.parse(stored).isUtc, isTrue, reason: stored);
  });

  test('P0-02 foreign keys are enforced', () async {
    final row = await db.customSelect('PRAGMA foreign_keys').getSingle();
    expect(row.read<int>('foreign_keys'), 1);
  });
}

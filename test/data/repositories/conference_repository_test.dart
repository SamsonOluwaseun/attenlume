import 'package:attenlume/data/local_database/app_database.dart';
import 'package:attenlume/domain/models/enums.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';

import '../../fixtures/fixtures.dart';

void main() {
  late TestData t;

  setUp(() => t = TestData());
  tearDown(() => t.close());

  group('FR-CONF-01 and FR-CONF-02 create', () {
    test('FR-CONF-01 a name and timezone are enough', () async {
      final c = await t.conferences.create(
        name: '  Samlytics Conference 2026  ',
        timezone: 'Europe/London',
      );
      expect(c.name, 'Samlytics Conference 2026');
      expect(c.requestedOutputs, isEmpty);
      expect(c.startDate, isNull);
      expect(c.isArchived, isFalse);
    });

    test('FR-CONF-02 a blank name is rejected', () {
      expect(
        () => t.conferences.create(name: '  ', timezone: 'UTC'),
        throwsArgumentError,
      );
    });

    test('FR-CONF-02 calendar dates round-trip without shifting', () async {
      final c = await t.conferences.create(
        name: 'Summit',
        timezone: 'Pacific/Auckland',
        startDate: DateTime.utc(2026, 11, 4),
        endDate: DateTime.utc(2026, 11, 5),
      );
      expect(c.startDate, DateTime.utc(2026, 11, 4));
      final raw = await t.db
          .customSelect('SELECT start_date FROM conferences')
          .getSingle();
      expect(raw.read<String>('start_date'), '2026-11-04');
    });

    test('FR-CONF-03 and FR-CONF-05 role and outputs round-trip', () async {
      final sample = await SampleConference.build(t);
      final c = (await t.conferences.get(sample.conference.id))!;
      expect(c.roleType, RoleType.attendee);
      expect(c.roleText, 'Senior enterprise data architect');
      expect(c.requestedOutputs, [
        RequestedOutput.briefing,
        RequestedOutput.blog,
      ]);
    });
  });

  group('FR-QUAL-02 and FR-QUAL-03 conference default profile', () {
    test('FR-QUAL-02 copies the global default at creation', () async {
      expect(
        (await t.conference()).defaultRecordingProfile,
        RecordingProfile.balanced,
      );
      await t.settings.setGlobalDefaultRecordingProfile(
        RecordingProfile.enhanced,
      );
      expect(
        (await t.conference(name: 'Second')).defaultRecordingProfile,
        RecordingProfile.enhanced,
      );
    });

    test('FR-QUAL-02 changing the global default leaves conferences', () async {
      final c = await t.conference();
      await t.settings.setGlobalDefaultRecordingProfile(
        RecordingProfile.economy,
      );
      expect(
        (await t.conferences.get(c.id))!.defaultRecordingProfile,
        RecordingProfile.balanced,
      );
    });

    test('FR-QUAL-03 a new default affects new activities only', () async {
      final c = await t.conference();
      final before = await t.activity(c.id);
      await t.conferences.changeDefaultRecordingProfile(
        c.id,
        RecordingProfile.enhanced,
      );
      final after = await t.activity(c.id);
      expect(
        await t.activities.effectiveProfile(before.id),
        RecordingProfile.balanced,
      );
      expect(
        await t.activities.effectiveProfile(after.id),
        RecordingProfile.enhanced,
      );
    });

    test('FR-QUAL-03 confirmed bulk change moves unrecorded only', () async {
      final c = await t.conference();
      final recorded = await t.activity(c.id);
      await t.segment(
        recorded.id,
        start: t.clock.now,
        length: const Duration(minutes: 1),
      );
      final unrecorded = await t.activity(c.id);
      final overridden = await t.activities.create(
        conferenceId: c.id,
        typeId: builtinTypeId('session'),
        recordingProfileOverride: RecordingProfile.economy,
      );

      await t.conferences.changeDefaultRecordingProfile(
        c.id,
        RecordingProfile.enhanced,
        includeUnrecordedActivities: true,
      );

      expect(
        await t.activities.effectiveProfile(recorded.id),
        RecordingProfile.balanced,
      );
      expect(
        await t.activities.effectiveProfile(unrecorded.id),
        RecordingProfile.enhanced,
      );
      expect(
        await t.activities.effectiveProfile(overridden.id),
        RecordingProfile.economy,
      );
    });

    test('FR-QUAL-03 counts only unrecorded activities that inherit the '
        'default, for the bulk change prompt [P1-09]', () async {
      final c = await t.conference();
      expect(await t.conferences.countUnrecordedInheritingActivities(c.id), 0);
      final recorded = await t.activity(c.id);
      await t.segment(
        recorded.id,
        start: t.clock.now,
        length: const Duration(minutes: 1),
      );
      await t.activity(c.id);
      await t.activity(c.id);
      await t.activities.create(
        conferenceId: c.id,
        typeId: builtinTypeId('session'),
        recordingProfileOverride: RecordingProfile.economy,
      );
      expect(await t.conferences.countUnrecordedInheritingActivities(c.id), 2);
    });

    test('FR-QUAL-03 update refuses to change the profile directly', () async {
      final c = await t.conference();
      expect(
        () => t.conferences.update(
          c.id,
          const ConferencesCompanion(
            defaultRecordingProfile: Value(RecordingProfile.economy),
          ),
        ),
        throwsArgumentError,
      );
    });
  });

  group('FR-CONF-08 edit, archive and delete', () {
    test('FR-CONF-08 update stamps updated_at', () async {
      final c = await t.conference();
      t.clock.advance(const Duration(hours: 1));
      await t.conferences.update(
        c.id,
        const ConferencesCompanion(venue: Value('ExCeL London')),
      );
      final updated = (await t.conferences.get(c.id))!;
      expect(updated.venue, 'ExCeL London');
      expect(updated.updatedAt, t.clock.now);
      expect(updated.createdAt, c.createdAt);
    });

    test('NFR-02 archived conferences stay accessible', () async {
      final a = await t.conference(name: 'A');
      await t.conference(name: 'B');
      await t.conferences.archive(a.id);
      expect((await t.conferences.watchAll().first).map((c) => c.name), ['B']);
      expect(
        await t.conferences.watchAll(includeArchived: true).first,
        hasLength(2),
      );
      await t.conferences.unarchive(a.id);
      expect(await t.conferences.watchAll().first, hasLength(2));
    });

    test('FR-CONF-06 policy acknowledgement is recorded', () async {
      final c = await t.conference();
      await t.conferences.acknowledgePolicy(c.id);
      expect(
        (await t.conferences.get(c.id))!.policyAcknowledgedAt,
        t.clock.now,
      );
    });

    test('FR-CONF-08 deletion summary counts what will go', () async {
      final sample = await SampleConference.build(t);
      final summary = await t.conferences.deletionSummary(sample.conference.id);
      expect(summary.activities, 3);
      expect(summary.segments, 2);
      expect(summary.photos, 1);
      expect(summary.bookmarks, 1);
      expect(summary.photoBytes, 400000);
      // 17 minutes at 48 kbps, from the fixture's byte estimate.
      expect(summary.audioBytes, 17 * 60 * 48000 ~/ 8);
    });

    test('P0-09 deleting a conference cascades to every child row', () async {
      final sample = await SampleConference.build(t);
      final other = await t.conference(name: 'Other');
      await t.activity(other.id);
      await t.exports.create(
        conferenceId: sample.conference.id,
        scope: const {'kind': 'conference'},
        format: ExportFormat.zip,
        audioMode: ExportAudioMode.original,
      );

      await t.conferences.delete(sample.conference.id);

      Future<int> count(String table) async =>
          (await t.db
                  .customSelect('SELECT COUNT(*) AS n FROM $table')
                  .getSingle())
              .read<int>('n');
      expect(await count('conferences'), 1);
      expect(await count('activities'), 1);
      for (final table in [
        'goals',
        'recording_segments',
        'interruptions',
        'photos',
        'bookmarks',
        'cut_ranges',
        'export_jobs',
      ]) {
        expect(await count(table), 0, reason: table);
      }
      // Activity types are shared and stay.
      expect(await count('activity_types'), 9);
    });
  });

  group('FR-CONF-04 goals', () {
    test('FR-CONF-04 priority goals come first, then extras', () async {
      final c = await t.conference();
      await t.conferences.addGoal(c.id, 'Extra one');
      await t.conferences.addGoal(c.id, 'Second priority', priority: 2);
      await t.conferences.addGoal(c.id, 'First priority', priority: 1);
      await t.conferences.addGoal(c.id, 'Extra two');
      expect((await t.conferences.goalsFor(c.id)).map((g) => g.goalText), [
        'First priority',
        'Second priority',
        'Extra one',
        'Extra two',
      ]);
    });

    test('FR-CONF-04 priority outside 1 to 3 is rejected', () async {
      final c = await t.conference();
      expect(
        () => t.conferences.addGoal(c.id, 'x', priority: 4),
        throwsRangeError,
      );
      // The database enforces it too.
      expect(
        () => t.db.customStatement(
          "INSERT INTO goals VALUES ('g', '${c.id}', 'x', 0, 0, "
          "'2026-01-01T00:00:00.000Z', '2026-01-01T00:00:00.000Z')",
        ),
        throwsA(anything),
      );
    });

    test('FR-CONF-04 goals can be edited and removed', () async {
      final c = await t.conference();
      final g = await t.conferences.addGoal(c.id, 'Draft', priority: 1);
      await t.conferences.updateGoal(
        g.id,
        text: 'Final',
        priority: const Value(null),
      );
      final edited = (await t.conferences.goalsFor(c.id)).single;
      expect(edited.goalText, 'Final');
      expect(edited.priority, isNull);
      await t.conferences.deleteGoal(g.id);
      expect(await t.conferences.goalsFor(c.id), isEmpty);
    });
  });
}

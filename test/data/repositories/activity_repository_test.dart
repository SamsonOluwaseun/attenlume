import 'package:attenlume/data/local_database/app_database.dart';
import 'package:attenlume/data/local_database/builtin_activity_types.dart';
import 'package:attenlume/domain/models/enums.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';

import '../../fixtures/fixtures.dart';

void main() {
  late TestData t;

  setUp(() => t = TestData());
  tearDown(() => t.close());

  group('NFR-03 activity types', () {
    test('NFR-03 every built-in type is seeded once, in order', () async {
      final types = await t.activities.types();
      expect(types.map((x) => x.key), [
        'session',
        'keynote',
        'panel',
        'breakout',
        'workshop',
        'exhibit',
        'business_conversation',
        'networking',
        'personal_reflection',
      ]);
      expect(types.every((x) => x.isBuiltin), isTrue);
      // Seeding again on reopen adds nothing.
      await t.db.seedBuiltinActivityTypes();
      expect(await t.activities.types(), hasLength(9));
    });

    test('FR-ACT-02 quick-start labels exist', () async {
      final labels = (await t.activities.types()).map((x) => x.label);
      expect(
        labels,
        containsAll(['Session', 'Conversation', 'Exhibit', 'Reflection']),
      );
    });

    test('P0-09 built-in IDs are valid UUID v4', () {
      final v4 = RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-'
        r'[0-9a-f]{12}$',
      );
      for (final type in builtinActivityTypes) {
        expect(type.id, matches(v4));
      }
    });

    test('FR-ACT-06 custom types get unique keys', () async {
      final a = await t.activities.createCustomType('Poster session');
      final b = await t.activities.createCustomType('Poster session!');
      expect(a.key, 'custom_poster_session');
      expect(b.key, 'custom_poster_session_2');
      expect(a.isBuiltin, isFalse);
      expect((await t.activities.types()).last.key, b.key);
    });

    test('FR-ACT-06 a custom type in use cannot be deleted', () async {
      final c = await t.conference();
      final type = await t.activities.createCustomType('Lab tour');
      await t.activities.create(conferenceId: c.id, typeId: type.id);
      expect(() => t.activities.deleteCustomType(type.id), throwsStateError);
      expect(
        () => t.activities.deleteCustomType(builtinTypeId('session')),
        throwsStateError,
      );
      final unused = await t.activities.createCustomType('Unused');
      await t.activities.deleteCustomType(unused.id);
      expect(await t.activities.typeByKey(unused.key), isNull);
    });
  });

  group('FR-ACT-05 default titles', () {
    test('FR-ACT-05 numbers each type separately per conference', () async {
      final c = await t.conference();
      final other = await t.conference(name: 'Other');
      t.clock.set(DateTime.utc(2026, 11, 4, 14, 5)); // 14:05 GMT
      await t.activity(c.id);
      await t.activity(c.id, typeKey: 'exhibit');
      await t.activity(other.id);
      final third = await t.activity(c.id);
      final second = await t.activity(c.id, typeKey: 'exhibit');
      expect(third.title, 'Session 2, 14:05');
      expect(second.title, 'Exhibit 2, 14:05');
    });

    test('FR-ACT-05 counts named activities of the type too', () async {
      final c = await t.conference();
      t.clock.set(DateTime.utc(2026, 11, 4, 9));
      await t.activity(c.id, title: 'Opening');
      await t.activity(c.id, title: 'Data Mesh');
      expect((await t.activity(c.id)).title, 'Session 3, 09:00');
    });

    test('FR-ACT-05 uses the conference timezone', () async {
      final c = await t.conference(timezone: 'Asia/Tokyo');
      t.clock.set(DateTime.utc(2026, 11, 4, 5, 5)); // 14:05 JST
      expect((await t.activity(c.id)).title, 'Session 1, 14:05');
    });

    test('FR-ACT-05 a blank title gets the default', () async {
      final c = await t.conference();
      t.clock.set(DateTime.utc(2026, 11, 4, 10, 30));
      expect(
        (await t.activity(
          c.id,
          typeKey: 'business_conversation',
          title: ' ',
        )).title,
        'Conversation 1, 10:30',
      );
    });

    test('FR-ACT-05 rename any time, but not to blank', () async {
      final c = await t.conference();
      final a = await t.activity(c.id);
      await t.activities.rename(a.id, ' Data Mesh Keynote ');
      expect((await t.activities.get(a.id))!.title, 'Data Mesh Keynote');
      expect(() => t.activities.rename(a.id, ''), throwsArgumentError);
    });
  });

  group('FR-ACT-04 activity fields', () {
    test('FR-ACT-04 fields round-trip', () async {
      final c = await t.conference();
      final planned = DateTime.utc(2026, 11, 4, 11);
      final a = await t.activities.create(
        conferenceId: c.id,
        typeId: builtinTypeId('panel'),
        title: 'AI in public health',
        plannedStart: planned,
        speakerNames: ['Dr Ada Example', 'Sam Sample'],
        organisation: 'Samlytics Data Services',
        room: 'Hall B',
        tags: ['ai', 'health'],
        recordingPermissionStatus: RecordingPermissionStatus.permitted,
        recordingProfileOverride: RecordingProfile.enhanced,
      );
      await t.activities.update(
        a.id,
        const ActivitiesCompanion(
          notesMd: Value('# Notes'),
          contactName: Value('Sam'),
          contactDetails: Value('sam@example.invalid'),
          followUpText: Value('Send slides'),
        ),
      );
      final read = (await t.activities.get(a.id))!;
      expect(read.speakerNames, ['Dr Ada Example', 'Sam Sample']);
      expect(read.tags, ['ai', 'health']);
      expect(read.plannedStart, planned);
      expect(read.plannedStart!.isUtc, isTrue);
      expect(read.status, ActivityStatus.draft);
      expect(
        read.recordingPermissionStatus,
        RecordingPermissionStatus.permitted,
      );
      expect(read.recordingProfileOverride, RecordingProfile.enhanced);
      expect(read.notesMd, '# Notes');
      expect(read.contactName, 'Sam');
      expect(read.followUpText, 'Send slides');
      expect(read.isPrivate, isFalse);
    });

    test('FR-EXP-10 reflections are private by default', () async {
      final c = await t.conference();
      final r = await t.activity(c.id, typeKey: 'personal_reflection');
      final s = await t.activity(c.id);
      expect(r.isPrivate, isTrue);
      expect(s.isPrivate, isFalse);
      final shared = await t.activities.create(
        conferenceId: c.id,
        typeId: builtinTypeId('personal_reflection'),
        isPrivate: false,
      );
      expect(shared.isPrivate, isFalse);
    });

    test('FR-QUAL-02 effective profile honours the override', () async {
      final c = await t.conference();
      final inherit = await t.activity(c.id);
      final override = await t.activities.create(
        conferenceId: c.id,
        typeId: builtinTypeId('keynote'),
        recordingProfileOverride: RecordingProfile.enhanced,
      );
      expect(
        await t.activities.effectiveProfile(inherit.id),
        RecordingProfile.balanced,
      );
      expect(
        await t.activities.effectiveProfile(override.id),
        RecordingProfile.enhanced,
      );
    });

    test('FR-ACT-03 activities list chronologically', () async {
      final c = await t.conference();
      t.clock.set(DateTime.utc(2026, 11, 4, 8));
      final late = await t.activities.create(
        conferenceId: c.id,
        typeId: builtinTypeId('session'),
        title: 'Late',
        plannedStart: DateTime.utc(2026, 11, 4, 16),
      );
      final early = await t.activities.create(
        conferenceId: c.id,
        typeId: builtinTypeId('session'),
        title: 'Early',
        plannedStart: DateTime.utc(2026, 11, 4, 9),
      );
      t.clock.set(DateTime.utc(2026, 11, 4, 12));
      final adHoc = await t.activity(c.id, title: 'Ad hoc');
      expect(late.id, isNot(early.id));
      expect(adHoc.title, 'Ad hoc');
      expect((await t.activities.listForConference(c.id)).map((a) => a.title), [
        'Early',
        'Ad hoc',
        'Late',
      ]);
    });

    test('P0-09 deleting an activity cascades to its media rows', () async {
      final sample = await SampleConference.build(t);
      await t.activities.delete(sample.keynote.id);
      expect(await t.media.segmentsFor(sample.keynote.id), isEmpty);
      expect(await t.media.photosFor(sample.keynote.id), isEmpty);
      expect(await t.media.bookmarksFor(sample.keynote.id), isEmpty);
      expect(await t.media.interruptionsFor(sample.keynote.id), isEmpty);
      expect(await t.cuts.activeFor(sample.keynote.id), isEmpty);
      expect(
        await t.activities.listForConference(sample.conference.id),
        hasLength(2),
      );
    });
  });
}

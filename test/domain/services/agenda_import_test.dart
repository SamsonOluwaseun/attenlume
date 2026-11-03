import 'dart:convert';

import 'package:attenlume/domain/models/planned_session.dart';
import 'package:attenlume/domain/services/agenda_import.dart';
import 'package:attenlume/domain/services/agenda_parser.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fixtures/fixtures.dart';

/// P2-07 agenda preview counts, duplicates, near-now order and type
/// matching (ADR-082).
void main() {
  late TestData t;

  setUp(() => t = TestData());
  tearDown(() => t.close());

  PlannedSession session(
    String title,
    DateTime start, {
    DateTime? end,
    bool allDay = false,
    String? uid,
  }) => PlannedSession(
    id: title,
    conferenceId: 'c',
    title: title,
    speakerNames: const [],
    startUtc: start,
    endUtc: end,
    allDay: allDay,
    source: AgendaSource.csv,
    sourceUid: uid,
    createdAt: start,
    updatedAt: start,
  );

  group('P2-07 preview', () {
    test('P2-07 preview counts found, new, duplicates and skipped rows', () {
      final result = parseAgendaFile(
        fileName: 'agenda.csv',
        bytes: utf8.encode(
          'title,start\n'
          'Data Mesh in Practice,2026-11-04 09:30\n'
          'data mesh in practice!,2026-11-04 09:30\n'
          'Opening keynote,2026-11-04 09:00\n'
          'Lunch,\n'
          'Samlytics Data Services panel,2026-11-04 14:00\n',
        ),
        timezone: 'Europe/London',
      );
      final existing = [
        session('Data Mesh in Practice', DateTime.utc(2026, 11, 4, 9, 30)),
        // Same title, different time: not a duplicate.
        session('Opening keynote', DateTime.utc(2026, 11, 4, 10)),
      ];
      final preview = buildAgendaPreview(
        fileName: 'agenda.csv',
        result: result,
        existing: existing,
      );
      expect(preview.found, 3);
      expect(preview.toSave.map((e) => e.title), [
        'Opening keynote',
        'Samlytics Data Services panel',
      ]);
      expect(preview.duplicates.single.existing.title, 'Data Mesh in Practice');
      expect(preview.skipped.map((s) => s.reason), [
        'Same session as line 2.',
        'No start time.',
      ]);
    });

    test('P2-07 the same ICS UID is a duplicate even when the time moved', () {
      final entry = AgendaEntry(
        line: 4,
        title: 'Moved talk',
        startUtc: DateTime.utc(2026, 11, 4, 15),
        uid: 'talk-7@samlytics.example',
      );
      final existing = session(
        'Talk',
        DateTime.utc(2026, 11, 4, 11),
        uid: 'talk-7@samlytics.example',
      );
      expect(isSamePlannedSession(entry, existing), isTrue);
    });

    test('P2-07 importing the same file twice saves nothing new', () async {
      final conf = await t.conference();
      final bytes = utf8.encode(
        'BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nUID:a@samlytics.example\r\n'
        'SUMMARY:Keynote\r\nDTSTART:20261104T090000Z\r\nEND:VEVENT\r\n'
        'BEGIN:VEVENT\r\nUID:b@samlytics.example\r\nSUMMARY:Panel\r\n'
        'DTSTART:20261104T100000Z\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n',
      );
      AgendaParseResult parse() => parseAgendaFile(
        fileName: 'agenda.ics',
        bytes: bytes,
        timezone: conf.timezone,
      );
      final first = buildAgendaPreview(
        fileName: 'agenda.ics',
        result: parse(),
        existing: await t.plannedSessions.listFor(conf.id),
      );
      expect(first.toSave, hasLength(2));
      await t.plannedSessions.addAll(
        conf.id,
        first.toSave,
        source: AgendaSource.ics,
      );
      final second = buildAgendaPreview(
        fileName: 'agenda.ics',
        result: parse(),
        existing: await t.plannedSessions.listFor(conf.id),
      );
      expect(second.toSave, isEmpty);
      expect(second.duplicates, hasLength(2));
    });
  });

  group('P2-07 near now first', () {
    final now = DateTime.utc(2026, 11, 4, 10, 10);

    test('P2-07 sessions on now come first, then by distance from now, '
        'all-day sessions last', () {
      final sessions = [
        session('Tomorrow', DateTime.utc(2026, 11, 5, 9)),
        session('Whole day', DateTime.utc(2026, 11, 4), allDay: true),
        session('Early', DateTime.utc(2026, 11, 4, 8)),
        session(
          'On now',
          DateTime.utc(2026, 11, 4, 9, 30),
          end: DateTime.utc(2026, 11, 4, 10, 30),
        ),
        session('Next', DateTime.utc(2026, 11, 4, 10, 30)),
        session(
          'Just ended',
          DateTime.utc(2026, 11, 4, 9),
          end: DateTime.utc(2026, 11, 4, 10),
        ),
      ];
      expect(orderByNearNow(sessions, now).map((s) => s.title), [
        'On now',
        'Next',
        'Just ended',
        'Early',
        'Tomorrow',
        'Whole day',
      ]);
    });

    test('P2-07 a session without an end counts as on for 45 minutes', () {
      final s = session('Open end', DateTime.utc(2026, 11, 4, 9, 30));
      expect(isPlannedSessionOnNow(s, now), isTrue);
      expect(
        isPlannedSessionOnNow(s, DateTime.utc(2026, 11, 4, 10, 15)),
        isFalse,
      );
    });
  });

  group('P2-07 type matching', () {
    test('P2-07 matches labels, keys and common words, else Session', () async {
      final types = await t.activities.types();
      String key(String? text) => matchActivityType(types, text).key;
      expect(key('Keynote'), 'keynote');
      expect(key('  WORKSHOP '), 'workshop');
      expect(key('business_conversation'), 'business_conversation');
      expect(key('Talk'), 'session');
      expect(key('Plenary'), 'keynote');
      expect(key('Panel discussion'), 'panel');
      expect(key('Hands-on lab'), 'workshop');
      expect(key('Evening reception'), 'networking');
      expect(key('Coffee'), 'session');
      expect(key(null), 'session');
    });

    test('P2-07 a custom type matches by its label', () async {
      final custom = await t.activities.createCustomType('Poster session');
      final types = await t.activities.types();
      expect(matchActivityType(types, 'poster session').id, custom.id);
    });
  });
}

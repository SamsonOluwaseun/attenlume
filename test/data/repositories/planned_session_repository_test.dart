import 'package:attenlume/domain/models/planned_session.dart';
import 'package:attenlume/domain/services/agenda_parser.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fixtures/fixtures.dart';

/// P2-07 planned session storage (ADR-082).
void main() {
  late TestData t;

  setUp(() => t = TestData());
  tearDown(() => t.close());

  AgendaEntry entry(String title, DateTime start, {String? uid}) => AgendaEntry(
    line: 2,
    title: title,
    speakerNames: const ['Samlytics Data Services'],
    room: 'Hall A',
    typeText: 'Keynote',
    description: 'About data',
    startUtc: start,
    endUtc: start.add(const Duration(minutes: 45)),
    uid: uid,
  );

  test('P2-07 saves an agenda per conference, in time order', () async {
    final conf = await t.conference();
    final other = await t.conference(name: 'Samlytics Conference 2026 (2)');
    final saved = await t.plannedSessions.addAll(conf.id, [
      entry('Second', DateTime.utc(2026, 11, 4, 11)),
      entry('First', DateTime.utc(2026, 11, 4, 9), uid: 'uid-1'),
    ], source: AgendaSource.ics);
    expect(saved, 2);
    await t.plannedSessions.addAll(other.id, [
      entry('Elsewhere', DateTime.utc(2026, 11, 4, 9)),
    ], source: AgendaSource.csv);

    final list = await t.plannedSessions.listFor(conf.id);
    expect(list.map((p) => p.title), ['First', 'Second']);
    final first = list.first;
    expect(first.conferenceId, conf.id);
    expect(first.speakerNames, ['Samlytics Data Services']);
    expect(first.room, 'Hall A');
    expect(first.typeText, 'Keynote');
    expect(first.description, 'About data');
    expect(first.startUtc, DateTime.utc(2026, 11, 4, 9));
    expect(first.startUtc.isUtc, isTrue);
    expect(first.endUtc, DateTime.utc(2026, 11, 4, 9, 45));
    expect(first.allDay, isFalse);
    expect(first.source, AgendaSource.ics);
    expect(first.sourceUid, 'uid-1');
    expect(await t.plannedSessions.countFor(conf.id), 2);
  });

  test('P2-07 clearing the agenda leaves activities alone; deleting the '
      'conference removes its agenda', () async {
    final conf = await t.conference();
    await t.plannedSessions.addAll(conf.id, [
      entry('Keynote', DateTime.utc(2026, 11, 4, 9)),
    ], source: AgendaSource.csv);
    final activity = await t.activity(conf.id, title: 'Keynote');

    expect(await t.plannedSessions.deleteAllFor(conf.id), 1);
    expect(await t.plannedSessions.listFor(conf.id), isEmpty);
    expect(await t.activities.get(activity.id), isNotNull);

    await t.plannedSessions.addAll(conf.id, [
      entry('Keynote', DateTime.utc(2026, 11, 4, 9)),
    ], source: AgendaSource.csv);
    await t.conferences.delete(conf.id);
    expect(await t.plannedSessions.countFor(conf.id), 0);
  });

  test('P2-07 deletes one planned session', () async {
    final conf = await t.conference();
    await t.plannedSessions.addAll(conf.id, [
      entry('A', DateTime.utc(2026, 11, 4, 9)),
      entry('B', DateTime.utc(2026, 11, 4, 10)),
    ], source: AgendaSource.csv);
    final a = (await t.plannedSessions.listFor(conf.id)).first;
    await t.plannedSessions.delete(a.id);
    expect((await t.plannedSessions.listFor(conf.id)).map((p) => p.title), [
      'B',
    ]);
  });
}

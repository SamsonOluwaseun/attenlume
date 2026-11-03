import 'dart:convert';
import 'dart:io';

import 'package:attenlume/data/filesystem/export_writer.dart';
import 'package:attenlume/domain/models/planned_session.dart';
import 'package:attenlume/domain/services/agenda_parser.dart';
import 'package:attenlume/domain/services/export_package.dart';
import 'package:attenlume/domain/services/export_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../fixtures/fake_free_space_probe.dart';
import '../fixtures/fixtures.dart';

Future<ExportWriteResult> _inlineWriter(
  ExportWritePlan plan, {
  void Function(ExportWriteProgress progress)? onProgress,
  Future<void>? cancel,
}) => writeExport(plan, onProgress: onProgress, isCancelled: () => false);

/// P2-07 the imported agenda in `conference.json` (ADR-082), next to the
/// goals, only when there is one.
void main() {
  late TestData t;
  late Directory temp;

  setUp(() async {
    t = TestData();
    temp = await Directory.systemTemp.createTemp('agenda_export_test');
  });

  tearDown(() async {
    await t.close();
    await temp.delete(recursive: true);
  });

  ExportService service({bool withAgenda = true}) => ExportService(
    conferences: t.conferences,
    activities: t.activities,
    media: t.media,
    cuts: t.cuts,
    jobs: t.exports,
    mediaRoot: () async => Directory(p.join(temp.path, 'media')),
    tempRoot: () async => Directory(p.join(temp.path, 'cache')),
    freeSpace: FakeFreeSpaceProbe(64 << 30),
    reserveBytes: 0,
    writer: _inlineWriter,
    clock: t.clock.call,
    plannedSessions: withAgenda ? t.plannedSessions : null,
  );

  Future<Map<String, Object?>> manifest(
    String conferenceId, {
    bool withAgenda = true,
  }) async {
    final dest = Directory(p.join(temp.path, 'dest${withAgenda ? 1 : 0}'))
      ..createSync();
    final out = await service(withAgenda: withAgenda).run(
      ExportRequest(conferenceId: conferenceId),
      destinationParent: dest.path,
    );
    final file = File(p.join(out.outputPath, manifestFileName));
    return jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
  }

  test('P2-07 conference.json lists the planned sessions with UTC and '
      'conference-local times', () async {
    final c = await t.conference(timezone: 'Europe/Berlin');
    await t.activities.create(
      conferenceId: c.id,
      typeId: builtinTypeId('session'),
      title: 'Data Mesh in Practice',
      notesMd: 'Notes.',
    );
    await t.plannedSessions.addAll(c.id, [
      AgendaEntry(
        line: 2,
        title: 'Data Mesh in Practice',
        speakerNames: const ['Samlytics Data Services'],
        room: 'Hall A',
        typeText: 'Talk',
        startUtc: DateTime.utc(2026, 11, 4, 9),
        endUtc: DateTime.utc(2026, 11, 4, 9, 45),
      ),
      AgendaEntry(
        line: 3,
        title: 'Exhibition',
        startUtc: DateTime.utc(2026, 11, 4, 23),
        allDay: true,
      ),
    ], source: AgendaSource.csv);

    final json = await manifest(c.id);
    final planned = json['planned_sessions']! as List;
    expect(planned, hasLength(2));
    expect(planned.first, {
      'title': 'Data Mesh in Practice',
      'speakers': ['Samlytics Data Services'],
      'room': 'Hall A',
      'type': 'Talk',
      'description': null,
      'all_day': false,
      'start_utc': '2026-11-04T09:00:00.000Z',
      'start_local': startsWith('2026-11-04T10:00:00'),
      'end_utc': '2026-11-04T09:45:00.000Z',
      'end_local': startsWith('2026-11-04T10:45:00'),
    });
    expect((planned.last as Map)['all_day'], isTrue);
    expect((planned.last as Map)['end_utc'], isNull);
  });

  test('P2-07 conference.json has no planned_sessions key without an '
      'agenda, so earlier exports are unchanged', () async {
    final c = await t.conference();
    await t.activities.create(
      conferenceId: c.id,
      typeId: builtinTypeId('session'),
      title: 'Data Mesh in Practice',
      notesMd: 'Notes.',
    );
    expect((await manifest(c.id)).containsKey('planned_sessions'), isFalse);
    await t.plannedSessions.addAll(c.id, [
      AgendaEntry(
        line: 2,
        title: 'Talk',
        startUtc: DateTime.utc(2026, 11, 4, 9),
      ),
    ], source: AgendaSource.csv);
    expect(
      (await manifest(c.id, withAgenda: false)).containsKey('planned_sessions'),
      isFalse,
    );
  });
}

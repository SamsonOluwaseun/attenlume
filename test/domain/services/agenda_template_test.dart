import 'dart:convert';

import 'package:attenlume/domain/models/planned_session.dart';
import 'package:attenlume/domain/services/agenda_parser.dart';
import 'package:attenlume/domain/services/agenda_template.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('P2-07a CSV agenda template', () {
    test('FR-ACT-10 the header names every template column, in order', () {
      final header = agendaCsvTemplate().split('\r\n').first;
      expect(header, agendaTemplateColumns.join(','));
      expect(header, 'title,speaker,room,date,start,end,type,description');
    });

    test('FR-ACT-10 the template imports cleanly, every column read', () {
      final result = parseAgendaFile(
        fileName: agendaTemplateFileName,
        bytes: agendaCsvTemplateBytes(),
        timezone: 'Europe/London',
      );
      expect(result.format, AgendaSource.csv);
      expect(result.skipped, isEmpty);
      expect(result.warnings, isEmpty);
      expect(result.entries, hasLength(3));

      final keynote = result.entries.first;
      expect(keynote.title, 'Opening keynote');
      expect(keynote.speakerNames, ['Samlytics Data Services']);
      expect(keynote.room, 'Main stage');
      expect(keynote.typeText, 'Keynote');
      expect(keynote.description, 'Welcome and the plan for the day');
      // November in London is GMT, so 09:00 local is 09:00 UTC.
      expect(keynote.startUtc, DateTime.utc(2026, 11, 4, 9));
      expect(keynote.endUtc, DateTime.utc(2026, 11, 4, 9, 45));

      final panel = result.entries[1];
      expect(panel.title, 'Panel: data in practice');
      expect(panel.speakerNames, ['First Speaker', 'Second Speaker']);
      expect(result.entries[2].description, isNull);
    });

    test('FR-ACT-10 the file is UTF-8 with a byte order mark for Excel', () {
      final bytes = agendaCsvTemplateBytes();
      expect(bytes.take(3), [0xEF, 0xBB, 0xBF]);
      expect(utf8.decode(bytes.skip(3).toList()), agendaCsvTemplate());
      expect(agendaCsvTemplate(), endsWith('\r\n'));
    });
  });
}

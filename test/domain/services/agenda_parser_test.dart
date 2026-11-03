import 'dart:convert';

import 'package:attenlume/domain/models/planned_session.dart';
import 'package:attenlume/domain/services/agenda_parser.dart';
import 'package:flutter_test/flutter_test.dart';

/// P2-07 agenda import parsing (ADR-082): CSV and ICS, time zones, all-day
/// events and rows that cannot be read. Test data: Samlytics Conference
/// 2026 by Samlytics Data Services.
void main() {
  AgendaParseResult csv(
    String text, {
    String timezone = 'Europe/London',
    DateTime? defaultDate,
  }) => parseAgendaFile(
    fileName: 'agenda.csv',
    bytes: utf8.encode(text),
    timezone: timezone,
    defaultDate: defaultDate,
  );

  AgendaParseResult ics(String body, {String timezone = 'Europe/London'}) =>
      parseAgendaFile(
        fileName: 'agenda.ics',
        bytes: utf8.encode(
          'BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//Samlytics Data '
          'Services//Agenda//EN\r\n$body\r\nEND:VCALENDAR\r\n',
        ),
        timezone: timezone,
      );

  group('P2-07 CSV agenda', () {
    test('P2-07 reads title, speaker, room, start, end and type', () {
      final r = csv(
        'title,speaker,room,start,end,type\n'
        'Data Mesh in Practice,Samlytics Data Services,Hall A,'
        '2026-11-04 09:30,2026-11-04 10:15,Keynote\n',
      );
      expect(r.format, AgendaSource.csv);
      expect(r.skipped, isEmpty);
      final e = r.entries.single;
      expect(e.title, 'Data Mesh in Practice');
      expect(e.speakerNames, ['Samlytics Data Services']);
      expect(e.room, 'Hall A');
      expect(e.typeText, 'Keynote');
      // London is on GMT in November.
      expect(e.startUtc, DateTime.utc(2026, 11, 4, 9, 30));
      expect(e.endUtc, DateTime.utc(2026, 11, 4, 10, 15));
      expect(e.allDay, isFalse);
      expect(e.line, 2);
    });

    test('P2-07 tolerates header variants, case and spacing', () {
      final r = csv(
        'Session Title ; Presenter(s) ; Location ; Date ; Start Time ; '
        'End Time ; Session Type\n'
        'Opening keynote;Samlytics Data Services;Main stage;04/11/2026;'
        '9:00 am;9.45;Plenary\n',
      );
      final e = r.entries.single;
      expect(e.title, 'Opening keynote');
      expect(e.speakerNames, ['Samlytics Data Services']);
      expect(e.room, 'Main stage');
      expect(e.typeText, 'Plenary');
      expect(e.startUtc, DateTime.utc(2026, 11, 4, 9));
      expect(e.endUtc, DateTime.utc(2026, 11, 4, 9, 45));
    });

    test('P2-07 reads the Outlook calendar CSV layout', () {
      final r = csv(
        '"Subject","Start Date","Start Time","End Date","End Time",'
        '"All day event","Description","Location"\n'
        '"Panel: AI in public health","4 Nov 2026","2:00 PM","4 Nov 2026",'
        '"3:00 PM","False","Speakers: Samlytics Data Services","Room 3"\n',
      );
      final e = r.entries.single;
      expect(e.title, 'Panel: AI in public health');
      expect(e.startUtc, DateTime.utc(2026, 11, 4, 14));
      expect(e.endUtc, DateTime.utc(2026, 11, 4, 15));
      expect(e.room, 'Room 3');
      expect(e.description, 'Speakers: Samlytics Data Services');
    });

    test('P2-07 handles UTF-8 with a byte order mark, quoted fields, '
        'commas, doubled quotes and line breaks inside quotes', () {
      const text =
          'title,speaker,start\r\n'
          '"Data, ethics and ""trust""","Samlytics Data Services; '
          'Café team","2026-11-04T11:00"\r\n'
          '"Two-line\r\ntitle",,2026-11-04T12:00\r\n';
      final r = parseAgendaFile(
        fileName: 'agenda.csv',
        bytes: [0xEF, 0xBB, 0xBF, ...utf8.encode(text)],
        timezone: 'Europe/London',
      );
      expect(r.skipped, isEmpty);
      expect(r.entries, hasLength(2));
      expect(r.entries[0].title, 'Data, ethics and "trust"');
      expect(r.entries[0].speakerNames, [
        'Samlytics Data Services',
        'Café team',
      ]);
      expect(r.entries[1].title, 'Two-line\r\ntitle');
      expect(r.entries[1].line, 3);
      expect(r.entries[1].speakerNames, isEmpty);
    });

    test('P2-07 reads UTF-8 without a byte order mark and Latin-1', () {
      final utf = csv('title,start\nCafé talk,2026-11-04 10:00\n');
      expect(utf.entries.single.title, 'Café talk');
      final latin = parseAgendaFile(
        fileName: 'agenda.csv',
        bytes: latin1.encode('title,start\nCafé talk,2026-11-04 10:00\n'),
        timezone: 'Europe/London',
      );
      expect(latin.entries.single.title, 'Café talk');
    });

    test('P2-07 reads UTF-16 with a byte order mark (Excel Unicode text)', () {
      const text = 'title\tstart\nSamlytics keynote\t2026-11-04 10:00\n';
      final bytes = <int>[0xFF, 0xFE];
      for (final unit in text.codeUnits) {
        bytes.addAll([unit & 0xFF, unit >> 8]);
      }
      final r = parseAgendaFile(
        fileName: 'agenda.txt',
        bytes: bytes,
        timezone: 'Europe/London',
      );
      expect(r.entries.single.title, 'Samlytics keynote');
    });

    test('P2-07 times use the conference time zone, including summer time', () {
      final berlin = csv(
        'title,start,end\nWorkshop,2026-11-04 09:00,2026-11-04 10:30\n',
        timezone: 'Europe/Berlin',
      );
      expect(berlin.entries.single.startUtc, DateTime.utc(2026, 11, 4, 8));
      expect(berlin.entries.single.endUtc, DateTime.utc(2026, 11, 4, 9, 30));

      final londonSummer = csv('title,start\nWorkshop,2026-06-10 09:00\n');
      expect(
        londonSummer.entries.single.startUtc,
        DateTime.utc(2026, 6, 10, 8),
      );

      final newYork = csv(
        'title,start\nWorkshop,2026-11-04 09:00\n',
        timezone: 'America/New_York',
      );
      expect(newYork.entries.single.startUtc, DateTime.utc(2026, 11, 4, 14));
    });

    test('P2-07 an explicit offset or Z wins over the conference zone', () {
      final r = csv(
        'title,start,end\n'
        'Remote talk,2026-11-04T09:00:00Z,2026-11-04T11:00:00+01:00\n'
        'Backwards,2026-11-04T09:00:00Z,2026-11-04T09:00:00+01:00\n',
        timezone: 'Europe/Berlin',
      );
      expect(r.entries[0].startUtc, DateTime.utc(2026, 11, 4, 9));
      expect(r.entries[0].endUtc, DateTime.utc(2026, 11, 4, 10));
      // An end that is not after the start is dropped with a warning.
      expect(r.entries[1].endUtc, isNull);
      expect(r.warnings.single, contains('Line 3'));
    });

    test('P2-07 a date with no time is an all-day session', () {
      final r = csv(
        'title,date,all day\n'
        'Exhibition open,04/11/2026,\n'
        'Registration,05/11/2026,yes\n',
        timezone: 'Europe/Berlin',
      );
      final expo = r.entries[0];
      expect(expo.allDay, isTrue);
      // Midnight in Berlin (UTC+1) to the next midnight.
      expect(expo.startUtc, DateTime.utc(2026, 11, 3, 23));
      expect(expo.endUtc, DateTime.utc(2026, 11, 4, 23));
      expect(r.entries[1].allDay, isTrue);
    });

    test('P2-07 an end time before the start runs past midnight', () {
      final r = csv(
        'title,date,start,end\nEvening social,04/11/2026,22:30,00:30\n',
      );
      expect(r.entries.single.endUtc, DateTime.utc(2026, 11, 5, 0, 30));
    });

    test('P2-07 a time range in one cell gives the start and the end', () {
      final r = csv(
        'title,date,time\nLightning talks,2026-11-04,14:00–14:45\n',
      );
      expect(r.entries.single.startUtc, DateTime.utc(2026, 11, 4, 14));
      expect(r.entries.single.endUtc, DateTime.utc(2026, 11, 4, 14, 45));
    });

    test('P2-07 a duration column gives the end', () {
      final r = csv('title,start,duration\nTalk,2026-11-04 10:00,25\n');
      expect(r.entries.single.endUtc, DateTime.utc(2026, 11, 4, 10, 25));
    });

    test(
      'P2-07 numeric dates are day first unless the file is month first',
      () {
        final uk = csv('title,start\nA,03/11/2026 10:00\n');
        expect(uk.entries.single.startUtc, DateTime.utc(2026, 11, 3, 10));
        final us = csv(
          'title,start\nA,11/03/2026 10:00\nB,11/30/2026 10:00\n',
          timezone: 'UTC',
        );
        expect(us.entries[0].startUtc, DateTime.utc(2026, 11, 3, 10));
        expect(us.entries[1].startUtc, DateTime.utc(2026, 11, 30, 10));
      },
    );

    test('P2-07 a time with no date uses the default day, else is skipped', () {
      const text = 'title,start\nMorning talk,09:30\n';
      final noDay = csv(text);
      expect(noDay.entries, isEmpty);
      expect(noDay.skipped.single.reason, 'No date for this session.');
      final oneDay = csv(text, defaultDate: DateTime.utc(2026, 11, 4));
      expect(oneDay.entries.single.startUtc, DateTime.utc(2026, 11, 4, 9, 30));
    });

    test('P2-07 bad rows are skipped with a line number and a reason; empty '
        'rows are ignored', () {
      final r = csv(
        'title,start\n'
        ',2026-11-04 09:00\n'
        '\n'
        'Mystery talk,soon\n'
        'No time at all,\n'
        'Good talk,2026-11-04 11:00\n'
        'Good talk,2026-11-04 11:00\n'
        'Bad day,31/02/2026 10:00\n',
      );
      expect(r.entries.single.title, 'Good talk');
      expect(r.skipped.map((s) => s.toString()), [
        'Line 2: No title.',
        'Line 4: Start time not understood: "soon".',
        'Line 5: No start time.',
        'Line 7: Same session as line 6.',
        'Line 8: Start time not understood: "31/02/2026 10:00".',
      ]);
    });

    test('P2-07 a file without a title or start column is refused', () {
      expect(
        () => csv('speaker,room\nSamlytics Data Services,Hall A\n'),
        throwsA(
          isA<AgendaFormatException>().having(
            (e) => e.message,
            'message',
            contains('No title column'),
          ),
        ),
      );
      expect(
        () => csv('title,room\nKeynote,Hall A\n'),
        throwsA(isA<AgendaFormatException>()),
      );
      expect(() => csv(''), throwsA(isA<AgendaFormatException>()));
    });

    test('P2-07 files over the size limit are refused before reading', () {
      expect(
        () => parseAgendaFile(
          fileName: 'agenda.csv',
          bytes: List.filled(maxAgendaFileBytes + 1, 0x41),
          timezone: 'Europe/London',
        ),
        throwsA(isA<AgendaFormatException>()),
      );
    });
  });

  group('P2-07 ICS agenda', () {
    test('P2-07 reads SUMMARY, DTSTART and DTEND with TZID, LOCATION, '
        'DESCRIPTION, CATEGORIES and UID', () {
      final r = ics(
        'BEGIN:VEVENT\r\n'
        'UID:keynote-1@samlytics.example\r\n'
        'SUMMARY:Data Mesh in Practice\r\n'
        'DTSTART;TZID=Europe/Berlin:20261104T093000\r\n'
        'DTEND;TZID=Europe/Berlin:20261104T101500\r\n'
        'LOCATION:Hall A\\, level 2\r\n'
        'DESCRIPTION:Speaker: Samlytics Data Services\\nWhy domains matter.\r\n'
        'CATEGORIES:Keynote,Data\r\n'
        'END:VEVENT',
      );
      expect(r.format, AgendaSource.ics);
      final e = r.entries.single;
      expect(e.title, 'Data Mesh in Practice');
      expect(e.startUtc, DateTime.utc(2026, 11, 4, 8, 30));
      expect(e.endUtc, DateTime.utc(2026, 11, 4, 9, 15));
      expect(e.room, 'Hall A, level 2');
      expect(
        e.description,
        'Speaker: Samlytics Data Services\nWhy domains '
        'matter.',
      );
      expect(e.speakerNames, ['Samlytics Data Services']);
      expect(e.typeText, 'Keynote');
      expect(e.uid, 'keynote-1@samlytics.example');
      expect(r.warnings, isEmpty);
    });

    test('P2-07 UTC, floating, Windows and vendor-prefixed time zones', () {
      final r = ics(
        'BEGIN:VEVENT\r\nSUMMARY:UTC\r\nDTSTART:20261104T090000Z\r\n'
        'END:VEVENT\r\n'
        'BEGIN:VEVENT\r\nSUMMARY:Floating\r\nDTSTART:20261104T090000\r\n'
        'END:VEVENT\r\n'
        'BEGIN:VEVENT\r\nSUMMARY:Windows\r\n'
        'DTSTART;TZID="W. Europe Standard Time":20261104T090000\r\n'
        'END:VEVENT\r\n'
        'BEGIN:VEVENT\r\nSUMMARY:Mozilla\r\n'
        'DTSTART;TZID=/mozilla.org/20050126_1/America/New_York:'
        '20261104T090000\r\nEND:VEVENT',
        timezone: 'Europe/Berlin',
      );
      final byTitle = {for (final e in r.entries) e.title: e.startUtc};
      expect(byTitle['UTC'], DateTime.utc(2026, 11, 4, 9));
      // Floating times are read in the conference zone (Berlin, UTC+1).
      expect(byTitle['Floating'], DateTime.utc(2026, 11, 4, 8));
      expect(byTitle['Windows'], DateTime.utc(2026, 11, 4, 8));
      expect(byTitle['Mozilla'], DateTime.utc(2026, 11, 4, 14));
    });

    test('P2-07 an unknown TZID uses the conference zone with a warning', () {
      final r = ics(
        'BEGIN:VEVENT\r\nSUMMARY:Somewhere\r\n'
        'DTSTART;TZID=Samlytics Standard Time:20261104T090000\r\n'
        'END:VEVENT',
        timezone: 'Europe/Berlin',
      );
      expect(r.entries.single.startUtc, DateTime.utc(2026, 11, 4, 8));
      expect(r.warnings.single, contains('Samlytics Standard Time'));
    });

    test('P2-07 all-day events: VALUE=DATE, with and without DTEND', () {
      final r = ics(
        'BEGIN:VEVENT\r\nSUMMARY:Samlytics Conference 2026\r\n'
        'DTSTART;VALUE=DATE:20261104\r\nDTEND;VALUE=DATE:20261106\r\n'
        'END:VEVENT\r\n'
        'BEGIN:VEVENT\r\nSUMMARY:Exhibition day\r\n'
        'DTSTART;VALUE=DATE:20261105\r\nEND:VEVENT',
        timezone: 'Europe/Berlin',
      );
      final conf = r.entries[0];
      expect(conf.allDay, isTrue);
      expect(conf.startUtc, DateTime.utc(2026, 11, 3, 23));
      expect(conf.endUtc, DateTime.utc(2026, 11, 5, 23));
      final expo = r.entries[1];
      expect(expo.allDay, isTrue);
      expect(expo.startUtc, DateTime.utc(2026, 11, 4, 23));
      expect(expo.endUtc, DateTime.utc(2026, 11, 5, 23));
    });

    test('P2-07 folded lines, DURATION, alarms and LF line ends', () {
      final r = parseAgendaFile(
        fileName: 'calendar.txt',
        bytes: utf8.encode(
          'BEGIN:VCALENDAR\nBEGIN:VEVENT\nSUMMARY:A very long title that '
          'was\n  folded\nDTSTART:20261104T090000Z\nDURATION:PT1H30M\n'
          'BEGIN:VALARM\nSUMMARY:Alarm text, not the title\n'
          'TRIGGER:-PT10M\nEND:VALARM\nEND:VEVENT\nEND:VCALENDAR\n',
        ),
        timezone: 'Europe/London',
      );
      final e = r.entries.single;
      expect(e.title, 'A very long title that was folded');
      expect(e.endUtc, DateTime.utc(2026, 11, 4, 10, 30));
    });

    test('P2-07 bad events are skipped with reasons', () {
      final r = ics(
        'BEGIN:VEVENT\r\nDTSTART:20261104T090000Z\r\nEND:VEVENT\r\n'
        'BEGIN:VEVENT\r\nSUMMARY:No start\r\nEND:VEVENT\r\n'
        'BEGIN:VEVENT\r\nSUMMARY:Garbled\r\nDTSTART:tomorrow\r\nEND:VEVENT\r\n'
        'BEGIN:VEVENT\r\nSUMMARY:Called off\r\nSTATUS:CANCELLED\r\n'
        'DTSTART:20261104T090000Z\r\nEND:VEVENT\r\n'
        'BEGIN:VEVENT\r\nSUMMARY:Kept\r\nDTSTART:20261104T090000Z\r\n'
        'RRULE:FREQ=DAILY;COUNT=2\r\nEND:VEVENT',
      );
      expect(r.entries.single.title, 'Kept');
      expect(r.skipped.map((s) => s.reason), [
        'No title.',
        'No start time.',
        'Start time not understood: "tomorrow".',
        'Cancelled in the calendar.',
      ]);
      expect(r.skipped.first.line, 4);
      expect(r.warnings.single, contains('repeats'));
    });

    test('P2-07 a file that is not a calendar is refused', () {
      expect(
        () => parseAgendaFile(
          fileName: 'agenda.ics',
          bytes: utf8.encode('hello'),
          timezone: 'Europe/London',
        ),
        throwsA(isA<AgendaFormatException>()),
      );
    });

    test('P2-07 a calendar is detected by content whatever its name', () {
      final r = parseAgendaFile(
        fileName: 'download',
        bytes: utf8.encode(
          'BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nSUMMARY:Talk\r\n'
          'DTSTART:20261104T090000Z\r\nEND:VEVENT\r\nEND:VCALENDAR',
        ),
        timezone: 'Europe/London',
      );
      expect(r.format, AgendaSource.ics);
      expect(r.entries, hasLength(1));
    });
  });

  test('P2-07 speaker names split on semicolons, bars and line breaks', () {
    expect(splitSpeakerNames('Ada; Grace | Samlytics Data Services\nLin'), [
      'Ada',
      'Grace',
      'Samlytics Data Services',
      'Lin',
    ]);
    expect(splitSpeakerNames('Lovelace, Ada'), ['Lovelace, Ada']);
    expect(splitSpeakerNames('  '), isEmpty);
  });
}

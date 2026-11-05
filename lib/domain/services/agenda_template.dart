import 'dart:convert';

// The CSV agenda template people download, fill in and import, so files
// arrive in one known layout (FR-ACT-10) [P2-07a]. Every column is one the
// agenda reader already knows (ADR-082).

/// The name the template is saved under.
const agendaTemplateFileName = 'attenlume-agenda-template.csv';

/// The template's columns, in order. `title` and `date` with `start` are
/// needed; the rest may be left empty.
const agendaTemplateColumns = [
  'title',
  'speaker',
  'room',
  'date',
  'start',
  'end',
  'type',
  'description',
];

/// Example rows: they show the date and time layout, and a semicolon
/// between several speakers. People overwrite or delete them.
const _exampleRows = [
  [
    'Opening keynote',
    'Samlytics Data Services',
    'Main stage',
    '2026-11-04',
    '09:00',
    '09:45',
    'Keynote',
    'Welcome and the plan for the day',
  ],
  [
    'Panel: data in practice',
    'First Speaker; Second Speaker',
    'Hall A',
    '2026-11-04',
    '10:00',
    '10:45',
    'Panel',
    'Separate several speakers with a semicolon',
  ],
  [
    'Hands-on workshop',
    'Samlytics Data Services',
    'Room 2',
    '2026-11-04',
    '11:00',
    '12:30',
    'Workshop',
    '',
  ],
];

/// The template as text: a header row and the example rows, with Windows
/// line endings, which Excel and every other reader accept.
String agendaCsvTemplate() {
  final rows = [agendaTemplateColumns, ..._exampleRows];
  final lines = rows.map((row) => row.map(_csvField).join(','));
  return '${lines.join('\r\n')}\r\n';
}

/// The template as UTF-8 with a byte order mark, so Excel keeps accented
/// names intact when the file is edited and saved again.
List<int> agendaCsvTemplateBytes() => [
  0xEF,
  0xBB,
  0xBF,
  ...utf8.encode(agendaCsvTemplate()),
];

String _csvField(String value) => value.contains(RegExp(r'[",\r\n]'))
    ? '"${value.replaceAll('"', '""')}"'
    : value;

import 'dart:convert';

import 'package:timezone/timezone.dart' as tz;

import '../models/planned_session.dart';
import 'activity_title.dart' show ensureTimeZonesLoaded;

// Agenda import: a small CSV and ICS reader of our own (ADR-082) [P2-07].
// Everything runs on the device; nothing is fetched (NFR-01). Times without
// their own zone are read in the conference time zone and stored in UTC
// (BUILD_GUIDE 9.4).

/// Larger files are refused before they are read, so memory stays bounded
/// (NFR-10). A 2,000-session agenda is well under 1 MB.
const maxAgendaFileBytes = 2 * 1024 * 1024;

/// Sessions read from one file at most. The rest are reported, not saved.
const maxAgendaEntries = 2000;

/// One session read from an agenda file.
class AgendaEntry {
  const AgendaEntry({
    required this.line,
    required this.title,
    this.speakerNames = const [],
    this.room,
    this.typeText,
    this.description,
    required this.startUtc,
    this.endUtc,
    this.allDay = false,
    this.uid,
  });

  /// Line in the file where the row or event starts (1-based).
  final int line;
  final String title;
  final List<String> speakerNames;
  final String? room;
  final String? typeText;
  final String? description;
  final DateTime startUtc;
  final DateTime? endUtc;
  final bool allDay;

  /// ICS `UID`, when the file has one.
  final String? uid;
}

/// A row or event that was not imported, and why, in plain words.
class AgendaSkip {
  const AgendaSkip(this.line, this.reason);

  final int line;
  final String reason;

  @override
  String toString() => 'Line $line: $reason';
}

/// What one agenda file holds.
class AgendaParseResult {
  const AgendaParseResult({
    required this.format,
    required this.entries,
    required this.skipped,
    required this.warnings,
  });

  final AgendaSource format;
  final List<AgendaEntry> entries;
  final List<AgendaSkip> skipped;

  /// Things the user should know that did not stop a session being read,
  /// such as an unknown time zone.
  final List<String> warnings;
}

/// The file cannot be read as an agenda at all. [message] is shown to the
/// user as written.
class AgendaFormatException implements Exception {
  const AgendaFormatException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Reads an agenda file. ICS when the name ends in `.ics` (or `.ical`) or the
/// text starts with `BEGIN:VCALENDAR`, otherwise CSV.
///
/// [timezone] is the conference's IANA time zone, used for times that do
/// not carry their own. [defaultDate] (a calendar day, as stored on the
/// conference) is used for CSV rows that give a time but no date; callers
/// pass it only for one-day conferences.
AgendaParseResult parseAgendaFile({
  required String fileName,
  required List<int> bytes,
  required String timezone,
  DateTime? defaultDate,
}) {
  if (bytes.length > maxAgendaFileBytes) {
    throw const AgendaFormatException(
      'This file is larger than 2 MB, which is too big for an agenda. '
      'Choose a CSV or ICS file with just the sessions.',
    );
  }
  final text = decodeAgendaText(bytes);
  final lower = fileName.toLowerCase();
  final looksIcs = text.trimLeft().toUpperCase().startsWith('BEGIN:VCALENDAR');
  if (lower.endsWith('.ics') || lower.endsWith('.ical') || looksIcs) {
    return parseIcsAgenda(text, timezone: timezone);
  }
  return parseCsvAgenda(text, timezone: timezone, defaultDate: defaultDate);
}

/// Decodes UTF-8 with or without a byte order mark, and UTF-16 with one
/// (Excel's "Unicode text"). Bytes that are not valid UTF-8 are read as
/// Latin-1, so older spreadsheet exports still open.
String decodeAgendaText(List<int> bytes) {
  if (bytes.length >= 2) {
    final le = bytes[0] == 0xFF && bytes[1] == 0xFE;
    final be = bytes[0] == 0xFE && bytes[1] == 0xFF;
    if (le || be) {
      final units = <int>[];
      for (var i = 2; i + 1 < bytes.length; i += 2) {
        units.add(
          le ? bytes[i] | (bytes[i + 1] << 8) : (bytes[i] << 8) | bytes[i + 1],
        );
      }
      return String.fromCharCodes(units);
    }
  }
  var start = 0;
  if (bytes.length >= 3 &&
      bytes[0] == 0xEF &&
      bytes[1] == 0xBB &&
      bytes[2] == 0xBF) {
    start = 3;
  }
  final body = start == 0 ? bytes : bytes.sublist(start);
  try {
    return utf8.decode(body);
  } on FormatException {
    return latin1.decode(body, allowInvalid: true);
  }
}

// ---------------------------------------------------------------------------
// Time zones

tz.Location? _location(String name) {
  ensureTimeZonesLoaded();
  try {
    return tz.getLocation(name);
  } on tz.LocationNotFoundException {
    return null;
  }
}

/// Common Windows zone names that Outlook writes as `TZID`.
const _windowsZones = {
  'gmt standard time': 'Europe/London',
  'greenwich standard time': 'Atlantic/Reykjavik',
  'w. europe standard time': 'Europe/Berlin',
  'romance standard time': 'Europe/Paris',
  'central europe standard time': 'Europe/Budapest',
  'central european standard time': 'Europe/Warsaw',
  'e. europe standard time': 'Europe/Chisinau',
  'fle standard time': 'Europe/Helsinki',
  'gtb standard time': 'Europe/Bucharest',
  'eastern standard time': 'America/New_York',
  'central standard time': 'America/Chicago',
  'mountain standard time': 'America/Denver',
  'pacific standard time': 'America/Los_Angeles',
  'w. central africa standard time': 'Africa/Lagos',
  'south africa standard time': 'Africa/Johannesburg',
  'e. africa standard time': 'Africa/Nairobi',
  'arabian standard time': 'Asia/Dubai',
  'india standard time': 'Asia/Kolkata',
  'singapore standard time': 'Asia/Singapore',
  'china standard time': 'Asia/Shanghai',
  'tokyo standard time': 'Asia/Tokyo',
  'aus eastern standard time': 'Australia/Sydney',
  'utc': 'UTC',
  'coordinated universal time': 'UTC',
};

/// Resolves an ICS `TZID`: an IANA name, a vendor-prefixed one
/// (`/mozilla.org/20050126_1/Europe/London`) or a Windows name.
tz.Location? _resolveTzid(String tzid) {
  final name = tzid.trim().replaceAll('"', '');
  final direct = _location(name);
  if (direct != null) return direct;
  final parts = name.split('/').where((p) => p.isNotEmpty).toList();
  for (var take = 3; take >= 2; take--) {
    if (parts.length >= take) {
      final found = _location(parts.sublist(parts.length - take).join('/'));
      if (found != null) return found;
    }
  }
  final windows = _windowsZones[name.toLowerCase()];
  return windows == null ? null : _location(windows);
}

/// Wall-clock time in [location] (UTC when null) as a plain UTC [DateTime].
DateTime _toUtc(tz.Location? location, _Local t) {
  if (location == null) {
    return DateTime.utc(t.year, t.month, t.day, t.hour, t.minute, t.second);
  }
  final local = tz.TZDateTime(
    location,
    t.year,
    t.month,
    t.day,
    t.hour,
    t.minute,
    t.second,
  );
  return DateTime.fromMillisecondsSinceEpoch(
    local.millisecondsSinceEpoch,
    isUtc: true,
  );
}

class _Local {
  const _Local(
    this.year,
    this.month,
    this.day, [
    this.hour = 0,
    this.minute = 0,
    this.second = 0,
  ]);

  final int year, month, day, hour, minute, second;

  _Local withTime(_Time t) =>
      _Local(year, month, day, t.hour, t.minute, t.second);

  _Local addDays(int days) {
    final d = DateTime.utc(year, month, day + days);
    return _Local(d.year, d.month, d.day);
  }
}

class _Time {
  const _Time(this.hour, this.minute, [this.second = 0]);

  final int hour, minute, second;
}

// ---------------------------------------------------------------------------
// Dates and times written by people (CSV)

const _months = {
  'jan': 1,
  'feb': 2,
  'mar': 3,
  'apr': 4,
  'may': 5,
  'jun': 6,
  'jul': 7,
  'aug': 8,
  'sep': 9,
  'sept': 9,
  'oct': 10,
  'nov': 11,
  'dec': 12,
};

_Local? _validDate(int y, int m, int d) {
  if (y < 100) y += 2000;
  if (m < 1 || m > 12 || d < 1 || d > 31) return null;
  final check = DateTime.utc(y, m, d);
  if (check.month != m || check.day != d) return null;
  return _Local(y, m, d);
}

int? _monthNumber(String word) {
  final w = word.toLowerCase().replaceAll('.', '');
  if (w.length < 3) return null;
  return _months[w.length > 4 ? w.substring(0, 3) : w] ??
      _months[w.substring(0, 3)];
}

final _numericDate = RegExp(r'^(\d{1,2})[-/.](\d{1,2})[-/.](\d{2}|\d{4})\b');

/// Whether the numeric dates in [cells] are written month first (US): true
/// when some date only makes sense that way (`11/30/2026`) and none only
/// makes sense day first.
bool _isMonthFirst(Iterable<String> cells) {
  var monthFirst = false;
  for (final c in cells) {
    final m = _numericDate.firstMatch(c.trim());
    if (m == null) continue;
    final a = int.parse(m[1]!);
    final b = int.parse(m[2]!);
    if (a > 12 && b <= 12) return false;
    if (b > 12 && a <= 12) monthFirst = true;
  }
  return monthFirst;
}

/// Calendar dates: ISO (`2026-11-04`), UK day first (`04/11/2026`,
/// `4.11.26`), compact (`20261104`) and with month names (`4 Nov 2026`,
/// `Wednesday 4 November 2026`, `Nov 4, 2026`).
_Local? _parseDate(String input, {bool monthFirst = false}) {
  final s = input.trim();
  if (s.isEmpty) return null;
  var m = RegExp(r'^(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})$').firstMatch(s);
  if (m != null) {
    return _validDate(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
  }
  m = _numericDate.firstMatch(s);
  if (m != null && m.end == s.length) {
    // Day first, as written in the UK, unless the file is month first
    // (ADR-082).
    final a = int.parse(m[1]!);
    final b = int.parse(m[2]!);
    return _validDate(int.parse(m[3]!), monthFirst ? a : b, monthFirst ? b : a);
  }
  m = RegExp(r'^(\d{4})(\d{2})(\d{2})$').firstMatch(s);
  if (m != null && s.length == 8) {
    return _validDate(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
  }
  // Month names, with an optional weekday in front.
  final words = s
      .replaceAll(',', ' ')
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList();
  if (words.length >= 3) {
    final tail = words.sublist(words.length - 3);
    // 4 Nov 2026
    final d1 = int.tryParse(tail[0].replaceAll(RegExp(r'(st|nd|rd|th)$'), ''));
    final m1 = _monthNumber(tail[1]);
    final y1 = int.tryParse(tail[2]);
    if (d1 != null && m1 != null && y1 != null) return _validDate(y1, m1, d1);
    // Nov 4 2026
    final m2 = _monthNumber(tail[0]);
    final d2 = int.tryParse(tail[1].replaceAll(RegExp(r'(st|nd|rd|th)$'), ''));
    if (m2 != null && d2 != null && y1 != null) return _validDate(y1, m2, d2);
  }
  return null;
}

/// Times of day: `09:30`, `9.30`, `09:30:00`, `9:30 am`, `2pm`, `2 p.m.`.
_Time? _parseTime(String input) {
  final s = input.trim().toLowerCase();
  final m = RegExp(
    r'^(\d{1,2})(?:[:.](\d{2}))?(?::(\d{2}))?\s*([ap])?\.?\s*(m\.?)?$',
  ).firstMatch(s);
  if (m == null) return null;
  final ampm = m[4];
  if (m[2] == null && ampm == null) return null; // a bare number is not a time
  if (ampm != null && m[5] == null) return null;
  var hour = int.parse(m[1]!);
  final minute = m[2] == null ? 0 : int.parse(m[2]!);
  final second = m[3] == null ? 0 : int.parse(m[3]!);
  if (ampm != null) {
    if (hour < 1 || hour > 12) return null;
    if (ampm == 'a' && hour == 12) hour = 0;
    if (ampm == 'p' && hour != 12) hour += 12;
  }
  if (hour > 23 || minute > 59 || second > 59) return null;
  return _Time(hour, minute, second);
}

/// A date with a time, or a time alone.
class _When {
  const _When({this.date, this.time, this.utcOffset});

  final _Local? date;
  final _Time? time;

  /// From ISO text with `Z` or `+01:00`: the time is absolute.
  final Duration? utcOffset;
}

_When? _parseWhen(String input, {bool monthFirst = false}) {
  final s = input.trim();
  if (s.isEmpty) return null;
  final iso = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})[T ](\d{1,2}):(\d{2})(?::(\d{2})(?:\.\d+)?)?\s*'
    r'(Z|[+-]\d{2}:?\d{2})?$',
    caseSensitive: false,
  ).firstMatch(s);
  if (iso != null) {
    final date = _validDate(
      int.parse(iso[1]!),
      int.parse(iso[2]!),
      int.parse(iso[3]!),
    );
    final hour = int.parse(iso[4]!);
    final minute = int.parse(iso[5]!);
    final second = iso[6] == null ? 0 : int.parse(iso[6]!);
    if (date == null || hour > 23 || minute > 59 || second > 59) return null;
    Duration? offset;
    final z = iso[7];
    if (z != null) {
      if (z.toUpperCase() == 'Z') {
        offset = Duration.zero;
      } else {
        final digits = z.substring(1).replaceAll(':', '');
        final mins =
            int.parse(digits.substring(0, 2)) * 60 +
            int.parse(digits.substring(2));
        offset = Duration(minutes: z.startsWith('-') ? -mins : mins);
      }
    }
    return _When(
      date: date,
      time: _Time(hour, minute, second),
      utcOffset: offset,
    );
  }
  final time = _parseTime(s);
  if (time != null) return _When(time: time);
  final date = _parseDate(s, monthFirst: monthFirst);
  if (date != null) return _When(date: date);
  // "04/11/2026 09:30", "4 Nov 2026, 2pm", "2026-11-04T09:30" without zone.
  final split = RegExp(
    r'^(.*?)[\sT,]+(\d{1,2}(?:[:.]\d{2}){0,2}\s*(?:[ap]\.?\s*m\.?)?)$',
    caseSensitive: false,
  ).firstMatch(s);
  if (split != null) {
    final d = _parseDate(split[1]!, monthFirst: monthFirst);
    final t = _parseTime(split[2]!);
    if (d != null && t != null) return _When(date: d, time: t);
  }
  return null;
}

// ---------------------------------------------------------------------------
// CSV

/// One CSV record and the line it starts on.
class _Record {
  _Record(this.line, this.fields);

  final int line;
  final List<String> fields;
}

/// The delimiter of the first line: comma, semicolon (Excel in much of
/// Europe) or tab, whichever appears most outside quotes.
String _detectDelimiter(String text) {
  final counts = {',': 0, ';': 0, '\t': 0};
  var inQuotes = false;
  for (var i = 0; i < text.length; i++) {
    final c = text[i];
    if (c == '"') inQuotes = !inQuotes;
    if (!inQuotes && (c == '\n' || c == '\r')) {
      if (counts.values.any((n) => n > 0)) break;
      continue;
    }
    if (!inQuotes && counts.containsKey(c)) counts[c] = counts[c]! + 1;
  }
  var best = ',';
  for (final d in [';', '\t']) {
    if (counts[d]! > counts[best]!) best = d;
  }
  return best;
}

/// RFC 4180 records: quoted fields may hold the delimiter, line breaks and
/// doubled quotes. CRLF, LF and CR line ends are all accepted.
List<_Record> _readCsv(String text, String delimiter) {
  final records = <_Record>[];
  var fields = <String>[];
  final field = StringBuffer();
  var inQuotes = false;
  var line = 1;
  var recordLine = 1;
  var fieldStarted = false;

  void endField() {
    fields.add(field.toString());
    field.clear();
    fieldStarted = false;
  }

  void endRecord() {
    endField();
    records.add(_Record(recordLine, fields));
    fields = <String>[];
  }

  for (var i = 0; i < text.length; i++) {
    final c = text[i];
    if (inQuotes) {
      if (c == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        if (c == '\n') line++;
        if (c == '\r') {
          if (i + 1 < text.length && text[i + 1] == '\n') {
            field.write('\r');
            continue;
          }
          line++;
        }
        field.write(c);
      }
      continue;
    }
    if (c == '"' && !fieldStarted && field.toString().trim().isEmpty) {
      field.clear();
      inQuotes = true;
      fieldStarted = true;
    } else if (c == delimiter) {
      endField();
    } else if (c == '\r' || c == '\n') {
      if (c == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
      endRecord();
      line++;
      recordLine = line;
    } else {
      field.write(c);
      if (c != ' ') fieldStarted = true;
    }
  }
  if (field.isNotEmpty || fields.isNotEmpty || fieldStarted) endRecord();
  return records;
}

String _normaliseHeader(String h) =>
    h.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

/// Header names each field accepts, after [_normaliseHeader]. Earlier
/// fields claim a column first, so "summary" is the title only when there
/// is no other title column.
const _headerAliases = <String, List<String>>{
  'title': [
    'title',
    'sessiontitle',
    'session',
    'sessionname',
    'talk',
    'talktitle',
    'name',
    'subject',
    'event',
    'eventname',
    'eventtitle',
    'topic',
    'summary',
  ],
  'speaker': [
    'speaker',
    'speakers',
    'speakername',
    'speakernames',
    'presenter',
    'presenters',
    'presentedby',
    'host',
    'hosts',
    'moderator',
  ],
  'room': [
    'room',
    'location',
    'venue',
    'stage',
    'hall',
    'roomname',
    'where',
    'place',
  ],
  'startDate': ['startdate', 'date', 'day', 'sessiondate', 'eventdate'],
  'start': [
    'start',
    'starttime',
    'startdatetime',
    'starts',
    'startsat',
    'startat',
    'begin',
    'begins',
    'from',
    'time',
  ],
  'endDate': ['enddate'],
  'end': [
    'end',
    'endtime',
    'enddatetime',
    'ends',
    'endsat',
    'endat',
    'finish',
    'finishes',
    'until',
    'to',
  ],
  'duration': ['duration', 'durationminutes', 'durationmins', 'length', 'mins'],
  'type': [
    'type',
    'sessiontype',
    'format',
    'sessionformat',
    'category',
    'kind',
    'activitytype',
  ],
  'description': [
    'description',
    'abstract',
    'details',
    'notes',
    'synopsis',
    'summary',
  ],
  'allDay': ['allday', 'alldayevent'],
};

/// Reads a CSV agenda. The first non-empty row names the columns.
AgendaParseResult parseCsvAgenda(
  String text, {
  required String timezone,
  DateTime? defaultDate,
}) {
  final location = _location(timezone);
  final records = _readCsv(text, _detectDelimiter(text));
  final rows = records
      .where((r) => r.fields.any((f) => f.trim().isNotEmpty))
      .toList();
  if (rows.isEmpty) {
    throw const AgendaFormatException('This file is empty.');
  }
  final header = rows.first.fields.map(_normaliseHeader).toList();
  final columns = <String, int>{};
  for (final MapEntry(key: name, value: aliases) in _headerAliases.entries) {
    for (final alias in aliases) {
      final index = header.indexOf(alias);
      if (index >= 0 && !columns.values.contains(index)) {
        columns[name] = index;
        break;
      }
    }
  }
  if (!columns.containsKey('title')) {
    throw const AgendaFormatException(
      'No title column found. The first row should name the columns, '
      'for example: title, speaker, room, start, end, type.',
    );
  }
  if (!columns.containsKey('start') && !columns.containsKey('startDate')) {
    throw const AgendaFormatException(
      'No start column found. The first row should name the columns, '
      'for example: title, speaker, room, start, end, type.',
    );
  }

  final dateCells = [
    for (final r in rows.skip(1))
      for (final name in const ['startDate', 'start', 'endDate', 'end'])
        if (columns[name] case final i? when i < r.fields.length) r.fields[i],
  ];
  final monthFirst = _isMonthFirst(dateCells);
  _When? when(String s) => _parseWhen(s, monthFirst: monthFirst);

  final fallbackDay = defaultDate == null
      ? null
      : _Local(defaultDate.year, defaultDate.month, defaultDate.day);
  final entries = <AgendaEntry>[];
  final skipped = <AgendaSkip>[];
  final warnings = <String>[];
  final seen = <String, int>{};

  String cell(_Record r, String name) {
    final i = columns[name];
    if (i == null || i >= r.fields.length) return '';
    return r.fields[i].trim();
  }

  for (final row in rows.skip(1)) {
    final title = _clip(cell(row, 'title'), 300);
    if (title.isEmpty) {
      skipped.add(AgendaSkip(row.line, 'No title.'));
      continue;
    }
    var startText = cell(row, 'start');
    final dateText = cell(row, 'startDate');
    var endText = cell(row, 'end');
    // "09:30-10:15" (or with an en dash) in one cell: start and end.
    if (when(startText) == null) {
      final range = RegExp(r'^(.+?)\s*[-–—]\s*(.+)$').firstMatch(startText);
      if (range != null &&
          _parseTime(range[1]!) != null &&
          _parseTime(range[2]!) != null) {
        startText = range[1]!.trim();
        if (endText.isEmpty) endText = range[2]!.trim();
      }
    }
    final allDayText = cell(row, 'allDay').toLowerCase();
    final markedAllDay = const {
      'true',
      'yes',
      'y',
      '1',
      'all day',
    }.contains(allDayText);

    // Work out the start: a full date and time, a date and a time in two
    // columns, a date alone (all day), or a time on the default day.
    final startWhen = when(startText);
    final dateWhen = when(dateText);
    if (startText.isNotEmpty && startWhen == null) {
      skipped.add(
        AgendaSkip(row.line, 'Start time not understood: "$startText".'),
      );
      continue;
    }
    if (dateText.isNotEmpty && dateWhen == null) {
      skipped.add(AgendaSkip(row.line, 'Date not understood: "$dateText".'));
      continue;
    }
    final day = startWhen?.date ?? dateWhen?.date ?? fallbackDay;
    final time = startWhen?.time ?? dateWhen?.time;
    if (day == null) {
      skipped.add(
        AgendaSkip(
          row.line,
          time == null ? 'No start time.' : 'No date for this session.',
        ),
      );
      continue;
    }
    final allDay = markedAllDay || time == null;
    final offset = startWhen?.utcOffset ?? dateWhen?.utcOffset;
    final DateTime startUtc;
    if (allDay) {
      startUtc = _toUtc(location, day);
    } else if (offset != null) {
      final l = day.withTime(time);
      startUtc = DateTime.utc(
        l.year,
        l.month,
        l.day,
        l.hour,
        l.minute,
        l.second,
      ).subtract(offset);
    } else {
      startUtc = _toUtc(location, day.withTime(time));
    }

    // The end: a full date and time, a time on the start's day (the next
    // day when it would be before the start), or a length in minutes.
    DateTime? endUtc;
    final endDateText = cell(row, 'endDate');
    final endWhen = when(endText);
    final endDateWhen = when(endDateText);
    if (endText.isNotEmpty && endWhen == null) {
      warnings.add(
        'Line ${row.line}: end time "$endText" not understood, left empty.',
      );
    }
    if (allDay) {
      final last = endWhen?.date ?? endDateWhen?.date ?? day;
      endUtc = _toUtc(location, last.addDays(1));
    } else if (endWhen != null || endDateWhen != null) {
      final endDay = endWhen?.date ?? endDateWhen?.date ?? day;
      final endTime = endWhen?.time ?? endDateWhen?.time;
      if (endTime != null) {
        final endOffset = endWhen?.utcOffset ?? endDateWhen?.utcOffset;
        final l = endDay.withTime(endTime);
        endUtc = endOffset != null
            ? DateTime.utc(
                l.year,
                l.month,
                l.day,
                l.hour,
                l.minute,
                l.second,
              ).subtract(endOffset)
            : _toUtc(location, l);
        final sameDayOnly = endWhen?.date == null && endDateWhen?.date == null;
        if (!endUtc.isAfter(startUtc) && sameDayOnly) {
          endUtc = _toUtc(location, day.addDays(1).withTime(endTime));
        }
      }
    } else {
      final minutes = int.tryParse(cell(row, 'duration'));
      if (minutes != null && minutes > 0 && minutes <= 24 * 60) {
        endUtc = startUtc.add(Duration(minutes: minutes));
      }
    }
    if (endUtc != null && !endUtc.isAfter(startUtc)) {
      warnings.add('Line ${row.line}: ends before it starts, end left empty.');
      endUtc = null;
    }

    final key = '${_titleKey(title)}|${startUtc.toIso8601String()}';
    final first = seen[key];
    if (first != null) {
      skipped.add(AgendaSkip(row.line, 'Same session as line $first.'));
      continue;
    }
    if (entries.length >= maxAgendaEntries) {
      skipped.add(
        AgendaSkip(row.line, 'More than $maxAgendaEntries sessions in file.'),
      );
      continue;
    }
    seen[key] = row.line;
    entries.add(
      AgendaEntry(
        line: row.line,
        title: title,
        speakerNames: splitSpeakerNames(cell(row, 'speaker')),
        room: _nullIfEmpty(_clip(cell(row, 'room'), 200)),
        typeText: _nullIfEmpty(_clip(cell(row, 'type'), 100)),
        description: _nullIfEmpty(_clip(cell(row, 'description'), 10000)),
        startUtc: startUtc,
        endUtc: endUtc,
        allDay: allDay,
      ),
    );
  }
  if (location == null) {
    warnings.add(
      'The conference time zone "$timezone" is not known, so times were '
      'read as UTC.',
    );
  }
  return AgendaParseResult(
    format: AgendaSource.csv,
    entries: entries,
    skipped: skipped,
    warnings: warnings,
  );
}

// ---------------------------------------------------------------------------
// ICS (RFC 5545, the parts agendas use)

class _Property {
  _Property(this.name, this.params, this.value);

  final String name;
  final Map<String, String> params;
  final String value;
}

/// Splits [s] at [sep] outside double quotes.
List<String> _splitUnquoted(String s, String sep) {
  final out = <String>[];
  final buf = StringBuffer();
  var quoted = false;
  for (var i = 0; i < s.length; i++) {
    final c = s[i];
    if (c == '"') quoted = !quoted;
    if (c == sep && !quoted) {
      out.add(buf.toString());
      buf.clear();
    } else {
      buf.write(c);
    }
  }
  out.add(buf.toString());
  return out;
}

_Property? _parseContentLine(String line) {
  var quoted = false;
  var colon = -1;
  for (var i = 0; i < line.length; i++) {
    if (line[i] == '"') quoted = !quoted;
    if (line[i] == ':' && !quoted) {
      colon = i;
      break;
    }
  }
  if (colon <= 0) return null;
  final head = _splitUnquoted(line.substring(0, colon), ';');
  final params = <String, String>{};
  for (final p in head.skip(1)) {
    final eq = p.indexOf('=');
    if (eq <= 0) continue;
    params[p.substring(0, eq).toUpperCase()] = p
        .substring(eq + 1)
        .replaceAll('"', '');
  }
  return _Property(head.first.toUpperCase(), params, line.substring(colon + 1));
}

String _unescapeIcsText(String s) {
  final out = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    final c = s[i];
    if (c == r'\' && i + 1 < s.length) {
      final n = s[++i];
      out.write(switch (n) {
        'n' || 'N' => '\n',
        _ => n,
      });
    } else {
      out.write(c);
    }
  }
  return out.toString();
}

/// An ICS date or date-time, read in its own zone.
class _IcsTime {
  const _IcsTime(this.utc, {required this.allDay, required this.day});

  final DateTime utc;
  final bool allDay;
  final _Local day;
}

Duration? _parseIcsDuration(String s) {
  final m = RegExp(
    r'^([+-])?P(?:(\d+)W)?(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?$',
  ).firstMatch(s.trim().toUpperCase());
  if (m == null) return null;
  int n(int g) => m[g] == null ? 0 : int.parse(m[g]!);
  final d = Duration(
    days: n(2) * 7 + n(3),
    hours: n(4),
    minutes: n(5),
    seconds: n(6),
  );
  return m[1] == '-' ? -d : d;
}

/// Reads the VEVENTs of an ICS calendar.
AgendaParseResult parseIcsAgenda(String text, {required String timezone}) {
  final conferenceZone = _location(timezone);
  final warnings = <String>[];
  final unknownZones = <String>{};

  // Unfold: a line starting with a space or tab continues the one before.
  final lines = <(int, String)>[];
  final raw = text.split(RegExp(r'\r\n|\n|\r'));
  for (var i = 0; i < raw.length; i++) {
    final l = raw[i];
    if ((l.startsWith(' ') || l.startsWith('\t')) && lines.isNotEmpty) {
      final (n, prev) = lines.removeLast();
      lines.add((n, prev + l.substring(1)));
    } else if (l.isNotEmpty) {
      lines.add((i + 1, l));
    }
  }
  if (!lines.any((l) => l.$2.toUpperCase() == 'BEGIN:VCALENDAR')) {
    throw const AgendaFormatException(
      'This is not a calendar file. An ICS file starts with BEGIN:VCALENDAR.',
    );
  }

  _IcsTime? readTime(_Property p) {
    final v = p.value.trim();
    final dateOnly = RegExp(r'^(\d{4})(\d{2})(\d{2})$').firstMatch(v);
    if (dateOnly != null || p.params['VALUE']?.toUpperCase() == 'DATE') {
      if (dateOnly == null) return null;
      final day = _validDate(
        int.parse(dateOnly[1]!),
        int.parse(dateOnly[2]!),
        int.parse(dateOnly[3]!),
      );
      if (day == null) return null;
      return _IcsTime(_toUtc(conferenceZone, day), allDay: true, day: day);
    }
    final m = RegExp(
      r'^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})?(Z)?$',
      caseSensitive: false,
    ).firstMatch(v);
    if (m == null) return null;
    final day = _validDate(
      int.parse(m[1]!),
      int.parse(m[2]!),
      int.parse(m[3]!),
    );
    final hour = int.parse(m[4]!);
    final minute = int.parse(m[5]!);
    final second = m[6] == null ? 0 : int.parse(m[6]!);
    if (day == null || hour > 23 || minute > 59 || second > 60) return null;
    final local = day.withTime(_Time(hour, minute, second.clamp(0, 59)));
    if (m[7] != null) {
      return _IcsTime(_toUtc(null, local), allDay: false, day: day);
    }
    final tzid = p.params['TZID'];
    var zone = conferenceZone;
    if (tzid != null) {
      final resolved = _resolveTzid(tzid);
      if (resolved != null) {
        zone = resolved;
      } else {
        unknownZones.add(tzid);
      }
    }
    return _IcsTime(_toUtc(zone, local), allDay: false, day: day);
  }

  final entries = <AgendaEntry>[];
  final skipped = <AgendaSkip>[];
  final seen = <String, int>{};
  Map<String, _Property>? event;
  var eventLine = 0;
  var nested = 0;

  void finish() {
    final e = event!;
    String? textOf(String name) {
      final p = e[name];
      if (p == null) return null;
      final v = _unescapeIcsText(p.value).trim();
      return v.isEmpty ? null : v;
    }

    if (e['STATUS']?.value.trim().toUpperCase() == 'CANCELLED') {
      skipped.add(AgendaSkip(eventLine, 'Cancelled in the calendar.'));
      return;
    }
    final title = _clip(textOf('SUMMARY') ?? '', 300);
    if (title.isEmpty) {
      skipped.add(AgendaSkip(eventLine, 'No title.'));
      return;
    }
    final startProp = e['DTSTART'];
    if (startProp == null) {
      skipped.add(AgendaSkip(eventLine, 'No start time.'));
      return;
    }
    final start = readTime(startProp);
    if (start == null) {
      skipped.add(
        AgendaSkip(
          eventLine,
          'Start time not understood: "${startProp.value.trim()}".',
        ),
      );
      return;
    }
    DateTime? endUtc;
    final endProp = e['DTEND'];
    if (endProp != null) {
      final end = readTime(endProp);
      endUtc = end?.utc;
      if (end != null && start.allDay && !end.allDay) endUtc = null;
    } else if (e['DURATION'] case final d?) {
      final duration = _parseIcsDuration(d.value);
      if (duration != null) endUtc = start.utc.add(duration);
    } else if (start.allDay) {
      // RFC 5545: an all-day event with no end lasts that one day.
      endUtc = _toUtc(conferenceZone, start.day.addDays(1));
    }
    if (endUtc != null && !endUtc.isAfter(start.utc)) {
      warnings.add(
        'Line $eventLine: "$title" ends before it starts, end left '
        'empty.',
      );
      endUtc = null;
    }
    if (e.containsKey('RRULE')) {
      warnings.add(
        '"$title" repeats in the calendar. Only its first time was imported.',
      );
    }

    final description = textOf('DESCRIPTION');
    final speakerText =
        textOf('X-SPEAKER') ??
        textOf('X-SPEAKERS') ??
        _speakerFromDescription(description);
    final categories = textOf('CATEGORIES');
    final key = '${_titleKey(title)}|${start.utc.toIso8601String()}';
    final first = seen[key];
    if (first != null) {
      skipped.add(AgendaSkip(eventLine, 'Same session as line $first.'));
      return;
    }
    if (entries.length >= maxAgendaEntries) {
      skipped.add(
        AgendaSkip(eventLine, 'More than $maxAgendaEntries sessions in file.'),
      );
      return;
    }
    seen[key] = eventLine;
    entries.add(
      AgendaEntry(
        line: eventLine,
        title: title,
        speakerNames: splitSpeakerNames(speakerText ?? ''),
        room: _nullIfEmpty(_clip(textOf('LOCATION') ?? '', 200)),
        typeText: _nullIfEmpty(
          _clip(categories == null ? '' : categories.split(',').first, 100),
        ),
        description: _nullIfEmpty(_clip(description ?? '', 10000)),
        startUtc: start.utc,
        endUtc: endUtc,
        allDay: start.allDay,
        uid: _nullIfEmpty(_clip(e['UID']?.value.trim() ?? '', 300)),
      ),
    );
  }

  for (final (lineNo, line) in lines) {
    final upper = line.toUpperCase();
    if (event == null) {
      if (upper == 'BEGIN:VEVENT') {
        event = {};
        eventLine = lineNo;
        nested = 0;
      }
      continue;
    }
    if (upper.startsWith('BEGIN:')) {
      nested++;
      continue;
    }
    if (upper.startsWith('END:')) {
      if (nested > 0) {
        nested--;
        continue;
      }
      if (upper == 'END:VEVENT') {
        finish();
        event = null;
      }
      continue;
    }
    if (nested > 0) continue; // VALARM and friends
    final p = _parseContentLine(line);
    if (p != null) event.putIfAbsent(p.name, () => p);
  }
  if (event != null) {
    skipped.add(AgendaSkip(eventLine, 'The event is cut off (no END:VEVENT).'));
  }

  for (final zone in unknownZones) {
    warnings.add(
      'Time zone "$zone" is not known, so its times were read in the '
      'conference time zone ($timezone).',
    );
  }
  if (conferenceZone == null) {
    warnings.add(
      'The conference time zone "$timezone" is not known, so times without '
      'their own zone were read as UTC.',
    );
  }
  return AgendaParseResult(
    format: AgendaSource.ics,
    entries: entries,
    skipped: skipped,
    warnings: warnings,
  );
}

/// "Speaker: Ada Lovelace" (or Speakers, Presenter, Presented by) on its
/// own line of a description.
String? _speakerFromDescription(String? description) {
  if (description == null) return null;
  final m = RegExp(
    r'^\s*(?:speakers?|presenters?|presented by)\s*[:\-]\s*(.+)$',
    caseSensitive: false,
    multiLine: true,
  ).firstMatch(description);
  return m?[1]?.trim();
}

// ---------------------------------------------------------------------------
// Shared

/// Speaker names separated by semicolons, vertical bars or line breaks.
/// Commas are kept, because "Surname, First name" is common.
List<String> splitSpeakerNames(String text) => [
  for (final part in text.split(RegExp(r'[;|\r\n]+')))
    if (part.trim().isNotEmpty) _clip(part.trim(), 200),
];

/// Title compared without case, spacing or punctuation differences.
String _titleKey(String title) => title
    .toLowerCase()
    .replaceAll(RegExp(r'[\s\p{P}\p{S}]+', unicode: true), ' ')
    .trim();

/// [_titleKey] for other files: the same session imported twice.
String agendaTitleKey(String title) => _titleKey(title);

String _clip(String s, int max) => s.length <= max ? s : s.substring(0, max);

String? _nullIfEmpty(String s) => s.isEmpty ? null : s;

import '../models/activity.dart';
import '../models/planned_session.dart';
import 'agenda_parser.dart';

// Agenda preview and picking (ADR-082) [P2-07].

/// A session in the file that is already on the conference's agenda.
class AgendaDuplicate {
  const AgendaDuplicate(this.entry, this.existing);

  final AgendaEntry entry;
  final PlannedSession existing;
}

/// What an import would do, shown before anything is saved.
class AgendaImportPreview {
  const AgendaImportPreview({
    required this.fileName,
    required this.result,
    required this.toSave,
    required this.duplicates,
  });

  final String fileName;
  final AgendaParseResult result;

  /// New sessions: saved when the user confirms.
  final List<AgendaEntry> toSave;

  /// Sessions already on the agenda: left as they are.
  final List<AgendaDuplicate> duplicates;

  /// Sessions read from the file, new or not.
  int get found => result.entries.length;
  List<AgendaSkip> get skipped => result.skipped;
  List<String> get warnings => result.warnings;
}

/// Whether [entry] is [existing] imported again: the same ICS `UID`, or the
/// same title (ignoring case and punctuation) at the same start.
bool isSamePlannedSession(AgendaEntry entry, PlannedSession existing) {
  final uid = entry.uid;
  if (uid != null && uid == existing.sourceUid) return true;
  return entry.startUtc.isAtSameMomentAs(existing.startUtc) &&
      agendaTitleKey(entry.title) == agendaTitleKey(existing.title);
}

/// Splits [result] into new sessions and ones already in [existing].
AgendaImportPreview buildAgendaPreview({
  required String fileName,
  required AgendaParseResult result,
  required List<PlannedSession> existing,
}) {
  final toSave = <AgendaEntry>[];
  final duplicates = <AgendaDuplicate>[];
  for (final entry in result.entries) {
    PlannedSession? match;
    for (final p in existing) {
      if (isSamePlannedSession(entry, p)) {
        match = p;
        break;
      }
    }
    if (match == null) {
      toSave.add(entry);
    } else {
      duplicates.add(AgendaDuplicate(entry, match));
    }
  }
  return AgendaImportPreview(
    fileName: fileName,
    result: result,
    toSave: toSave,
    duplicates: duplicates,
  );
}

/// How long a session without an end counts as "on now".
const assumedSessionLength = Duration(minutes: 45);

/// Whether [session] is on at [nowUtc]. All-day sessions never are, so they
/// do not crowd the top of the list.
bool isPlannedSessionOnNow(PlannedSession session, DateTime nowUtc) {
  if (session.allDay) return false;
  final end = session.endUtc ?? session.startUtc.add(assumedSessionLength);
  return !nowUtc.isBefore(session.startUtc) && nowUtc.isBefore(end);
}

/// Sessions near [nowUtc] first (ADR-082): those on now, then the rest by
/// how far their start is from now, so the next session and the one that
/// just started come before tomorrow's. All-day sessions go last.
List<PlannedSession> orderByNearNow(
  List<PlannedSession> sessions,
  DateTime nowUtc,
) {
  int rank(PlannedSession s) {
    if (s.allDay) return 2;
    return isPlannedSessionOnNow(s, nowUtc) ? 0 : 1;
  }

  final sorted = [...sessions];
  sorted.sort((a, b) {
    final r = rank(a).compareTo(rank(b));
    if (r != 0) return r;
    final da = a.startUtc.difference(nowUtc).abs();
    final db = b.startUtc.difference(nowUtc).abs();
    final d = da.compareTo(db);
    if (d != 0) return d;
    return a.startUtc.compareTo(b.startUtc);
  });
  return sorted;
}

/// Words in an agenda's type column that mean a built-in type.
const _typeSynonyms = <String, String>{
  'talk': 'session',
  'presentation': 'session',
  'lecture': 'session',
  'session': 'session',
  'plenary': 'keynote',
  'keynote': 'keynote',
  'panel': 'panel',
  'panel discussion': 'panel',
  'discussion': 'panel',
  'fireside chat': 'panel',
  'breakout': 'breakout',
  'break out': 'breakout',
  'roundtable': 'breakout',
  'round table': 'breakout',
  'workshop': 'workshop',
  'tutorial': 'workshop',
  'masterclass': 'workshop',
  'lab': 'workshop',
  'hands on': 'workshop',
  'exhibit': 'exhibit',
  'exhibition': 'exhibit',
  'expo': 'exhibit',
  'demo': 'exhibit',
  'networking': 'networking',
  'reception': 'networking',
  'social': 'networking',
  'meetup': 'networking',
};

/// The activity type for an agenda's type text: a type whose label or key
/// matches (ignoring case), then a known synonym ("Talk" is a Session),
/// else Session. [types] must not be empty.
ActivityType matchActivityType(List<ActivityType> types, String? typeText) {
  String norm(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
  ActivityType? byKey(String key) {
    for (final t in types) {
      if (t.key == key) return t;
    }
    return null;
  }

  final fallback = byKey('session') ?? types.first;
  if (typeText == null || typeText.trim().isEmpty) return fallback;
  final text = norm(typeText);
  for (final t in types) {
    if (norm(t.label) == text || norm(t.key) == text) return t;
  }
  final synonym = _typeSynonyms[text];
  if (synonym != null) return byKey(synonym) ?? fallback;
  // "Keynote address", "Hands-on workshop": the first known word wins.
  for (final word in text.split(' ')) {
    final key = _typeSynonyms[word];
    if (key != null) return byKey(key) ?? fallback;
  }
  return fallback;
}

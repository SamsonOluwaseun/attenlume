import 'enums.dart';

/// Where a planned session came from (ADR-082) [P2-07].
enum AgendaSource implements KeyedEnum {
  csv('csv'),
  ics('ics');

  const AgendaSource(this.key);

  @override
  final String key;
}

/// A session on the conference agenda, imported from a CSV or ICS file
/// (ADR-082) [P2-07].
///
/// A planned session is not an activity: it holds no media and nothing is
/// recorded against it. Starting an activity "From the agenda" copies its
/// title, speakers, room, type and start time into a new activity.
class PlannedSession {
  const PlannedSession({
    required this.id,
    required this.conferenceId,
    required this.title,
    required this.speakerNames,
    this.room,
    this.typeText,
    this.description,
    required this.startUtc,
    this.endUtc,
    required this.allDay,
    required this.source,
    this.sourceUid,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String conferenceId;
  final String title;
  final List<String> speakerNames;
  final String? room;

  /// The session type as written in the file ("Keynote", "Workshop"). It is
  /// matched to an activity type when the session is picked.
  final String? typeText;
  final String? description;

  /// UTC. For an all-day session, midnight at the start of the day in the
  /// conference time zone.
  final DateTime startUtc;

  /// UTC, or null when the file gave no end. For an all-day session, the
  /// midnight that ends it (exclusive).
  final DateTime? endUtc;
  final bool allDay;
  final AgendaSource source;

  /// The ICS `UID`, used to spot the same event imported twice.
  final String? sourceUid;
  final DateTime createdAt;
  final DateTime updatedAt;
}

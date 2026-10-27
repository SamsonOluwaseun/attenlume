import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

bool _timeZonesLoaded = false;

/// Loads the bundled IANA timezone database once. Works offline.
void ensureTimeZonesLoaded() {
  if (_timeZonesLoaded) return;
  tzdata.initializeTimeZones();
  _timeZonesLoaded = true;
}

/// Converts [utc] to wall-clock time in the IANA [timezone].
///
/// An unknown timezone name falls back to UTC rather than failing, so a
/// damaged or foreign value never blocks creating an activity.
DateTime toConferenceTime(DateTime utc, String timezone) {
  ensureTimeZonesLoaded();
  final tz.Location location;
  try {
    location = tz.getLocation(timezone);
  } on tz.LocationNotFoundException {
    return utc.toUtc();
  }
  return tz.TZDateTime.from(utc, location);
}

/// The default activity title "{Type} {n}, {HH:mm}" (FR-ACT-05) [P0-09].
///
/// [ordinal] counts activities of this type in the conference, including the
/// new one. The time is local to the conference [timezone]
/// (PRODUCT_SPEC 5). Example: "Session 3, 14:05".
String defaultActivityTitle({
  required String typeLabel,
  required int ordinal,
  required DateTime atUtc,
  required String timezone,
}) {
  final local = toConferenceTime(atUtc, timezone);
  String two(int n) => n.toString().padLeft(2, '0');
  return '$typeLabel $ordinal, ${two(local.hour)}:${two(local.minute)}';
}

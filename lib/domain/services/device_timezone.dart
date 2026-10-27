import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/timezone.dart' as tz;

import 'activity_title.dart';

/// Service to detect and list available IANA timezones (FR-CONF-02).
class DeviceTimezoneService {
  const DeviceTimezoneService();

  static const String defaultFallbackTimezone = 'Europe/London';

  /// Detects the device's IANA timezone. Falls back safely to
  /// [defaultFallbackTimezone] if unavailable or unknown.
  Future<String> detectTimezone() async {
    ensureTimeZonesLoaded();
    try {
      final info = await FlutterTimezone.getLocalTimezone().timeout(
        const Duration(milliseconds: 500),
      );
      final detected = info.identifier;
      if (tz.timeZoneDatabase.locations.containsKey(detected)) {
        return detected;
      }
    } catch (_) {
      // Platform channels or unrecognized names fall back safely.
    }
    return defaultFallbackTimezone;
  }

  /// Sorted list of all available IANA timezones in the bundled database.
  List<String> getAvailableTimezones() {
    ensureTimeZonesLoaded();
    final list = tz.timeZoneDatabase.locations.keys.toList()..sort();
    return list;
  }

  /// Whether [timezone] is known to the bundled IANA database.
  bool isValidTimezone(String timezone) {
    ensureTimeZonesLoaded();
    return tz.timeZoneDatabase.locations.containsKey(timezone);
  }
}

final deviceTimezoneServiceProvider = Provider<DeviceTimezoneService>(
  (ref) => const DeviceTimezoneService(),
);

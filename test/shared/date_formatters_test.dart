import 'package:attenlume/shared/utilities/date_formatters.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Date and time formatters [FR-ACT-01, FR-ACT-03]', () {
    test('formatDuration formats zero, minutes, hours and combined', () {
      expect(formatDuration(Duration.zero), '0 min');
      expect(formatDuration(const Duration(seconds: 30)), '< 1 min');
      expect(formatDuration(const Duration(minutes: 1)), '1 min');
      expect(formatDuration(const Duration(minutes: 47)), '47 min');
      expect(formatDuration(const Duration(hours: 1)), '1 h');
      expect(
        formatDuration(const Duration(hours: 2, minutes: 15)),
        '2 h 15 min',
      );
    });

    test('FR-BMK-01 formatOffset shows m:ss, h:mm:ss and before start', () {
      expect(formatOffset(0), '0:00');
      expect(formatOffset(245000), '4:05');
      expect(formatOffset(245999), '4:05');
      expect(formatOffset(3725000), '1:02:05');
      expect(formatOffset(-12000), '-0:12');
    });

    test('formatStorageBytes formats bytes, KB, MB and GB', () {
      expect(formatStorageBytes(0), '0 B');
      expect(formatStorageBytes(512), '512 B');
      expect(formatStorageBytes(1024), '1.0 KB');
      expect(formatStorageBytes(350 * 1024), '350.0 KB');
      expect(formatStorageBytes(10 * 1024 * 1024), '10 MB');
      expect(formatStorageBytes(14 * 1024 * 1024 + 200 * 1024), '14.2 MB');
      expect(formatStorageBytes(2 * 1024 * 1024 * 1024), '2.0 GB');
    });

    test(
      'formatTimeOfDayInTimezone formats UTC into conference local HH:mm',
      () {
        final utc = DateTime.utc(2026, 11, 4, 9, 30);
        expect(formatTimeOfDayInTimezone(utc, 'Europe/London'), '09:30');

        // Tokyo is UTC+9
        expect(formatTimeOfDayInTimezone(utc, 'Asia/Tokyo'), '18:30');

        // New York in November is EST (UTC-5)
        expect(formatTimeOfDayInTimezone(utc, 'America/New_York'), '04:30');
      },
    );
  });
}

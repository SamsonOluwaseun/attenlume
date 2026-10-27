import 'package:attenlume/domain/services/device_timezone.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const service = DeviceTimezoneService();

  test(
    'FR-CONF-02 detectTimezone falls back safely to a valid IANA timezone',
    () async {
      final tz = await service.detectTimezone();
      expect(tz, isNotEmpty);
      expect(service.isValidTimezone(tz), isTrue);
    },
  );

  test(
    'FR-CONF-02 getAvailableTimezones returns sorted non-empty IANA list',
    () {
      final list = service.getAvailableTimezones();
      expect(list, isNotEmpty);
      expect(list.contains('Europe/London'), isTrue);
      expect(list.contains('America/New_York'), isTrue);
      expect(list.contains('Asia/Tokyo'), isTrue);
      expect(list.contains('Etc/UTC'), isTrue);

      // Verify sorted
      final copy = List<String>.from(list)..sort();
      expect(list, equals(copy));
    },
  );

  test('FR-CONF-02 isValidTimezone validates known and rejects unknown', () {
    expect(service.isValidTimezone('Europe/London'), isTrue);
    expect(service.isValidTimezone('Invalid/Nonexistent_Timezone'), isFalse);
  });
}

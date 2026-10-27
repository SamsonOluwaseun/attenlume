import 'package:attenlume/platform/diagnostics/method_channel_battery_probe.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.samlytics.attenlume/battery');
  void answer(Object? Function(MethodCall call) reply) =>
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async => reply(call));

  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );

  test(
    'FR-REC-06 reads percent and charging from the Android channel',
    () async {
      String? method;
      answer((call) {
        method = call.method;
        return {'percent': 14, 'charging': false};
      });

      final reading = await const MethodChannelBatteryProbe().read();

      expect(method, 'readBattery');
      expect(reading!.percent, 14);
      expect(reading.charging, isFalse);
    },
  );

  test('FR-REC-06 unknown when the platform answers null or fails', () async {
    answer((_) => null);
    expect(await const MethodChannelBatteryProbe().read(), isNull);

    answer((_) => throw PlatformException(code: 'boom'));
    expect(await const MethodChannelBatteryProbe().read(), isNull);
  });
}

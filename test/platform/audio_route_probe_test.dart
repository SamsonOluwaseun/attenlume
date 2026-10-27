// The mapping under test uses audio_session's experimental AudioDeviceType.
// ignore_for_file: experimental_member_use

import 'package:attenlume/platform/audio_capture/audio_capture_engine.dart';
import 'package:attenlume/platform/audio_route/audio_route_probe.dart';
import 'package:attenlume/platform/audio_route/audio_session_route_probe.dart';
import 'package:attenlume/platform/audio_route/engine_route_probe.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fixtures/fake_capture_engine.dart';

void main() {
  group('P0-07 input route kinds', () {
    test('P0-07 Android device types map to route kinds', () {
      const expected = {
        AudioDeviceType.builtInMic: InputRouteKind.builtIn,
        AudioDeviceType.wiredHeadset: InputRouteKind.wired,
        AudioDeviceType.bluetoothSco: InputRouteKind.bluetooth,
        AudioDeviceType.bluetoothLe: InputRouteKind.bluetooth,
        AudioDeviceType.usbAudio: InputRouteKind.usb,
        AudioDeviceType.telephony: InputRouteKind.other,
        AudioDeviceType.unknown: InputRouteKind.unknown,
      };
      for (final e in expected.entries) {
        expect(
          AudioSessionRouteProbe.kindOfDevice(e.key),
          e.value,
          reason: e.key.name,
        );
      }
    });

    test('P0-07 iOS ports map to route kinds', () {
      const expected = {
        AVAudioSessionPort.builtInMic: InputRouteKind.builtIn,
        AVAudioSessionPort.headsetMic: InputRouteKind.wired,
        AVAudioSessionPort.bluetoothHfp: InputRouteKind.bluetooth,
        AVAudioSessionPort.usbAudio: InputRouteKind.usb,
        AVAudioSessionPort.carAudio: InputRouteKind.other,
      };
      for (final e in expected.entries) {
        expect(
          AudioSessionRouteProbe.kindOfPort(e.key),
          e.value,
          reason: e.key.name,
        );
      }
    });

    test('P0-07 Windows names are classified, unknown names stay other', () {
      expect(
        classifyInputLabel('Headset (Jabra Evolve2 Hands-Free AG Audio)'),
        InputRouteKind.bluetooth,
      );
      expect(
        classifyInputLabel('Microphone (2- USB Audio Device)'),
        InputRouteKind.usb,
      );
      expect(
        classifyInputLabel('Microphone Array (Realtek(R) Audio)'),
        InputRouteKind.builtIn,
      );
      expect(classifyInputLabel('Stereo Mix'), InputRouteKind.other);
    });
  });

  group('P0-07 FR-QUAL-06 route key', () {
    test('P0-07 the stored key names the kind and the label', () {
      const route = InputRoute(
        id: 'x',
        label: 'AirPods Pro',
        kind: InputRouteKind.bluetooth,
      );
      expect(route.key, 'bluetooth: AirPods Pro');
      expect(
        route,
        const InputRoute(
          id: 'x',
          label: 'AirPods Pro',
          kind: InputRouteKind.bluetooth,
        ),
      );
    });

    test('P0-07 the engine probe lists inputs and never claims an active '
        'one', () async {
      final engine = FakeCaptureEngine()
        ..inputs = const [
          CaptureInput(id: '{a}', label: 'Microphone Array (Realtek Audio)'),
          CaptureInput(id: '{b}', label: 'Headset (Lapel Mic Hands-Free)'),
        ];
      final probe = EngineRouteProbe(engine);

      final inputs = await probe.availableInputs();

      expect(inputs.map((r) => r.kind), [
        InputRouteKind.builtIn,
        InputRouteKind.bluetooth,
      ]);
      expect(await probe.activeInput(), isNull);
    });
  });
}

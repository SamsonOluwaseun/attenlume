// audio_session marks AudioDeviceType experimental. The version is pinned
// (0.2.4) and the mapping is unit tested, so a change shows up as a
// failing test, not a silent mislabel.
// ignore_for_file: experimental_member_use

import 'dart:io';

import 'package:audio_session/audio_session.dart';

import 'audio_route_probe.dart';

/// [AudioRouteProbe] for Android and iOS through `audio_session` 0.2.4
/// (ADR-013, ADR-016) [P0-07].
///
/// iOS reads `AVAudioSession.currentRoute.inputs`, which is the input the
/// OS really uses. Android only lists the inputs that exist: the routed
/// device of the recorder (`AudioRecord.getRoutedDevice`) is not exposed
/// by `audio_session` or `record`, so [activeInput] is null there until
/// P1-07 adds a channel.
///
/// Unverified on every device: needs MT-20.
class AudioSessionRouteProbe implements AudioRouteProbe {
  AudioSessionRouteProbe({bool? isIos}) : _isIos = isIos ?? Platform.isIOS;

  final bool _isIos;

  @override
  Future<InputRoute?> activeInput() async {
    if (!_isIos) return null;
    final route = await AVAudioSession().currentRoute;
    final port = route.inputs.firstOrNull;
    return port == null
        ? null
        : fromDarwinPort(port.uid, port.portName, port.portType);
  }

  @override
  Future<List<InputRoute>> availableInputs() async {
    final session = await AudioSession.instance;
    final devices = await session.getDevices(includeOutputs: false);
    return [
      for (final d in devices)
        if (d.isInput) fromDevice(d.id, d.name, d.type),
    ];
  }

  static InputRoute fromDevice(String id, String name, AudioDeviceType type) =>
      InputRoute(id: id, label: name, kind: kindOfDevice(type));

  static InputRoute fromDarwinPort(
    String uid,
    String name,
    AVAudioSessionPort port,
  ) => InputRoute(id: uid, label: name, kind: kindOfPort(port));

  static InputRouteKind kindOfDevice(AudioDeviceType type) => switch (type) {
    AudioDeviceType.builtInMic => InputRouteKind.builtIn,
    AudioDeviceType.wiredHeadset ||
    AudioDeviceType.headsetMic ||
    AudioDeviceType.lineAnalog ||
    AudioDeviceType.lineDigital ||
    AudioDeviceType.auxLine => InputRouteKind.wired,
    AudioDeviceType.bluetoothSco ||
    AudioDeviceType.bluetoothA2dp ||
    AudioDeviceType.bluetoothLe ||
    AudioDeviceType.hearingAid => InputRouteKind.bluetooth,
    AudioDeviceType.usbAudio => InputRouteKind.usb,
    AudioDeviceType.unknown => InputRouteKind.unknown,
    _ => InputRouteKind.other,
  };

  static InputRouteKind kindOfPort(AVAudioSessionPort port) => switch (port) {
    AVAudioSessionPort.builtInMic => InputRouteKind.builtIn,
    AVAudioSessionPort.headsetMic ||
    AVAudioSessionPort.lineIn => InputRouteKind.wired,
    AVAudioSessionPort.bluetoothHfp ||
    AVAudioSessionPort.bluetoothLe ||
    AVAudioSessionPort.bluetoothA2dp => InputRouteKind.bluetooth,
    AVAudioSessionPort.usbAudio => InputRouteKind.usb,
    _ => InputRouteKind.other,
  };
}

import 'package:attenlume/platform/audio_route/audio_route_probe.dart';

/// An [AudioRouteProbe] for tests [P0-07]. Set [active] and [available]
/// to move the "headset" around.
class FakeRouteProbe implements AudioRouteProbe {
  InputRoute? active;
  List<InputRoute> available = const [];

  /// When set, both calls throw it.
  Object? error;
  int activeCalls = 0;

  @override
  Future<InputRoute?> activeInput() async {
    activeCalls++;
    if (error != null) throw error!;
    return active;
  }

  @override
  Future<List<InputRoute>> availableInputs() async {
    if (error != null) throw error!;
    return available;
  }
}

const builtInMic = InputRoute(
  id: 'mic-0',
  label: 'iPhone Microphone',
  kind: InputRouteKind.builtIn,
);

const headset = InputRoute(
  id: 'bt-1',
  label: 'Lapel Mic',
  kind: InputRouteKind.bluetooth,
);

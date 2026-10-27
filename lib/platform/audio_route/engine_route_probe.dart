import '../audio_capture/audio_capture_engine.dart';
import 'audio_route_probe.dart';

/// [AudioRouteProbe] from the capture engine's device list, for Windows
/// (ADR-016) [P0-07].
///
/// `record_windows` lists inputs by name but does not say which one the
/// system default is, so [activeInput] is null and the kind is guessed
/// from the name.
class EngineRouteProbe implements AudioRouteProbe {
  const EngineRouteProbe(this._engine);

  final AudioCaptureEngine _engine;

  @override
  Future<InputRoute?> activeInput() async => null;

  @override
  Future<List<InputRoute>> availableInputs() async => [
    for (final input in await _engine.listInputs())
      InputRoute(
        id: input.id,
        label: input.label,
        kind: classifyInputLabel(input.label),
      ),
  ];
}

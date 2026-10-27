import 'dart:async';

import 'package:attenlume/platform/interruptions/audio_interruption_source.dart';

/// An [AudioInterruptionSource] whose events the test sends [P1-07].
class FakeInterruptionSource implements AudioInterruptionSource {
  final _controller = StreamController<AudioInterruption>.broadcast();
  bool active = false;
  int activations = 0;
  int deactivations = 0;
  Object? activateError;

  @override
  Future<void> activate() async {
    activations++;
    if (activateError != null) throw activateError!;
    active = true;
  }

  @override
  Future<void> deactivate() async {
    deactivations++;
    active = false;
  }

  @override
  Stream<AudioInterruption> get events => _controller.stream;

  void began({bool mayDuck = false}) => _controller.add(
    AudioInterruption(AudioInterruptionKind.began, mayDuck: mayDuck),
  );

  void ended({required bool shouldResume}) => _controller.add(
    AudioInterruption(AudioInterruptionKind.ended, shouldResume: shouldResume),
  );

  void devicesChanged() => _controller.add(
    const AudioInterruption(AudioInterruptionKind.devicesChanged),
  );

  void becomingNoisy() => _controller.add(
    const AudioInterruption(AudioInterruptionKind.becomingNoisy),
  );

  Future<void> close() => _controller.close();
}

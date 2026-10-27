import 'dart:async';

import 'package:audio_session/audio_session.dart';

import 'audio_interruption_source.dart';

/// [AudioInterruptionSource] backed by `audio_session` on Android and iOS
/// (ADR-002, ADR-013) [P0-04].
///
/// iOS: category `playAndRecord`, mode `default`, Bluetooth input allowed,
/// so recording carries on when the screen locks (`UIBackgroundModes:
/// audio`). Android: speech attributes with full audio focus, so a ringing
/// call takes focus and shows up as an interruption.
///
/// Unverified on every device: needs P0-04 manual runs.
class AudioSessionInterruptionSource implements AudioInterruptionSource {
  AudioSessionInterruptionSource();

  static final recordingConfiguration = AudioSessionConfiguration(
    avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
    avAudioSessionCategoryOptions:
        AVAudioSessionCategoryOptions.allowBluetooth |
        AVAudioSessionCategoryOptions.defaultToSpeaker,
    avAudioSessionMode: AVAudioSessionMode.defaultMode,
    androidAudioAttributes: const AndroidAudioAttributes(
      contentType: AndroidAudioContentType.speech,
      usage: AndroidAudioUsage.media,
    ),
    androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
  );

  final _controller = StreamController<AudioInterruption>.broadcast();
  final _subscriptions = <StreamSubscription<Object?>>[];
  AudioSession? _session;

  @override
  Stream<AudioInterruption> get events => _controller.stream;

  @override
  Future<void> activate() async {
    final session = _session ??= await _open();
    await session.configure(recordingConfiguration);
    await session.setActive(true);
  }

  @override
  Future<void> deactivate() async {
    await _session?.setActive(false);
  }

  Future<AudioSession> _open() async {
    final session = await AudioSession.instance;
    _subscriptions
      ..add(session.interruptionEventStream.listen(_onInterruption))
      ..add(
        session.becomingNoisyEventStream.listen(
          (_) => _controller.add(
            const AudioInterruption(AudioInterruptionKind.becomingNoisy),
          ),
        ),
      )
      ..add(
        session.devicesChangedEventStream.listen(
          (e) => _controller.add(
            AudioInterruption(
              AudioInterruptionKind.devicesChanged,
              devicesAdded: [for (final d in e.devicesAdded) _label(d)],
              devicesRemoved: [for (final d in e.devicesRemoved) _label(d)],
            ),
          ),
        ),
      );
    return session;
  }

  // audio_session reports an ended interruption of type `pause` when the
  // system allows the app to resume, and `unknown` when it does not.
  void _onInterruption(AudioInterruptionEvent e) => _controller.add(
    e.begin
        ? AudioInterruption(
            AudioInterruptionKind.began,
            mayDuck: e.type == AudioInterruptionType.duck,
          )
        : AudioInterruption(
            AudioInterruptionKind.ended,
            shouldResume: e.type != AudioInterruptionType.unknown,
          ),
  );

  static String _label(AudioDevice d) =>
      '${d.name} (${d.type.name}${d.isInput ? ', input' : ''})';
}

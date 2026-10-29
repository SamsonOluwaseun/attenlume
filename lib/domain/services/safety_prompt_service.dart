import 'dart:async';

import '../../platform/diagnostics/battery_probe.dart';
import 'recording_service.dart';
import 'recording_state.dart';

/// Thresholds for the safety prompts (FR-REC-06) [P1-13]. Defaults from
/// the build guide; Settings changes them (5.11, P1-25, ADR-048).
class SafetyThresholds {
  const SafetyThresholds({
    this.longRecording = const Duration(hours: 2),
    this.silence = const Duration(minutes: 10),
    this.silenceDbfs = -55,
    this.lowBatteryPercent = 15,
  });

  /// Prompt after this much recording, then again after each further
  /// period of the same length.
  final Duration longRecording;

  /// Prompt after this long with no level above [silenceDbfs].
  final Duration silence;

  /// Below this the input counts as near-silence. Quiet rooms sit around
  /// -60 to -50 dBFS, speech well above -40.
  final double silenceDbfs;

  /// Prompt when the battery drops below this and is not charging.
  final int lowBatteryPercent;
}

enum SafetyPromptKind { longRecording, silence, lowBattery }

class SafetyPrompt {
  const SafetyPrompt({
    required this.kind,
    required this.activityId,
    this.elapsed,
    this.batteryPercent,
  });

  final SafetyPromptKind kind;
  final String activityId;

  /// How long the recording has run, for [SafetyPromptKind.longRecording].
  final Duration? elapsed;

  /// For [SafetyPromptKind.lowBattery].
  final int? batteryPercent;

  @override
  String toString() => 'SafetyPrompt(${kind.name}, $activityId)';
}

/// Watches a running recording and raises safety prompts: still recording
/// after 2 hours, 10 minutes of near-silence, battery below 15 %
/// (FR-REC-06) [P1-13].
///
/// Prompts never stop or pause the recording. Storage has its own checks
/// and the only automatic stop (StorageBudgetService, FR-STO-04).
class SafetyPromptService {
  SafetyPromptService({
    required this.recorder,
    required this._level,
    required this.battery,
    this.thresholds = const SafetyThresholds(),
    this.tickInterval = const Duration(seconds: 5),
    this.batteryEvery = 12,
    Timer Function(Duration, void Function(Timer))? createTimer,
    DateTime Function()? clock,
  }) : _createTimer = createTimer ?? Timer.periodic,
       clock = clock ?? (() => DateTime.now().toUtc());

  final RecordingService recorder;
  final BatteryProbe battery;

  /// Read on every check, so a change in Settings applies to the
  /// recording already running (5.11, ADR-048).
  SafetyThresholds thresholds;
  final Duration tickInterval;

  /// Read the battery once every this many ticks (once a minute).
  final int batteryEvery;
  final DateTime Function() clock;
  final Future<double> Function() _level;
  final Timer Function(Duration, void Function(Timer)) _createTimer;

  final _prompts = StreamController<SafetyPrompt>.broadcast();
  StreamSubscription<RecordingStatus>? _statusSub;
  Timer? _timer;
  bool _checking = false;
  int _ticks = 0;

  String? _activityId;
  Duration _recorded = Duration.zero;
  DateTime? _runningSince;
  DateTime? _lastSound;
  bool _silencePrompted = false;
  bool _batteryPrompted = false;
  int _longPrompts = 0;

  Stream<SafetyPrompt> get prompts => _prompts.stream;

  void start() {
    _statusSub ??= recorder.statusStream.listen(_onStatus);
    _onStatus(recorder.status);
  }

  void _onStatus(RecordingStatus status) {
    final activityId = status.activityId;
    final holds = status.state.holdsActivity;
    if (!holds || activityId != _activityId) _reset(holds ? activityId : null);

    if (status.state == RecordingState.recording) {
      if (_runningSince == null) {
        final now = clock();
        _runningSince = now;
        // Silence is only counted while audio is being written.
        _lastSound = now;
      }
      _timer ??= _createTimer(tickInterval, (_) => unawaited(check()));
    } else {
      _pauseClock();
      _timer?.cancel();
      _timer = null;
    }
  }

  void _reset(String? activityId) {
    _activityId = activityId;
    _recorded = Duration.zero;
    _runningSince = null;
    _lastSound = null;
    _silencePrompted = false;
    _batteryPrompted = false;
    _longPrompts = 0;
    _ticks = 0;
  }

  void _pauseClock() {
    final since = _runningSince;
    if (since != null) _recorded += clock().difference(since);
    _runningSince = null;
  }

  /// Time spent recording in this session, pauses excluded.
  Duration get recordedTime {
    final since = _runningSince;
    return since == null ? _recorded : _recorded + clock().difference(since);
  }

  /// Runs one round of checks. Public for tests and for callers that want
  /// an immediate check.
  Future<void> check() async {
    final activityId = _activityId;
    if (_checking ||
        activityId == null ||
        recorder.status.state != RecordingState.recording) {
      return;
    }
    _checking = true;
    try {
      final now = clock();

      final elapsed = recordedTime;
      final due = thresholds.longRecording * (_longPrompts + 1);
      if (elapsed >= due) {
        _longPrompts =
            elapsed.inMicroseconds ~/ thresholds.longRecording.inMicroseconds;
        _emit(
          SafetyPrompt(
            kind: SafetyPromptKind.longRecording,
            activityId: activityId,
            elapsed: elapsed,
          ),
        );
      }

      double? level;
      try {
        level = await _level();
      } on Object {
        level = null;
      }
      if (level != null && level > thresholds.silenceDbfs) {
        _lastSound = now;
        _silencePrompted = false;
      } else {
        final lastSound = _lastSound ?? now;
        if (!_silencePrompted &&
            now.difference(lastSound) >= thresholds.silence) {
          _silencePrompted = true;
          _emit(
            SafetyPrompt(
              kind: SafetyPromptKind.silence,
              activityId: activityId,
            ),
          );
        }
      }

      if (!_batteryPrompted && _ticks % batteryEvery == 0) {
        final reading = await battery.read();
        if (reading != null &&
            !reading.charging &&
            reading.percent < thresholds.lowBatteryPercent) {
          _batteryPrompted = true;
          _emit(
            SafetyPrompt(
              kind: SafetyPromptKind.lowBattery,
              activityId: activityId,
              batteryPercent: reading.percent,
            ),
          );
        }
      }
      _ticks++;
    } finally {
      _checking = false;
    }
  }

  void _emit(SafetyPrompt prompt) {
    if (!_prompts.isClosed) _prompts.add(prompt);
  }

  Future<void> dispose() async {
    _timer?.cancel();
    _timer = null;
    await _statusSub?.cancel();
    _statusSub = null;
    await _prompts.close();
  }
}

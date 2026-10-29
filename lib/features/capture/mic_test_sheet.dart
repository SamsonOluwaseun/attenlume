import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/tokens.dart';
import '../../domain/models/enums.dart';
import '../../domain/services/capture_settings.dart';
import '../../platform/audio_capture/audio_capture_engine.dart';
import 'level_meter.dart';
import 'recording_providers.dart';

/// 10-second microphone test sheet (FR-UI-06).
///
/// Runs a 10-second live capture test, displays live audio levels,
/// and determines whether the microphone has an active signal or a flat
/// (muted/blocked) signal.
class MicTestSheet extends ConsumerStatefulWidget {
  const MicTestSheet({
    super.key,
    this.testDuration = const Duration(seconds: 10),
    this.sampleInterval = const Duration(milliseconds: 200),
  });

  final Duration testDuration;
  final Duration sampleInterval;

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const MicTestSheet(),
    );
  }

  @override
  ConsumerState<MicTestSheet> createState() => _MicTestSheetState();
}

class _MicTestSheetState extends ConsumerState<MicTestSheet> {
  Timer? _countdownTimer;
  Timer? _sampleTimer;

  bool _isRunning = false;
  bool _isFinished = false;
  int _secondsLeft = 10;
  double _currentLevelDbfs = -90.0;
  final List<double> _sampledLevels = [];
  String? _errorMessage;
  String? _tempTestPath;
  bool _startedEngineDirectly = false;

  @override
  void initState() {
    super.initState();
    _secondsLeft = widget.testDuration.inSeconds;
    // Auto-start test on sheet open
    WidgetsBinding.instance.addPostFrameCallback((_) => _startTest());
  }

  @override
  void dispose() {
    _cleanupTimers();
    _cleanupTempCapture();
    super.dispose();
  }

  void _cleanupTimers() {
    _countdownTimer?.cancel();
    _sampleTimer?.cancel();
  }

  Future<void> _cleanupTempCapture() async {
    if (_startedEngineDirectly) {
      try {
        final engine = ref.read(audioCaptureEngineProvider);
        await engine.stop();
      } catch (_) {}
      _startedEngineDirectly = false;
    }
    if (_tempTestPath != null) {
      try {
        final file = File(_tempTestPath!);
        if (file.existsSync()) {
          file.deleteSync();
        }
      } catch (_) {}
      _tempTestPath = null;
    }
  }

  Future<void> _startTest() async {
    _cleanupTimers();
    await _cleanupTempCapture();

    if (!mounted) return;

    setState(() {
      _isRunning = true;
      _isFinished = false;
      _secondsLeft = widget.testDuration.inSeconds;
      _sampledLevels.clear();
      _errorMessage = null;
      _currentLevelDbfs = -90.0;
    });

    final recordingService = ref.read(recordingServiceProvider);
    final engine = ref.read(audioCaptureEngineProvider);
    final platform = ref.read(capturePlatformProvider);

    // If an active recording is not holding the engine, start a temp test capture
    if (!recordingService.status.state.holdsActivity) {
      try {
        final tempDir = Directory.systemTemp;
        _tempTestPath =
            '${tempDir.path}${Platform.pathSeparator}attenlume_mic_test_${DateTime.now().millisecondsSinceEpoch}.m4a';
        final effective = effectiveCaptureSettings(
          RecordingProfile.balanced,
          platform,
        );
        final request = CaptureRequest(
          bitrateBps: effective.bitrateBps,
          sampleRateHz: effective.sampleRateHz,
          channelCount: effective.channelCount,
        );
        if (!await engine.hasPermission()) {
          if (!mounted) return;
          setState(() {
            _isRunning = false;
            _isFinished = true;
            _errorMessage =
                'Attenlume needs microphone access. Allow it in your '
                'device settings, then test again.';
          });
          return;
        }
        await engine.start(request, _tempTestPath!);
        _startedEngineDirectly = true;
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _isRunning = false;
          _isFinished = true;
          _errorMessage = "Couldn't access microphone: $e";
        });
        return;
      }
    }

    _sampleTimer = Timer.periodic(widget.sampleInterval, (timer) async {
      try {
        final level = await engine.levelDbfs();
        if (mounted) {
          setState(() {
            _currentLevelDbfs = level;
            _sampledLevels.add(level);
          });
        }
      } catch (_) {}
    });

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_secondsLeft <= 1) {
        timer.cancel();
        unawaited(_finishTest());
      } else {
        setState(() => _secondsLeft--);
      }
    });
  }

  Future<void> _finishTest() async {
    _cleanupTimers();
    await _cleanupTempCapture();

    if (!mounted) return;
    setState(() {
      _isRunning = false;
      _isFinished = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final attenlume = theme.extension<AttenlumeColors>();

    final liveSurface = attenlume?.liveSurface ?? const Color(0xFF00212B);
    final liveRaised = attenlume?.liveRaised ?? const Color(0xFF0E3542);
    final onLiveSurface = attenlume?.onLiveSurface ?? const Color(0xFFFEFFF8);
    final onLiveSurfaceMuted =
        attenlume?.onLiveSurfaceMuted ?? const Color(0xFF9FB3B8);
    final live = attenlume?.live ?? const Color(0xFFDCFF38);
    final warningFill = attenlume?.warningFill ?? const Color(0xFFFFF4C2);

    final maxLevel = _sampledLevels.isEmpty
        ? -90.0
        : _sampledLevels.reduce(math.max);
    // Flat signal threshold: if maximum level is below -70.0 dBFS
    final isFlatSignal = maxLevel <= -70.0;

    return Theme(
      data: AppTheme.live(),
      child: SafeArea(
        child: Container(
          padding: const EdgeInsets.all(TokenSpace.space4),
          decoration: BoxDecoration(
            color: liveSurface,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(TokenRadius.radiusLg),
            ),
          ),
          // Scrolls at large text sizes (NFR-09).
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                Row(
                  children: [
                    Icon(Icons.mic_rounded, size: 24, color: onLiveSurface),
                    const SizedBox(width: TokenSpace.space2),
                    Expanded(
                      child: Semantics(
                        header: true,
                        child: Text(
                          '10-Second Microphone Test',
                          style: TextStyle(
                            fontFamily: TokenType.fontFamily,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: onLiveSurface,
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      key: const Key('mic-test-close-button'),
                      icon: Icon(
                        Icons.close_rounded,
                        color: onLiveSurfaceMuted,
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),

                const SizedBox(height: TokenSpace.space3),

                if (_errorMessage != null) ...[
                  Container(
                    padding: const EdgeInsets.all(TokenSpace.space3),
                    decoration: BoxDecoration(
                      color: warningFill.withValues(alpha: 0.15),
                      borderRadius: const BorderRadius.all(
                        Radius.circular(TokenRadius.radiusMd),
                      ),
                      border: Border.all(color: warningFill),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          color: onLiveSurface,
                          size: 20,
                        ),
                        const SizedBox(width: TokenSpace.space2),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: TextStyle(
                              fontFamily: TokenType.fontFamily,
                              fontSize: 14,
                              color: onLiveSurface,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: TokenSpace.space4),
                ] else if (_isRunning) ...[
                  Text(
                    'Speak into your microphone now to test audio input levels.',
                    style: TextStyle(
                      fontFamily: TokenType.fontFamily,
                      fontSize: 14,
                      color: onLiveSurfaceMuted,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: TokenSpace.space4),

                  // Countdown Timer
                  Center(
                    child: Text(
                      '00:${_secondsLeft.toString().padLeft(2, '0')}',
                      key: const Key('mic-test-countdown'),
                      style:
                          (attenlume?.timer ??
                                  const TextStyle(
                                    fontSize: 48,
                                    fontWeight: FontWeight.bold,
                                  ))
                              .copyWith(
                                color: live,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                    ),
                  ),
                  const SizedBox(height: TokenSpace.space3),

                  // Live level meter
                  LevelMeter(
                    key: const Key('mic-test-level-meter'),
                    levelDbfs: _currentLevelDbfs,
                    isRecording: true,
                    isPaused: false,
                  ),
                  const SizedBox(height: TokenSpace.space4),
                ] else if (_isFinished) ...[
                  Container(
                    padding: const EdgeInsets.all(TokenSpace.space3),
                    decoration: BoxDecoration(
                      color: liveRaised,
                      borderRadius: const BorderRadius.all(
                        Radius.circular(TokenRadius.radiusMd),
                      ),
                      border: Border.all(
                        color: isFlatSignal ? warningFill : live,
                        width: 1.5,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          isFlatSignal
                              ? Icons.volume_off_rounded
                              : Icons.check_circle_outline_rounded,
                          color: isFlatSignal ? warningFill : live,
                          size: 28,
                        ),
                        const SizedBox(width: TokenSpace.space3),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                isFlatSignal
                                    ? 'Flat signal detected'
                                    : 'Microphone working',
                                key: const Key('mic-test-result-title'),
                                style: TextStyle(
                                  fontFamily: TokenType.fontFamily,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: onLiveSurface,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                isFlatSignal
                                    ? 'No audio detected. Check microphone privacy switch, volume or permissions.'
                                    : 'Audio signal received clearly (peak: ${maxLevel.toStringAsFixed(1)} dBFS).',
                                key: const Key('mic-test-result-message'),
                                style: TextStyle(
                                  fontFamily: TokenType.fontFamily,
                                  fontSize: 13,
                                  color: onLiveSurfaceMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: TokenSpace.space4),
                ],

                // Actions
                Row(
                  children: [
                    if (_isRunning)
                      Expanded(
                        child: OutlinedButton(
                          key: const Key('mic-test-cancel-button'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: onLiveSurface,
                            side: BorderSide(color: onLiveSurfaceMuted),
                          ),
                          onPressed: _finishTest,
                          child: const Text('Cancel test'),
                        ),
                      )
                    else ...[
                      Expanded(
                        child: OutlinedButton(
                          key: const Key('mic-test-retry-button'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: onLiveSurface,
                            side: BorderSide(color: onLiveSurfaceMuted),
                          ),
                          onPressed: _startTest,
                          child: const Text('Test again'),
                        ),
                      ),
                      const SizedBox(width: TokenSpace.space3),
                      Expanded(
                        child: FilledButton(
                          key: const Key('mic-test-done-button'),
                          style: FilledButton.styleFrom(
                            backgroundColor:
                                attenlume?.surfaceBrand ??
                                const Color(0xFF4392F1),
                            foregroundColor:
                                attenlume?.onBrandLarge ??
                                const Color(0xFFFEFFF8),
                          ),
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Done'),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

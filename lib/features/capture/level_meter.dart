import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/tokens.dart';

/// Live level waveform visualizer for the recording screen (FR-UI-01, FR-UI-06).
///
/// Draws audio level bars in lime (`live`) while recording, paused with the
/// recording, and respecting the OS "reduce motion" setting.
class LevelMeter extends StatelessWidget {
  const LevelMeter({
    super.key,
    this.levelDbfs = -60.0,
    this.isRecording = false,
    this.isPaused = false,
    this.barCount = 28,
    this.height = 48.0,
  });

  /// Current input level in dBFS (typically -90.0 to 0.0 dBFS).
  final double levelDbfs;

  /// Whether audio is actively capturing.
  final bool isRecording;

  /// Whether capture is paused.
  final bool isPaused;

  /// Number of vertical waveform bars to render.
  final int barCount;

  /// Overall height of the waveform visualizer.
  final double height;

  /// Converts dBFS to normalized [0.0, 1.0] level.
  /// Anything <= -60 dBFS is considered silence (0.0).
  /// 0 dBFS is peak (1.0).
  static double normalizeDbfs(double dbfs) {
    if (dbfs.isNaN || dbfs.isInfinite || dbfs <= -60.0) return 0.0;
    if (dbfs >= 0.0) return 1.0;
    // Linear interpolation between -60 dBFS and 0 dBFS.
    return ((dbfs + 60.0) / 60.0).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final attenlume = theme.extension<AttenlumeColors>();
    final reduceMotion = MediaQuery.of(context).disableAnimations;

    final norm = normalizeDbfs(levelDbfs);
    final active = isRecording && !isPaused;

    final barColor = active
        ? (attenlume?.live ?? const Color(0xFFDCFF38))
        : (attenlume?.onLiveSurfaceMuted ?? const Color(0xFF9FB3B8));

    final percentInt = (norm * 100).round();
    final semanticText = active
        ? 'Microphone level $percentInt percent'
        : (isPaused ? 'Microphone paused' : 'Microphone idle');

    if (reduceMotion) {
      // Accessible static level bar when reduce motion is enabled
      return Semantics(
        label: semanticText,
        child: Container(
          height: 12,
          constraints: const BoxConstraints(maxWidth: 320),
          decoration: BoxDecoration(
            color: attenlume?.liveRaised ?? const Color(0xFF0E3542),
            borderRadius: const BorderRadius.all(
              Radius.circular(TokenRadius.radiusPill),
            ),
          ),
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: active ? math.max(0.04, norm) : 0.04,
            child: Container(
              decoration: BoxDecoration(
                color: barColor,
                borderRadius: const BorderRadius.all(
                  Radius.circular(TokenRadius.radiusPill),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Semantics(
      label: semanticText,
      child: SizedBox(
        height: height,
        child: CustomPaint(
          size: Size(double.infinity, height),
          painter: _WaveformPainter(
            normalizedLevel: norm,
            active: active,
            barCount: barCount,
            color: barColor,
          ),
        ),
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  _WaveformPainter({
    required this.normalizedLevel,
    required this.active,
    required this.barCount,
    required this.color,
  });

  final double normalizedLevel;
  final bool active;
  final int barCount;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final spacing = size.width / barCount;
    final barWidth = math.max(2.0, spacing * 0.45);
    final centerY = size.height / 2;

    for (var i = 0; i < barCount; i++) {
      final x = (i * spacing) + (spacing - barWidth) / 2;

      double barHeight;
      if (!active) {
        barHeight = 4.0;
      } else {
        // Create an organic wave shape with bell curve profile centered in middle
        final centerDist = (i - (barCount / 2)).abs() / (barCount / 2);
        final envelope = math.cos(centerDist * math.pi / 2).clamp(0.2, 1.0);
        // Harmonic variation to make bars look like voice frequencies
        final harmonic = 0.7 + 0.3 * math.sin(i * 1.3);
        final variableLevel = normalizedLevel * envelope * harmonic;
        barHeight = math.max(4.0, variableLevel * (size.height - 4.0) + 4.0);
      }

      final top = centerY - (barHeight / 2);
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, top, barWidth, barHeight),
        const Radius.circular(TokenRadius.radiusPill),
      );
      canvas.drawRRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) {
    return oldDelegate.normalizedLevel != normalizedLevel ||
        oldDelegate.active != active ||
        oldDelegate.color != color ||
        oldDelegate.barCount != barCount;
  }
}

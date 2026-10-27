import 'package:attenlume/app/theme/app_theme.dart';
import 'package:attenlume/features/capture/level_meter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FR-UI-01 & FR-UI-06 LevelMeter', () {
    test('FR-UI-06 normalizeDbfs converts dBFS range correctly', () {
      expect(LevelMeter.normalizeDbfs(-90.0), equals(0.0));
      expect(LevelMeter.normalizeDbfs(-60.0), equals(0.0));
      expect(LevelMeter.normalizeDbfs(-30.0), closeTo(0.5, 0.01));
      expect(LevelMeter.normalizeDbfs(0.0), equals(1.0));
      expect(LevelMeter.normalizeDbfs(5.0), equals(1.0));
      expect(LevelMeter.normalizeDbfs(double.nan), equals(0.0));
      expect(LevelMeter.normalizeDbfs(double.negativeInfinity), equals(0.0));
    });

    testWidgets('FR-UI-06 renders waveform visualizer when recording', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.live(),
          home: const Scaffold(
            body: LevelMeter(
              levelDbfs: -20.0,
              isRecording: true,
              isPaused: false,
            ),
          ),
        ),
      );

      expect(find.byType(LevelMeter), findsOneWidget);
      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('FR-UI-06 renders muted when paused', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.live(),
          home: const Scaffold(
            body: LevelMeter(
              levelDbfs: -20.0,
              isRecording: true,
              isPaused: true,
            ),
          ),
        ),
      );

      expect(find.byType(LevelMeter), findsOneWidget);
      expect(find.bySemanticsLabel('Microphone paused'), findsOneWidget);
    });

    testWidgets('FR-UI-06 respects reduce motion setting', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.live(),
          home: const MediaQuery(
            data: MediaQueryData(disableAnimations: true),
            child: Scaffold(
              body: LevelMeter(levelDbfs: -20.0, isRecording: true),
            ),
          ),
        ),
      );

      expect(find.byType(LevelMeter), findsOneWidget);
      expect(find.byType(FractionallySizedBox), findsOneWidget);
    });
  });
}

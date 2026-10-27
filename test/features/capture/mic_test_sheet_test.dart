import 'package:attenlume/app/theme/app_theme.dart';
import 'package:attenlume/data/local_database/database_provider.dart';
import 'package:attenlume/data/repositories/repository_providers.dart';
import 'package:attenlume/domain/services/capture_settings.dart';
import 'package:attenlume/features/capture/mic_test_sheet.dart';
import 'package:attenlume/features/capture/recording_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fixtures/fake_capture_engine.dart';
import '../../fixtures/fixtures.dart';

void main() {
  late TestData t;
  late FakeCaptureEngine fakeEngine;

  setUp(() {
    t = TestData();
    fakeEngine = FakeCaptureEngine()..level = -20.0;
  });

  tearDown(() async {
    await t.close();
  });

  Widget wrapSheet(Widget sheet) {
    return ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(t.db),
        activityRepositoryProvider.overrideWithValue(t.activities),
        conferenceRepositoryProvider.overrideWithValue(t.conferences),
        mediaAssetRepositoryProvider.overrideWithValue(t.media),
        audioCaptureEngineProvider.overrideWithValue(fakeEngine),
        capturePlatformProvider.overrideWithValue(CapturePlatform.android),
      ],
      child: MaterialApp(
        theme: AppTheme.live(),
        home: Scaffold(body: sheet),
      ),
    );
  }

  group('FR-UI-06 MicTestSheet', () {
    testWidgets(
      'FR-UI-06 displays countdown and completes successfully with audio signal',
      (tester) async {
        fakeEngine.level = -25.0;

        await tester.pumpWidget(
          wrapSheet(
            const MicTestSheet(
              testDuration: Duration(seconds: 2),
              sampleInterval: Duration(milliseconds: 100),
            ),
          ),
        );
        await tester.pump();
        await tester.pump();

        // Countdown in progress
        expect(find.text('10-Second Microphone Test'), findsOneWidget);
        expect(find.byKey(const Key('mic-test-countdown')), findsOneWidget);
        expect(find.byKey(const Key('mic-test-level-meter')), findsOneWidget);

        // Fast-forward 2 seconds
        await tester.pump(const Duration(seconds: 1));
        await tester.pump(const Duration(seconds: 1));
        await tester.pump(const Duration(seconds: 1));
        await tester.pump(const Duration(seconds: 1));
        await tester.pumpAndSettle();

        debugPrint(
          'Found text: ${find.byType(Text).evaluate().map((e) => (e.widget as Text).data).toList()}',
        );

        // Success message
        expect(find.byKey(const Key('mic-test-result-title')), findsOneWidget);
        expect(find.text('Microphone working'), findsOneWidget);
        expect(find.byKey(const Key('mic-test-done-button')), findsOneWidget);
      },
    );

    testWidgets(
      'FR-UI-06 flags flat signal when audio input is silent or blocked',
      (tester) async {
        fakeEngine.level = -85.0; // below -70.0 flatSignal threshold

        await tester.pumpWidget(
          wrapSheet(
            const MicTestSheet(
              testDuration: Duration(seconds: 1),
              sampleInterval: Duration(milliseconds: 100),
            ),
          ),
        );
        await tester.pump();
        await tester.pump();

        // Fast-forward past 1 second
        await tester.pump(const Duration(seconds: 1));
        await tester.pump();
        await tester.pumpAndSettle();

        expect(find.text('Flat signal detected'), findsOneWidget);
        expect(find.byKey(const Key('mic-test-retry-button')), findsOneWidget);
      },
    );

    testWidgets('FR-UI-06 cancel button finishes test early', (tester) async {
      await tester.pumpWidget(
        wrapSheet(
          const MicTestSheet(
            testDuration: Duration(seconds: 10),
            sampleInterval: Duration(milliseconds: 100),
          ),
        ),
      );
      await tester.pump();

      final cancelBtn = find.byKey(const Key('mic-test-cancel-button'));
      expect(cancelBtn, findsOneWidget);

      await tester.tap(cancelBtn);
      await tester.pumpAndSettle();

      // Finished state reached
      expect(find.byKey(const Key('mic-test-done-button')), findsOneWidget);
    });

    testWidgets(
      'FR-UI-06 asks for microphone access and does not capture without it',
      (tester) async {
        fakeEngine.permission = false;

        await tester.pumpWidget(
          wrapSheet(
            const MicTestSheet(
              testDuration: Duration(seconds: 1),
              sampleInterval: Duration(milliseconds: 100),
            ),
          ),
        );
        await tester.pump();
        await tester.pumpAndSettle();

        expect(fakeEngine.startedPaths, isEmpty);
        expect(
          find.textContaining('Attenlume needs microphone access'),
          findsOneWidget,
        );
      },
    );
  });
}

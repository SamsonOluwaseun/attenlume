import 'package:attenlume/app/theme/app_theme.dart';
import 'package:attenlume/app/theme/tokens.dart';
import 'package:attenlume/domain/services/recording_state.dart';
import 'package:attenlume/presentation/components/record_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget wrapWidget(Widget child) {
    return MaterialApp(
      theme: AppTheme.live(),
      home: Scaffold(body: Center(child: child)),
    );
  }

  group('FR-UI-01 & FR-REC-09 RecordButton', () {
    testWidgets('FR-UI-01 displays idle record control before recording', (
      tester,
    ) async {
      var recordTapped = false;
      await tester.pumpWidget(
        wrapWidget(
          RecordButton(
            state: RecordingState.idle,
            elapsed: Duration.zero,
            activityTitle: 'Opening Keynote',
            onRecord: () => recordTapped = true,
          ),
        ),
      );

      expect(find.byKey(const Key('record-status-idle')), findsOneWidget);
      expect(find.byKey(const Key('record-timer-text')), findsOneWidget);
      expect(find.text('00:00'), findsOneWidget);

      final recordBtn = find.byKey(const Key('record-button-start'));
      expect(recordBtn, findsOneWidget);
      final size = tester.getSize(recordBtn);
      expect(size.width, equals(TokenSize.recordButton));
      expect(size.height, equals(TokenSize.recordButton));

      await tester.tap(recordBtn);
      expect(recordTapped, isTrue);
    });

    testWidgets(
      'FR-UI-01 displays LIVE indicator, timer and active controls during recording',
      (tester) async {
        var pauseTapped = false;
        var stopTapped = false;
        var mockTime = DateTime(2026, 10, 27, 10, 0, 0);

        await tester.pumpWidget(
          wrapWidget(
            RecordButton(
              state: RecordingState.recording,
              elapsed: const Duration(minutes: 5, seconds: 23),
              activityTitle: 'Opening Keynote',
              clock: () => mockTime,
              onPause: () => pauseTapped = true,
              onStop: () => stopTapped = true,
            ),
          ),
        );

        expect(find.byKey(const Key('record-status-live')), findsOneWidget);
        expect(find.text('05:23'), findsOneWidget);

        // Pause button
        final pauseBtn = find.byKey(const Key('record-button-pause-resume'));
        expect(pauseBtn, findsOneWidget);
        expect(find.text('Pause'), findsOneWidget);
        expect(tester.getSize(pauseBtn).width, equals(TokenSize.recordButton));

        // Stop button
        final stopBtn = find.byKey(const Key('record-button-stop'));
        expect(stopBtn, findsOneWidget);
        expect(find.text('Stop'), findsOneWidget);
        expect(tester.getSize(stopBtn).width, equals(TokenSize.recordButton));

        await tester.tap(pauseBtn);
        expect(pauseTapped, isTrue);

        mockTime = mockTime.add(const Duration(milliseconds: 700));
        await tester.pump(
          const Duration(milliseconds: 700),
        ); // wait past debounce
        await tester.tap(stopBtn);
        expect(stopTapped, isTrue);
      },
    );

    testWidgets(
      'FR-UI-01 displays paused status and resume button when paused',
      (tester) async {
        var resumeTapped = false;

        await tester.pumpWidget(
          wrapWidget(
            RecordButton(
              state: RecordingState.paused,
              elapsed: const Duration(minutes: 12),
              activityTitle: 'Breakout Session',
              onResume: () => resumeTapped = true,
            ),
          ),
        );

        expect(find.byKey(const Key('record-status-paused')), findsOneWidget);
        expect(find.text('Resume'), findsOneWidget);

        await tester.tap(find.byKey(const Key('record-button-pause-resume')));
        expect(resumeTapped, isTrue);
      },
    );

    testWidgets('FR-REC-09 debounces rapid taps within 600 ms', (tester) async {
      var tapCount = 0;
      var mockTime = DateTime(2026, 10, 27, 10, 0, 0);

      await tester.pumpWidget(
        wrapWidget(
          RecordButton(
            state: RecordingState.idle,
            elapsed: Duration.zero,
            activityTitle: 'Session',
            debounceDuration: const Duration(milliseconds: 600),
            clock: () => mockTime,
            onRecord: () => tapCount++,
          ),
        ),
      );

      final recordBtn = find.byKey(const Key('record-button-start'));

      // First tap invokes
      await tester.tap(recordBtn);
      expect(tapCount, equals(1));

      // Rapid second tap within 200 ms is ignored
      mockTime = mockTime.add(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(recordBtn);
      expect(tapCount, equals(1));

      // Third tap after 700 ms invokes
      mockTime = mockTime.add(const Duration(milliseconds: 700));
      await tester.pump(const Duration(milliseconds: 700));
      await tester.tap(recordBtn);
      expect(tapCount, equals(2));
    });

    testWidgets(
      'FR-UI-01 displays secondary actions row: Photo, Bookmark, Note',
      (tester) async {
        var photoTapped = false;
        var bookmarkTapped = false;
        var noteTapped = false;
        var mockTime = DateTime(2026, 10, 27, 10, 0, 0);

        await tester.pumpWidget(
          wrapWidget(
            RecordButton(
              state: RecordingState.recording,
              elapsed: const Duration(seconds: 45),
              activityTitle: 'Session',
              clock: () => mockTime,
              onPhoto: () => photoTapped = true,
              onBookmark: () => bookmarkTapped = true,
              onNote: () => noteTapped = true,
            ),
          ),
        );

        expect(find.byKey(const Key('record-action-photo')), findsOneWidget);
        expect(find.byKey(const Key('record-action-bookmark')), findsOneWidget);
        expect(find.byKey(const Key('record-action-note')), findsOneWidget);

        await tester.tap(find.byKey(const Key('record-action-photo')));
        expect(photoTapped, isTrue);

        mockTime = mockTime.add(const Duration(milliseconds: 700));
        await tester.pump(const Duration(milliseconds: 700));
        await tester.tap(find.byKey(const Key('record-action-bookmark')));
        expect(bookmarkTapped, isTrue);

        mockTime = mockTime.add(const Duration(milliseconds: 700));
        await tester.pump(const Duration(milliseconds: 700));
        await tester.tap(find.byKey(const Key('record-action-note')));
        expect(noteTapped, isTrue);
      },
    );
  });
}

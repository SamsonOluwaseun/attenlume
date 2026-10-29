import 'package:attenlume/app/theme/app_theme.dart';
import 'package:attenlume/domain/models/enums.dart';
import 'package:attenlume/domain/services/recording_state.dart';
import 'package:attenlume/features/capture/camera_screen.dart';
import 'package:attenlume/features/capture/mic_test_sheet.dart';
import 'package:attenlume/features/capture/quick_thought_sheet.dart';
import 'package:attenlume/features/capture/recording_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'a11y_harness.dart';

/// NFR-09 accessibility of the recording screen and its sheets [P1-26].
void main() {
  Future<(A11yHarness, String)> open(
    WidgetTester tester, {
    A11ySize size = A11ySize.phone,
    double textScale = 1,
    RecordingStatus Function(String activityId)? status,
  }) async {
    final h = A11yHarness(tester);
    await h.setUp();
    addTearDown(h.tearDown);
    h.size(size, textScale: textScale);
    final id = await h.io(() async {
      final c = await h.t.conference(policyAcknowledged: true);
      return (await h.t.activity(c.id, title: 'Data Mesh in Practice')).id;
    });
    await tester.pumpWidget(
      h.app(
        RecordingScreen(activityId: id, enableTicker: false),
        theme: AppTheme.live(),
        status: status?.call(id),
      ),
    );
    await h.settle();
    return (h, id);
  }

  RecordingStatus live(String id) => RecordingStatus(
    state: RecordingState.recording,
    activityId: id,
    profile: RecordingProfile.balanced,
    segmentStartUtc: DateTime.utc(2026, 11, 4, 9),
  );

  RecordingStatus interrupted(String id) => RecordingStatus(
    state: RecordingState.userResumeRequired,
    activityId: id,
    interruption: InterruptionReason.call,
    errorMessage: 'Recording paused for a call or another app.',
  );

  group('NFR-09 recording screen', () {
    testWidgets('NFR-09 idle recording screen meets tap target, label and '
        'contrast guidelines', (tester) async {
      final handle = tester.ensureSemantics();
      await open(tester);
      await expectMeetsGuidelines(tester);
      handle.dispose();
    });

    testWidgets('NFR-09 live recording screen meets the guidelines', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await open(tester, status: live);
      expect(find.text('LIVE'), findsOneWidget);
      await expectMeetsGuidelines(tester);
      handle.dispose();
    });

    testWidgets('NFR-09 interrupted banner meets the guidelines and says '
        'Interrupted in words', (tester) async {
      final handle = tester.ensureSemantics();
      await open(tester, status: interrupted);
      expect(find.text('Interrupted'), findsOneWidget);
      await expectMeetsGuidelines(tester);
      handle.dispose();
    });

    testWidgets('NFR-09 record controls have one clear label each and '
        'the state is a live region', (tester) async {
      final handle = tester.ensureSemantics();
      await open(tester, status: live);

      expect(
        find.bySemanticsLabel(RegExp(r'^Pause recording, Data Mesh')),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('Stop and save recording, Data Mesh in Practice'),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('Take photo'), findsOneWidget);
      expect(find.bySemanticsLabel('Add bookmark'), findsOneWidget);
      expect(find.bySemanticsLabel('Add quick note'), findsOneWidget);
      expect(find.byTooltip('Test microphone'), findsOneWidget);
      expect(find.byTooltip('Back'), findsOneWidget);

      final status = tester.getSemantics(
        find.byKey(const Key('record-status')),
      );
      expect(status.flagsCollection.isLiveRegion, isTrue);
      expect(status.label, contains('LIVE'));
      handle.dispose();
    });

    testWidgets('NFR-09 reduced motion stops the live dot pulse', (
      tester,
    ) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await open(tester, status: live);
      expect(
        find.descendant(
          of: find.byKey(const Key('record-status')),
          matching: find.byType(FadeTransition),
        ),
        findsNothing,
      );
    });

    testWidgets('NFR-09 recording controls are reachable by keyboard and '
        'Ctrl+B still adds a bookmark', (tester) async {
      final (h, id) = await open(tester, size: A11ySize.tablet);
      // Tab from the screen reaches the Record button; Enter activates it.
      var reached = false;
      for (var i = 0; i < 12 && !reached; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        final focus = FocusManager.instance.primaryFocus?.context;
        reached =
            focus != null &&
            find
                .ancestor(
                  of: find.byWidget(focus.widget),
                  matching: find.byKey(const Key('main-record-button')),
                )
                .evaluate()
                .isNotEmpty;
      }
      expect(reached, isTrue, reason: 'Tab reaches the record controls');

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await h.settle();
      final bookmarks = await h.io(() => h.t.media.bookmarksFor(id));
      expect(bookmarks, hasLength(1));
    });

    for (final size in A11ySize.values) {
      testWidgets('NFR-09 recording screen at 200% text on ${size.name} has '
          'no overflow', (tester) async {
        await open(tester, size: size, textScale: 2, status: interrupted);
        await scrollThrough(tester, A11yHarness(tester));
        // Any overflow is reported by the framework and fails the test.
      });
    }
  });

  group('NFR-09 recording sheets', () {
    Future<void> sheet(
      WidgetTester tester,
      Future<void> Function(BuildContext context, String id) show, {
      double textScale = 1,
    }) async {
      final (h, id) = await open(tester, textScale: textScale);
      final context = tester.element(find.byType(RecordingScreen));
      // ignore: unawaited_futures
      show(context, id);
      await h.settle();
    }

    testWidgets('NFR-09 mic test sheet meets the guidelines', (tester) async {
      final handle = tester.ensureSemantics();
      await sheet(tester, (c, _) => MicTestSheet.show(c));
      await expectMeetsGuidelines(tester);
      handle.dispose();
    });

    testWidgets('NFR-09 quick thought sheet meets the guidelines', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await sheet(tester, (c, id) => QuickThoughtSheet.show(c, activityId: id));
      await expectMeetsGuidelines(tester);
      handle.dispose();
    });

    testWidgets('NFR-09 camera screen meets the guidelines', (tester) async {
      final handle = tester.ensureSemantics();
      await sheet(tester, CameraScreen.open);
      await expectMeetsGuidelines(tester);
      handle.dispose();
    });

    for (final (name, show)
        in <(String, Future<void> Function(BuildContext, String))>[
          ('mic test', (c, _) => MicTestSheet.show(c)),
          (
            'quick thought',
            (c, id) => QuickThoughtSheet.show(c, activityId: id),
          ),
          ('camera', CameraScreen.open),
        ]) {
      testWidgets('NFR-09 $name at 200% text has no overflow', (tester) async {
        await sheet(tester, show, textScale: 2);
        // Any overflow is reported by the framework and fails the test.
      });
    }
  });
}

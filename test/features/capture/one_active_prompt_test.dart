import 'dart:async';
import 'dart:io';

import 'package:attenlume/app/theme/app_theme.dart';
import 'package:attenlume/domain/services/capture_settings.dart';
import 'package:attenlume/domain/services/one_active_coordinator.dart';
import 'package:attenlume/domain/services/recording_service.dart';
import 'package:attenlume/domain/services/recording_state.dart';
import 'package:attenlume/features/capture/one_active_prompt_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fixtures/fake_capture_engine.dart';
import '../../fixtures/fake_timers.dart';
import '../../fixtures/fixtures.dart';

class _NoConfirmations implements TriggerConfirmationSink {
  @override
  Future<void> confirm(RecordingTrigger trigger, String message) async {}
}

void main() {
  const recording = OneActiveConflict(
    activityId: 'a',
    title: 'Data Mesh Keynote',
    state: RecordingState.recording,
    recorded: Duration(minutes: 47),
  );

  Future<void> pumpHost(
    WidgetTester tester,
    Future<void> Function(BuildContext context) onPressed,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => onPressed(context),
              child: const Text('Record'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Record'));
    await tester.pumpAndSettle();
  }

  group('FR-REC-04 one-active prompt dialog', () {
    testWidgets('FR-REC-04 shows the title, minutes and three choices in '
        'sentence case', (tester) async {
      await pumpHost(
        tester,
        (context) => OneActivePromptDialog.show(context, recording),
      );

      expect(find.byKey(const Key('one-active-dialog')), findsOneWidget);
      expect(
        find.text("'Data Mesh Keynote' is still recording (47 min)."),
        findsOneWidget,
      );
      expect(find.text('Stop it and start new'), findsOneWidget);
      expect(find.text('Keep it running'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
    });

    final cases = {
      'one-active-stop-and-start': OneActiveChoice.stopAndStartNew,
      'one-active-keep': OneActiveChoice.keepRunning,
      'one-active-cancel': OneActiveChoice.cancel,
    };
    for (final MapEntry(key: key, value: expected) in cases.entries) {
      testWidgets('FR-REC-04 $key returns ${expected.name}', (tester) async {
        OneActiveChoice? chosen;
        await pumpHost(tester, (context) async {
          chosen = await OneActivePromptDialog.show(context, recording);
        });

        await tester.tap(find.byKey(Key(key)));
        await tester.pumpAndSettle();

        expect(chosen, expected);
        expect(find.byKey(const Key('one-active-dialog')), findsNothing);
      });
    }

    testWidgets('FR-REC-04 dismissing returns null (treated as cancel)', (
      tester,
    ) async {
      var chosen = OneActiveChoice.stopAndStartNew as OneActiveChoice?;
      await pumpHost(tester, (context) async {
        chosen = await OneActivePromptDialog.show(context, recording);
      });

      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();

      expect(chosen, isNull);
    });

    testWidgets('FR-REC-04 a paused recording says paused and offers to '
        'keep it paused', (tester) async {
      await pumpHost(
        tester,
        (context) => OneActivePromptDialog.show(
          context,
          const OneActiveConflict(
            activityId: 'a',
            title: 'Data Mesh Keynote',
            state: RecordingState.paused,
            recorded: Duration(hours: 3, minutes: 12),
          ),
        ),
      );

      expect(
        find.text("'Data Mesh Keynote' is paused (3 h 12 min recorded)."),
        findsOneWidget,
      );
      expect(find.text('Keep it paused'), findsOneWidget);
    });
  });

  group('AT-REC-04 starting from the UI', () {
    late TestData t;
    late Directory root;
    late RecordingService service;
    late OneActiveCoordinator coordinator;

    setUp(() async {
      t = TestData();
      root = await Directory.systemTemp.createTemp('attenlume_prompt_');
      service = RecordingService(
        engine: FakeCaptureEngine(),
        activities: t.activities,
        media: t.media,
        mediaRoot: () async => root,
        platform: CapturePlatform.android,
        clock: t.clock.call,
        rollTimer: FakeTimers().call,
      );
      coordinator = OneActiveCoordinator(
        recorder: service,
        activities: t.activities,
        media: t.media,
        confirmations: _NoConfirmations(),
        clock: t.clock.call,
      );
    });

    tearDown(() async {
      await service.dispose();
      await t.close();
      await root.delete(recursive: true);
    });

    testWidgets('AT-REC-04 a second start shows the prompt and "Stop it and '
        'start new" switches', (tester) async {
      late String panelId;
      late String keynoteId;
      await tester.runAsync(() async {
        final conference = await t.conference();
        keynoteId = (await t.activity(
          conference.id,
          title: 'Data Mesh Keynote',
        )).id;
        panelId = (await t.activity(conference.id, title: 'Panel')).id;
        await service.start(keynoteId);
        t.clock.advance(const Duration(minutes: 47));
      });

      Future<RecordRequestResult>? pending;
      await pumpHost(tester, (context) async {
        pending = startRecordingFromUi(context, coordinator, panelId);
      });
      // The coordinator reads the database before the dialog opens.
      for (var i = 0; i < 20; i++) {
        if (find.byKey(const Key('one-active-dialog')).evaluate().isNotEmpty) {
          break;
        }
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      expect(
        find.text("'Data Mesh Keynote' is still recording (47 min)."),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('one-active-stop-and-start')));
      RecordRequestResult? result;
      unawaited(pending!.then((r) => result = r));
      // Database and hashing work needs real time as well as pumps.
      for (var i = 0; i < 200 && result == null; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(result, isNotNull);

      expect(result!.outcome, RecordRequestOutcome.switched);
      expect(result!.stoppedActivityId, keynoteId);
      expect(service.status.activityId, panelId);

      // Save and release here: the lock's futures belong to the fake zone,
      // so tearDown's dispose finds nothing left to do.
      var disposed = false;
      unawaited(service.dispose().then((_) => disposed = true));
      for (var i = 0; i < 200 && !disposed; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      expect(disposed, isTrue);
    });
  });
}

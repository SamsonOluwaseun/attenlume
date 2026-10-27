import 'dart:io';

import 'package:attenlume/data/local_database/app_database.dart';
import 'package:attenlume/domain/models/activity.dart';
import 'package:attenlume/domain/models/conference.dart';
import 'package:attenlume/domain/models/enums.dart';
import 'package:attenlume/domain/services/capture_settings.dart';
import 'package:attenlume/domain/services/one_active_coordinator.dart';
import 'package:attenlume/domain/services/recording_service.dart';
import 'package:attenlume/domain/services/recording_state.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import '../fixtures/fake_capture_engine.dart';
import '../fixtures/fixtures.dart';

class _Confirmations implements TriggerConfirmationSink {
  final sent = <(RecordingTrigger, String)>[];

  @override
  Future<void> confirm(RecordingTrigger trigger, String message) async =>
      sent.add((trigger, message));
}

void main() {
  late TestData t;
  late Directory root;
  late FakeCaptureEngine engine;
  late RecordingService service;
  late _Confirmations confirmations;
  late OneActiveCoordinator coordinator;
  late Conference conference;
  late Activity keynote;
  late Activity panel;

  setUp(() async {
    t = TestData();
    root = await Directory.systemTemp.createTemp('attenlume_one_active_');
    engine = FakeCaptureEngine();
    service = RecordingService(
      engine: engine,
      activities: t.activities,
      media: t.media,
      mediaRoot: () async => root,
      platform: CapturePlatform.android,
      clock: t.clock.call,
    );
    confirmations = _Confirmations();
    coordinator = OneActiveCoordinator(
      recorder: service,
      activities: t.activities,
      media: t.media,
      confirmations: confirmations,
      clock: t.clock.call,
    );
    conference = await t.conference();
    keynote = await t.activity(conference.id, title: 'Data Mesh Keynote');
    panel = await t.activity(conference.id, title: 'Panel');
  });

  tearDown(() async {
    await service.dispose();
    await t.close();
    await root.delete(recursive: true);
  });

  Future<void> keynoteRunningFor(Duration elapsed) async {
    expect(await service.start(keynote.id), StartOutcome.started);
    t.clock.advance(elapsed);
  }

  group('FR-REC-04 RecordingService.switchTo', () {
    test('FR-REC-04 stops and saves the old activity, then starts the new '
        'one', () async {
      await keynoteRunningFor(const Duration(minutes: 47));
      final seen = <RecordingState>[];
      final sub = service.statusStream.listen((s) => seen.add(s.state));

      final result = await service.switchTo(panel.id);
      await Future<void>.delayed(Duration.zero);

      expect(result.outcome, StartOutcome.started);
      expect(result.stoppedActivityId, keynote.id);
      expect(seen, [
        RecordingState.stopping,
        RecordingState.saved,
        RecordingState.starting,
        RecordingState.recording,
      ]);
      expect(service.status.activityId, panel.id);
      final old = (await t.activities.get(keynote.id))!;
      expect(old.status, ActivityStatus.completed);
      final oldSegment = (await t.media.segmentsFor(keynote.id)).single;
      expect(oldSegment.endReason, SegmentEndReason.userStop);
      expect(await t.media.segmentsFor(panel.id), hasLength(1));
      await sub.cancel();
    });

    test('FR-REC-04 runs as one command: a stop queued behind it stops the '
        'new recording, never leaves both or neither', () async {
      await keynoteRunningFor(const Duration(minutes: 1));

      final switching = service.switchTo(panel.id);
      final stopping = service.stop();

      expect((await switching).stoppedActivityId, keynote.id);
      expect(await stopping, panel.id);
      expect(service.status.state, RecordingState.saved);
      expect(engine.startedPaths, hasLength(2));
    });

    test('FR-REC-04 a start that would be refused never stops the old '
        'recording', () async {
      await t.activities.update(
        panel.id,
        const ActivitiesCompanion(
          recordingPermissionStatus: Value(
            RecordingPermissionStatus.notPermitted,
          ),
        ),
      );
      await keynoteRunningFor(const Duration(minutes: 1));

      final result = await service.switchTo(panel.id);

      expect(result.outcome, StartOutcome.recordingNotPermitted);
      expect(result.stoppedActivityId, isNull);
      expect(service.status.state, RecordingState.recording);
      expect(service.status.activityId, keynote.id);
    });

    test('FR-REC-04 refuses when a different activity holds the recorder '
        'than the one agreed to stop', () async {
      final third = await t.activity(conference.id, title: 'Workshop');
      await keynoteRunningFor(const Duration(minutes: 1));

      final result = await service.switchTo(third.id, replacing: panel.id);

      expect(result.outcome, StartOutcome.conflict);
      expect(service.status.activityId, keynote.id);
      expect(service.status.state, RecordingState.recording);
    });

    test('FR-REC-04 with nothing held it is a plain start; with the same '
        'activity it changes nothing', () async {
      final first = await service.switchTo(keynote.id);
      expect(first.outcome, StartOutcome.started);
      expect(first.stoppedActivityId, isNull);

      final again = await service.switchTo(keynote.id);
      expect(again.outcome, StartOutcome.alreadyRecording);
      expect(engine.startedPaths, hasLength(1));
    });

    test('FR-REC-04 a paused activity is saved before the switch', () async {
      await keynoteRunningFor(const Duration(minutes: 3));
      await service.pause();

      final result = await service.switchTo(panel.id);

      expect(result.outcome, StartOutcome.started);
      expect(result.stoppedActivityId, keynote.id);
      expect(
        (await t.activities.get(keynote.id))!.status,
        ActivityStatus.completed,
      );
    });
  });

  group('AT-REC-04 one-active prompt for visual triggers', () {
    test('AT-REC-04 a UI start over a running recording asks, with title '
        'and minutes', () async {
      await keynoteRunningFor(const Duration(minutes: 47));
      OneActiveConflict? asked;

      final result = await coordinator.requestStart(
        panel.id,
        trigger: RecordingTrigger.ui,
        prompt: (conflict) async {
          asked = conflict;
          return OneActiveChoice.cancel;
        },
      );

      expect(asked!.activityId, keynote.id);
      expect(
        asked!.message,
        "'Data Mesh Keynote' is still recording (47 min).",
      );
      expect(result.outcome, RecordRequestOutcome.cancelled);
    });

    test('AT-REC-04 "Stop it and start new" switches', () async {
      await keynoteRunningFor(const Duration(minutes: 5));

      final result = await coordinator.requestStart(
        panel.id,
        trigger: RecordingTrigger.ui,
        prompt: (_) async => OneActiveChoice.stopAndStartNew,
      );

      expect(result.outcome, RecordRequestOutcome.switched);
      expect(result.stoppedActivityId, keynote.id);
      expect(service.status.activityId, panel.id);
      expect(service.status.state, RecordingState.recording);
      expect(confirmations.sent, isEmpty);
    });

    test('AT-REC-04 "Keep it running" and Cancel leave the old recording '
        'untouched', () async {
      await keynoteRunningFor(const Duration(minutes: 5));

      for (final choice in [OneActiveChoice.keepRunning, null]) {
        final result = await coordinator.requestStart(
          panel.id,
          trigger: RecordingTrigger.notification,
          prompt: (_) async => choice,
        );
        expect(
          result.outcome,
          choice == null
              ? RecordRequestOutcome.cancelled
              : RecordRequestOutcome.keptRunning,
        );
      }

      expect(service.status.activityId, keynote.id);
      expect(service.status.state, RecordingState.recording);
      expect(engine.startedPaths, hasLength(1));
      expect(await t.media.segmentsFor(panel.id), isEmpty);
      expect(confirmations.sent, isEmpty);
    });

    test('AT-REC-04 counts recorded time across segments, not pauses, and '
        'says when paused', () async {
      await keynoteRunningFor(const Duration(minutes: 10));
      await service.pause();
      t.clock.advance(const Duration(minutes: 30));
      await service.resume();
      t.clock.advance(const Duration(minutes: 2));
      await service.pause();
      OneActiveConflict? asked;

      await coordinator.requestStart(
        panel.id,
        trigger: RecordingTrigger.ui,
        prompt: (conflict) async {
          asked = conflict;
          return OneActiveChoice.cancel;
        },
      );

      expect(asked!.recorded, const Duration(minutes: 12));
      expect(asked!.isPaused, isTrue);
      expect(
        asked!.message,
        "'Data Mesh Keynote' is paused (12 min recorded).",
      );
    });

    test('AT-REC-04 no prompt when nothing else is recording', () async {
      var asked = false;

      final result = await coordinator.requestStart(
        keynote.id,
        trigger: RecordingTrigger.ui,
        prompt: (_) async {
          asked = true;
          return OneActiveChoice.cancel;
        },
      );

      expect(result.outcome, RecordRequestOutcome.started);
      expect(asked, isFalse);
      expect(confirmations.sent, isEmpty);
    });

    test('AT-REC-04 the same activity again is not a conflict', () async {
      await keynoteRunningFor(const Duration(minutes: 1));

      final result = await coordinator.requestStart(
        keynote.id,
        trigger: RecordingTrigger.ui,
        prompt: (_) async => fail('must not prompt'),
      );

      expect(result.outcome, RecordRequestOutcome.alreadyRecording);
    });

    test('AT-REC-04 if another activity took over while the prompt was '
        'open, nothing is stopped', () async {
      final third = await t.activity(conference.id, title: 'Workshop');
      await keynoteRunningFor(const Duration(minutes: 1));

      final result = await coordinator.requestStart(
        panel.id,
        trigger: RecordingTrigger.ui,
        prompt: (_) async {
          await service.stop();
          await service.start(third.id);
          return OneActiveChoice.stopAndStartNew;
        },
      );

      expect(result.outcome, RecordRequestOutcome.refused);
      expect(result.startOutcome, StartOutcome.conflict);
      expect(service.status.activityId, third.id);
      expect(service.status.state, RecordingState.recording);
    });
  });

  group('AT-REC-04 non-visual triggers default to stop old, start new', () {
    for (final trigger in [RecordingTrigger.shortcut, RecordingTrigger.voice]) {
      test('AT-REC-04 ${trigger.name} switches without asking and '
          'confirms', () async {
        await keynoteRunningFor(const Duration(minutes: 47));

        final result = await coordinator.requestStart(
          panel.id,
          trigger: trigger,
          prompt: (_) async => fail('must not prompt'),
        );

        expect(result.outcome, RecordRequestOutcome.switched);
        expect(result.stoppedActivityId, keynote.id);
        expect(service.status.activityId, panel.id);
        expect(confirmations.sent, [
          (
            trigger,
            "Stopped and saved 'Data Mesh Keynote'. Now recording 'Panel'.",
          ),
        ]);
        expect(result.confirmation, confirmations.sent.single.$2);
      });
    }

    test('AT-REC-04 a plain shortcut start is confirmed too', () async {
      final result = await coordinator.requestStart(
        keynote.id,
        trigger: RecordingTrigger.shortcut,
      );

      expect(result.outcome, RecordRequestOutcome.started);
      expect(confirmations.sent.single.$2, "Recording 'Data Mesh Keynote'.");
    });

    test('AT-REC-04 a notification start with no screen to ask on follows '
        'the default and confirms', () async {
      await keynoteRunningFor(const Duration(minutes: 2));

      final result = await coordinator.requestStart(
        panel.id,
        trigger: RecordingTrigger.notification,
      );

      expect(result.outcome, RecordRequestOutcome.switched);
      expect(confirmations.sent, hasLength(1));
    });

    test('AT-REC-04 a refused shortcut start keeps the old recording and '
        'says why', () async {
      await t.activities.update(
        panel.id,
        const ActivitiesCompanion(
          recordingPermissionStatus: Value(
            RecordingPermissionStatus.notPermitted,
          ),
        ),
      );
      await keynoteRunningFor(const Duration(minutes: 2));

      final result = await coordinator.requestStart(
        panel.id,
        trigger: RecordingTrigger.voice,
      );

      expect(result.outcome, RecordRequestOutcome.refused);
      expect(result.stoppedActivityId, isNull);
      expect(service.status.activityId, keynote.id);
      expect(
        confirmations.sent.single.$2,
        "'Panel' is set to not record audio.",
      );
    });

    test('AT-REC-04 a failing confirmation sink never undoes the '
        'recording', () async {
      final failing = OneActiveCoordinator(
        recorder: service,
        activities: t.activities,
        media: t.media,
        confirmations: _ThrowingConfirmations(),
        clock: t.clock.call,
      );

      final result = await failing.requestStart(
        keynote.id,
        trigger: RecordingTrigger.shortcut,
      );

      expect(result.outcome, RecordRequestOutcome.started);
      expect(service.status.state, RecordingState.recording);
    });
  });

  test('FR-REC-04 only ui and notification triggers can prompt', () {
    expect(
      [
        for (final t in RecordingTrigger.values)
          if (t.canPrompt) t,
      ],
      [RecordingTrigger.ui, RecordingTrigger.notification],
    );
  });
}

class _ThrowingConfirmations implements TriggerConfirmationSink {
  @override
  Future<void> confirm(RecordingTrigger trigger, String message) =>
      Future.error(StateError('no notification channel'));
}

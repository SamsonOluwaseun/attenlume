import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:attenlume/domain/models/activity.dart';
import 'package:attenlume/domain/models/enums.dart';
import 'package:attenlume/domain/services/capture_settings.dart';
import 'package:attenlume/domain/services/recording_service.dart';
import 'package:attenlume/domain/services/recording_state.dart';
import 'package:attenlume/platform/shortcuts/shortcut_command.dart';
import 'package:attenlume/spikes/shortcut_trigger_spike.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_test/flutter_test.dart';

import '../fixtures/fake_capture_engine.dart';
import '../fixtures/fake_shortcut_bridge.dart';
import '../fixtures/fixtures.dart';

void main() {
  late TestData t;
  late Directory root;
  late FakeCaptureEngine engine;
  late RecordingService service;
  late FakeShortcutBridge bridge;
  late StreamController<AppLifecycleState> lifecycle;
  late Activity talk;

  /// Called after each one-second wait, with the wait's number (1-based).
  late void Function(int n) onWait;

  ShortcutCommand command(
    ShortcutAction action, {
    ShortcutSource source = ShortcutSource.quickSettingsTile,
    String? activityId,
    Duration ago = const Duration(milliseconds: 300),
    bool coldStart = false,
    bool? appVisible = true,
    bool direct = false,
  }) => ShortcutCommand(
    action: action,
    source: source,
    activityId: activityId,
    triggeredAt: t.clock().subtract(ago),
    coldStart: coldStart,
    appVisibleAtTrigger: appVisible,
    deliveredDirect: direct,
  );

  Future<ShortcutTriggerReport> run({
    int seconds = 10,
    bool tileDirect = false,
  }) {
    late ShortcutTriggerSpike spike;
    var waits = 0;
    spike = ShortcutTriggerSpike(
      service: service,
      engine: engine,
      media: t.media,
      bridge: bridge,
      lifecycle: lifecycle.stream,
      clock: t.clock.call,
      wait: (d) async {
        t.clock.advance(d);
        onWait(++waits);
        await Future<void>.delayed(Duration.zero);
        await spike.settle();
      },
    );
    return spike.run(
      activityId: talk.id,
      duration: Duration(seconds: seconds),
      tileDirect: tileDirect,
    );
  }

  setUp(() async {
    t = TestData();
    root = await Directory.systemTemp.createTemp('attenlume_p0_13_');
    engine = FakeCaptureEngine();
    service = RecordingService(
      engine: engine,
      activities: t.activities,
      media: t.media,
      mediaRoot: () async => root,
      platform: CapturePlatform.android,
      clock: t.clock.call,
      hashFile: (_) async => 'hash',
    );
    bridge = FakeShortcutBridge();
    lifecycle = StreamController<AppLifecycleState>.broadcast();
    onWait = (_) {};
    final conference = await t.conference();
    talk = await t.activity(conference.id, title: 'Keynote');
  });

  tearDown(() async {
    await service.dispose();
    await bridge.close();
    await lifecycle.close();
    await t.close();
    await root.delete(recursive: true);
  });

  test('P0-13 FR-HF-04 a tile tap toggles recording on and off', () async {
    onWait = (n) {
      if (n == 1 || n == 6) {
        bridge.send(command(ShortcutAction.toggleRecording));
      }
    };

    final report = await run();

    expect(report.triggers.map((x) => x.outcome), [
      TriggerOutcome.started,
      TriggerOutcome.stopped,
    ]);
    expect(report.segments, hasLength(1));
    expect(report.triggers.first.triggerToDoneMs, 300);
    expect(report.triggers.first.deliveryMs, 300);
    expect(report.triggers.first.stateAfter, RecordingState.recording);
    expect(report.triggers.first.levelsAfterStart, hasLength(5));
    expect(report.triggers.first.silentAfterStart, isFalse);
    expect(report.startsWithSound, hasLength(1));
    expect(report.backgroundStarts, isEmpty);
    expect(service.status.state, RecordingState.saved);
  });

  test('P0-13 FR-HF-01 the command that launched the app is handled '
      'first and reported as a cold start', () async {
    bridge.initial = command(
      ShortcutAction.startRecording,
      source: ShortcutSource.appIntent,
      coldStart: true,
      appVisible: false,
      ago: const Duration(seconds: 2),
    );

    final report = await run(seconds: 3);

    final first = report.triggers.single;
    expect(first.initial, isTrue);
    expect(first.command.coldStart, isTrue);
    expect(first.outcome, TriggerOutcome.started);
    expect(first.triggerToDoneMs, 2000);
    expect(first.inBackground, isTrue, reason: 'no screen at the tap');
    expect(report.observations.join('\n'), contains('1 cold start'));
    expect(
      service.status.state,
      RecordingState.saved,
      reason: 'stopped at end',
    );
  });

  test('P0-13 FR-REC-04 a start for another activity while one records is '
      'a conflict, never a switch', () async {
    final conference = await t.conference(name: 'Other');
    final other = await t.activity(conference.id, title: 'Workshop');
    onWait = (n) {
      if (n == 1) bridge.send(command(ShortcutAction.startRecording));
      if (n == 2) {
        bridge.send(
          command(ShortcutAction.startRecording, activityId: other.id),
        );
      }
      if (n == 3) bridge.send(command(ShortcutAction.startRecording));
    };

    final report = await run(seconds: 4);

    expect(report.triggers.map((x) => x.outcome), [
      TriggerOutcome.started,
      TriggerOutcome.conflict,
      TriggerOutcome.alreadyRecording,
    ]);
    expect(report.conflicts.single.detail, contains(talk.id));
    expect(await t.media.segmentsFor(other.id), isEmpty);
    expect(report.segments, hasLength(1));
  });

  test('P0-13 FR-HF-01 bookmarks need a running recording and are stored '
      'with source shortcut', () async {
    onWait = (n) {
      if (n == 1) bridge.send(command(ShortcutAction.bookmark));
      if (n == 2) bridge.send(command(ShortcutAction.startRecording));
      if (n == 5) {
        bridge.send(
          command(ShortcutAction.bookmark, source: ShortcutSource.appIntent),
        );
      }
    };

    final report = await run(seconds: 6);

    expect(report.triggers.map((x) => x.outcome), [
      TriggerOutcome.noRecordingToBookmark,
      TriggerOutcome.started,
      TriggerOutcome.bookmarked,
    ]);
    final bookmark = report.bookmarks.single;
    expect(bookmark.source, BookmarkSource.shortcut);
    expect(bookmark.offsetMs, 3000);
    expect(bookmark.label, 'Shortcut (app_intent)');
  });

  test('P0-13 a stop with nothing recording changes nothing', () async {
    onWait = (n) {
      if (n == 1) bridge.send(command(ShortcutAction.stopRecording));
    };

    final report = await run(seconds: 2);

    expect(report.triggers.single.outcome, TriggerOutcome.nothingToStop);
    expect(report.segments, isEmpty);
  });

  test('P0-13 photo and new conversation only open the app for now', () async {
    onWait = (n) {
      if (n == 1) bridge.send(command(ShortcutAction.takePhoto));
      if (n == 2) bridge.send(command(ShortcutAction.newConversation));
    };

    final report = await run(seconds: 3);

    expect(
      report.triggers.map((x) => x.outcome),
      everyElement(TriggerOutcome.openedAppOnly),
    );
  });

  test('P0-13 a direct start with the app in the background is flagged, '
      'and silence marks the microphone as cut off', () async {
    engine.level = -120;
    onWait = (n) {
      if (n == 1) lifecycle.add(AppLifecycleState.paused);
      if (n == 2) {
        bridge.send(
          command(
            ShortcutAction.toggleRecording,
            appVisible: false,
            direct: true,
          ),
        );
      }
    };

    final report = await run(seconds: 8, tileDirect: true);

    final start = report.triggers.single;
    expect(start.lifecycleOnArrival, AppLifecycleState.paused);
    expect(start.inBackground, isTrue);
    expect(start.silentAfterStart, isTrue);
    expect(report.backgroundStarts, [start]);
    expect(report.silentStarts, [start]);
    expect(bridge.tileDirectCalls, [true, false], reason: 'reset at the end');
    expect(report.observations.join('\n'), contains('#1 silent'));
  });

  test('P0-13 a refused start is reported with the reason', () async {
    engine.permission = false;
    onWait = (n) {
      if (n == 1) bridge.send(command(ShortcutAction.startRecording));
    };

    final report = await run(seconds: 2);

    expect(report.triggers.single.outcome, TriggerOutcome.startFailed);
    expect(report.triggers.single.detail, 'microphoneDenied');
    expect(report.observations.join('\n'), contains('microphoneDenied'));
  });

  test('P0-13 the report renders as JSON and a Markdown table', () async {
    onWait = (n) {
      if (n == 1) bridge.send(command(ShortcutAction.toggleRecording));
      if (n == 3) bridge.send(command(ShortcutAction.bookmark));
    };

    final report = await run(seconds: 4);

    final json = jsonDecode(report.toPrettyJson()) as Map<String, Object?>;
    expect(json['spike'], 'P0-13');
    expect(json['triggers'], hasLength(2));
    expect(json['bookmarks'], hasLength(1));
    expect((json['events']! as List).isNotEmpty, isTrue);
    final md = report.toMarkdown();
    expect(md, contains('| 1 | tile | toggle | no | yes | no | resumed '));
    expect(md, contains('| started | 300 | yes |'));
    expect(md, contains('Tap to recording: min 300 ms'));
  });
}

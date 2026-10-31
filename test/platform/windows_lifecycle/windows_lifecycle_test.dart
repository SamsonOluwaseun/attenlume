import 'dart:async';

import 'package:attenlume/domain/services/recording_state.dart';
import 'package:attenlume/platform/windows_lifecycle/windows_lifecycle.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/windows_lifecycle');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late StreamController<RecordingStatus> changes;
  late RecordingStatus status;
  late List<MethodCall> calls;
  late WindowsLifecycle bridge;
  late Future<void> Function() stop;

  setUp(() {
    changes = StreamController<RecordingStatus>.broadcast(sync: true);
    status = RecordingStatus.idle;
    calls = [];
    stop = () async {
      status = const RecordingStatus(state: RecordingState.saved);
      changes.add(status);
    };
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    bridge = WindowsLifecycle(
      status: () => status,
      changes: changes.stream,
      stop: () => stop(),
      channel: channel,
    );
  });

  tearDown(() async {
    await bridge.dispose();
    await changes.close();
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('FR-REC-10 P1-27 status protects paused, interrupted and error recordings without titles', () async {
    await bridge.start();
    for (final state in RecordingState.values) {
      status = RecordingStatus(state: state, activityId: 'private-title');
      changes.add(status);
    }
    await Future<void>.delayed(Duration.zero);
    final updates = calls.where((c) => c.method == 'status').toList();
    expect(updates.length, RecordingState.values.length + 1);
    for (var i = 0; i < RecordingState.values.length; i++) {
      expect(updates[i + 1].arguments, {
        'held': RecordingState.values[i].holdsActivity,
        'state': RecordingState.values[i].name,
      });
    }
  });

  test(
    'FR-REC-10 P1-27 quit waits for stop and verified saved state',
    () async {
      status = const RecordingStatus(state: RecordingState.paused);
      final saving = Completer<void>();
      stop = () async {
        await saving.future;
        status = const RecordingStatus(state: RecordingState.saved);
        changes.add(status);
      };
      await bridge.start();
      final quit = bridge.saveAndQuit();
      await bridge.saveAndQuit(); // Duplicate tray clicks cannot stop twice.
      expect(calls.where((c) => c.method == 'quit'), isEmpty);
      saving.complete();
      await quit;
      expect(calls.map((c) => c.method), ['status', 'status', 'quit']);
    },
  );

  test('FR-REC-10 P1-27 swallowed recorder failure keeps app open', () async {
    status = const RecordingStatus(state: RecordingState.recording);
    stop = () async {
      status = const RecordingStatus(state: RecordingState.errorRecoverable);
    };
    await bridge.start();
    await bridge.saveAndQuit();
    expect(calls.map((c) => c.method), ['status', 'saveFailed']);
  });

  test(
    'FR-REC-10 P1-27 thrown save failure keeps app open and permits retry',
    () async {
      status = const RecordingStatus(state: RecordingState.recording);
      stop = () async {
        throw StateError('disk');
      };
      await bridge.start();
      await bridge.saveAndQuit();
      expect(calls.last.method, 'saveFailed');
      stop = () async {
        status = const RecordingStatus(state: RecordingState.saved);
        changes.add(status);
      };
      await bridge.saveAndQuit();
      expect(calls.last.method, 'quit');
    },
  );

  test('FR-REC-10 P1-27 absent native plugin is harmless', () async {
    messenger.setMockMethodCallHandler(channel, null);
    await bridge.start();
    await bridge.saveAndQuit();
  });

  test('FR-REC-10 P1-27 idle quit does not touch microphone', () async {
    stop = () async {
      fail('Idle quit must not stop capture');
    };
    await bridge.start();
    await bridge.saveAndQuit();
    expect(calls.map((c) => c.method), ['status', 'quit']);
  });

  test('FR-REC-10 P1-27 native save command reaches the recorder', () async {
    status = const RecordingStatus(state: RecordingState.interrupted);
    await bridge.start();
    final reply = Completer<void>();
    await messenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('saveAndQuit'),
      ),
      (_) => reply.complete(),
    );
    await reply.future;
    expect(status.state, RecordingState.saved);
    expect(calls.last.method, 'quit');
  });

  test('FR-REC-10 P1-27 native refusal restores error route', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'quit') {
        throw PlatformException(code: 'recording_open');
      }
      return null;
    });
    await bridge.start();
    await bridge.saveAndQuit();
    expect(calls.map((c) => c.method), ['status', 'quit', 'saveFailed']);
  });
}

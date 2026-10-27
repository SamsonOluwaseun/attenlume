import 'package:attenlume/domain/services/recording_state.dart';
import 'package:attenlume/platform/foreground_service/foreground_service_bridge.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FR-REC-10 ForegroundServiceAction', () {
    test(
      'FR-REC-10 fromKey parses valid actions and returns null for unknown',
      () {
        expect(
          ForegroundServiceAction.fromKey('pause'),
          ForegroundServiceAction.pause,
        );
        expect(
          ForegroundServiceAction.fromKey('resume'),
          ForegroundServiceAction.resume,
        );
        expect(
          ForegroundServiceAction.fromKey('stop'),
          ForegroundServiceAction.stop,
        );
        expect(
          ForegroundServiceAction.fromKey('bookmark'),
          ForegroundServiceAction.bookmark,
        );
        expect(
          ForegroundServiceAction.fromKey('photo'),
          ForegroundServiceAction.photo,
        );
        expect(ForegroundServiceAction.fromKey('unknown'), isNull);
        expect(ForegroundServiceAction.fromKey(null), isNull);
      },
    );
  });

  group('FR-REC-10 NoopForegroundServiceBridge', () {
    test(
      'FR-REC-10 noop bridge is never running and emits no actions',
      () async {
        const bridge = NoopForegroundServiceBridge();
        expect(bridge.isRunning, isFalse);
        expect(await bridge.actions.isEmpty, isTrue);

        const details = NotificationDetails(
          activityId: 'act-1',
          title: 'Title',
          state: RecordingState.recording,
        );
        // Calls should complete without throwing
        await bridge.startService(details);
        await bridge.updateNotification(details);
        await bridge.stopService();
        expect(bridge.isRunning, isFalse);
      },
    );
  });

  group('FR-REC-10 MethodChannelForegroundServiceBridge', () {
    late MethodChannelForegroundServiceBridge bridge;
    late List<MethodCall> methodCalls;

    setUp(() {
      methodCalls = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel(
              MethodChannelForegroundServiceBridge.channelName,
            ),
            (call) async {
              methodCalls.add(call);
              return null;
            },
          );
      bridge = MethodChannelForegroundServiceBridge();
    });

    tearDown(() async {
      await bridge.dispose();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel(
              MethodChannelForegroundServiceBridge.channelName,
            ),
            null,
          );
    });

    test('FR-REC-10 startService invokes startService with details map and sets isRunning', () async {
      final base = DateTime.utc(2026, 10, 27, 10, 0);
      final details = NotificationDetails(
        activityId: 'activity-uuid-1',
        title: 'Keynote Session',
        state: RecordingState.recording,
        elapsed: const Duration(minutes: 5),
        baseTimeUtc: base,
        message: 'Recording in progress',
      );

      await bridge.startService(details);

      expect(bridge.isRunning, isTrue);
      expect(methodCalls, hasLength(1));
      expect(methodCalls.first.method, 'startService');
      final args = methodCalls.first.arguments as Map<Object?, Object?>;
      expect(args['activityId'], 'activity-uuid-1');
      expect(args['title'], 'Keynote Session');
      expect(args['state'], 'recording');
      expect(args['elapsedMs'], 300000);
      expect(args['baseTimeMs'], base.millisecondsSinceEpoch);
      expect(args['message'], 'Recording in progress');
    });

    test(
      'FR-REC-10 updateNotification invokes updateNotification method',
      () async {
        const details = NotificationDetails(
          activityId: 'activity-uuid-1',
          title: 'Keynote Session',
          state: RecordingState.paused,
          elapsed: Duration(minutes: 5),
          message: 'Recording paused',
        );

        await bridge.updateNotification(details);

        expect(methodCalls, hasLength(1));
        expect(methodCalls.first.method, 'updateNotification');
        final args = methodCalls.first.arguments as Map<Object?, Object?>;
        expect(args['activityId'], 'activity-uuid-1');
        expect(args['state'], 'paused');
        expect(args['message'], 'Recording paused');
      },
    );

    test(
      'FR-REC-10 stopService invokes stopService and clears isRunning',
      () async {
        bridge = MethodChannelForegroundServiceBridge();
        await bridge.startService(
          const NotificationDetails(
            activityId: 'act-1',
            title: 'Title',
            state: RecordingState.recording,
          ),
        );
        expect(bridge.isRunning, isTrue);

        await bridge.stopService();
        expect(bridge.isRunning, isFalse);
        expect(methodCalls.last.method, 'stopService');
      },
    );

    test('FR-REC-10 onAction call delivers actions to stream', () async {
      final actions = <ForegroundServiceAction>[];
      final subscription = bridge.actions.listen(actions.add);

      // Simulate native calling onAction with a map
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
            MethodChannelForegroundServiceBridge.channelName,
            const StandardMethodCodec().encodeMethodCall(
              const MethodCall('onAction', {'action': 'pause'}),
            ),
            (data) {},
          );

      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
            MethodChannelForegroundServiceBridge.channelName,
            const StandardMethodCodec().encodeMethodCall(
              const MethodCall('onAction', {'action': 'resume'}),
            ),
            (data) {},
          );

      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
            MethodChannelForegroundServiceBridge.channelName,
            const StandardMethodCodec().encodeMethodCall(
              const MethodCall('onAction', {'action': 'stop'}),
            ),
            (data) {},
          );

      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
            MethodChannelForegroundServiceBridge.channelName,
            const StandardMethodCodec().encodeMethodCall(
              const MethodCall('onAction', {'action': 'bookmark'}),
            ),
            (data) {},
          );

      await Future<void>.delayed(Duration.zero);

      expect(actions, [
        ForegroundServiceAction.pause,
        ForegroundServiceAction.resume,
        ForegroundServiceAction.stop,
        ForegroundServiceAction.bookmark,
      ]);

      await subscription.cancel();
    });

    test('FR-REC-10 malformed or unrecognized actions are reported to callback and not emitted', () async {
      final malformed = <Object?>[];
      final loggingBridge = MethodChannelForegroundServiceBridge(
        onMalformed: malformed.add,
      );

      final actions = <ForegroundServiceAction>[];
      final subscription = loggingBridge.actions.listen(actions.add);

      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
            MethodChannelForegroundServiceBridge.channelName,
            const StandardMethodCodec().encodeMethodCall(
              const MethodCall('onAction', {'action': 'unknown_action'}),
            ),
            (data) {},
          );

      await Future<void>.delayed(Duration.zero);

      expect(actions, isEmpty);
      expect(malformed, hasLength(1));

      await subscription.cancel();
      await loggingBridge.dispose();
    });
  });
}

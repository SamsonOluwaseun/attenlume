import 'dart:async';

import 'package:attenlume/platform/shortcuts/shortcut_bridge.dart';
import 'package:attenlume/platform/shortcuts/shortcut_command.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _activity = 'aaaaaaaa-0000-4000-8000-000000000001';

ShortcutCommand? _parse(String uri) => ShortcutCommand.parse(Uri.parse(uri));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('P0-13 FR-HF-05 deep link parsing', () {
    test('every documented URI maps to its action', () {
      expect(
        _parse('attenlume://record/start')?.action,
        ShortcutAction.startRecording,
      );
      expect(
        _parse('attenlume://record/stop')?.action,
        ShortcutAction.stopRecording,
      );
      expect(
        _parse('attenlume://record/toggle')?.action,
        ShortcutAction.toggleRecording,
      );
      expect(_parse('attenlume://bookmark')?.action, ShortcutAction.bookmark);
      expect(_parse('attenlume://photo')?.action, ShortcutAction.takePhoto);
      expect(
        _parse('attenlume://conversation/new')?.action,
        ShortcutAction.newConversation,
      );
    });

    test('scheme and host are case-insensitive and a trailing slash is '
        'accepted', () {
      expect(
        _parse('ATTENLUME://Record/start/')?.action,
        ShortcutAction.startRecording,
      );
    });

    test('anything else is dropped, never guessed at', () {
      expect(_parse('conferencecompanion://record/start'), isNull);
      expect(_parse('https://attenlume.app/record/start'), isNull);
      expect(_parse('attenlume://record'), isNull);
      expect(_parse('attenlume://record/delete'), isNull);
      expect(_parse('attenlume://record/start/now'), isNull);
      expect(_parse('attenlume://bookmark/extra'), isNull);
      expect(_parse('attenlume://export'), isNull);
    });

    test('source defaults to deep link and reads known keys', () {
      expect(
        _parse('attenlume://record/start')?.source,
        ShortcutSource.deepLink,
      );
      expect(
        _parse('attenlume://record/toggle?source=tile')?.source,
        ShortcutSource.quickSettingsTile,
      );
      expect(
        _parse('attenlume://bookmark?source=app_intent')?.source,
        ShortcutSource.appIntent,
      );
      expect(
        _parse('attenlume://record/stop?source=app_shortcut')?.source,
        ShortcutSource.appShortcut,
      );
      expect(
        _parse('attenlume://record/stop?source=somewhere')?.source,
        ShortcutSource.deepLink,
      );
    });

    test('activity is kept only when it is a UUID v4', () {
      expect(
        _parse('attenlume://record/start?activity=$_activity')?.activityId,
        _activity,
      );
      expect(
        _parse('attenlume://record/start?activity=${_activity.toUpperCase()}')
            ?.activityId,
        _activity,
      );
      expect(
        _parse('attenlume://record/start?activity=../../etc')?.activityId,
        isNull,
      );
      expect(
        _parse('attenlume://record/start?activity=12345')?.activityId,
        isNull,
      );
    });

    test('toUri round-trips through parse', () {
      for (final action in ShortcutAction.values) {
        final c = ShortcutCommand(
          action: action,
          source: ShortcutSource.appIntent,
          activityId: _activity,
        );
        final back = ShortcutCommand.parse(c.toUri())!;
        expect(back.action, action);
        expect(back.source, ShortcutSource.appIntent);
        expect(back.activityId, _activity);
      }
    });
  });

  group('P0-13 FR-HF-04 channel payload', () {
    test('reads time, cold start, visibility and direct delivery', () {
      final c = ShortcutCommand.fromChannel({
        'uri': 'attenlume://record/toggle?source=tile',
        'triggeredAtMs': 1793782800000,
        'coldStart': true,
        'appVisible': false,
        'direct': true,
      })!;
      expect(c.action, ShortcutAction.toggleRecording);
      expect(c.source, ShortcutSource.quickSettingsTile);
      expect(
        c.triggeredAt,
        DateTime.fromMillisecondsSinceEpoch(1793782800000, isUtc: true),
      );
      expect(c.coldStart, isTrue);
      expect(c.appVisibleAtTrigger, isFalse);
      expect(c.deliveredDirect, isTrue);
    });

    test('missing optional fields stay unknown', () {
      final c = ShortcutCommand.fromChannel({'uri': 'attenlume://bookmark'})!;
      expect(c.triggeredAt, isNull);
      expect(c.coldStart, isFalse);
      expect(c.appVisibleAtTrigger, isNull);
      expect(c.deliveredDirect, isFalse);
    });

    test('malformed payloads are rejected', () {
      expect(ShortcutCommand.fromChannel(null), isNull);
      expect(ShortcutCommand.fromChannel('attenlume://bookmark'), isNull);
      expect(ShortcutCommand.fromChannel({'uri': 42}), isNull);
      expect(ShortcutCommand.fromChannel({'uri': 'attenlume://nope'}), isNull);
    });
  });

  group('P0-13 MethodChannelShortcutBridge', () {
    const channel = MethodChannel('test/shortcuts');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final calls = <MethodCall>[];
    Object? initialReply;

    setUp(() {
      calls.clear();
      initialReply = null;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return call.method == 'takeInitialCommand' ? initialReply : null;
      });
    });

    tearDown(() => messenger.setMockMethodCallHandler(channel, null));

    Future<Object?> fromNative(String method, Object? arguments) {
      final reply = Completer<Object?>();
      messenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(
          MethodCall(method, arguments),
        ),
        (data) => reply.complete(
          data == null
              ? null
              : const StandardMethodCodec().decodeEnvelope(data),
        ),
      );
      return reply.future;
    }

    test('takes the initial command once the native side has one', () async {
      final bridge = MethodChannelShortcutBridge(channel: channel);
      initialReply = {
        'uri': 'attenlume://record/start?source=app_intent',
        'coldStart': true,
      };
      final c = await bridge.takeInitialCommand();
      expect(c?.action, ShortcutAction.startRecording);
      expect(c?.coldStart, isTrue);
      initialReply = null;
      expect(await bridge.takeInitialCommand(), isNull);
      await bridge.dispose();
    });

    test('commands from native reach the stream; malformed ones are '
        'reported and refused', () async {
      final malformed = <Object?>[];
      final bridge = MethodChannelShortcutBridge(
        channel: channel,
        onMalformed: malformed.add,
      );
      final received = <ShortcutCommand>[];
      final sub = bridge.commands.listen(received.add);

      expect(
        await fromNative('command', {'uri': 'attenlume://bookmark'}),
        isTrue,
      );
      expect(
        await fromNative('command', {'uri': 'attenlume://format/disk'}),
        isFalse,
      );
      await Future<void>.delayed(Duration.zero);

      expect(received.single.action, ShortcutAction.bookmark);
      expect(malformed, hasLength(1));
      await sub.cancel();
      await bridge.dispose();
    });

    test('setTileDirect sends the flag', () async {
      final bridge = MethodChannelShortcutBridge(channel: channel);
      await bridge.setTileDirect(true);
      expect(calls.single.method, 'setTileDirect');
      expect(calls.single.arguments, {'direct': true});
      await bridge.dispose();
    });

    test(
      'a platform without the channel gives no command and no error',
      () async {
        messenger.setMockMethodCallHandler(channel, null);
        final bridge = MethodChannelShortcutBridge(channel: channel);
        expect(await bridge.takeInitialCommand(), isNull);
        await bridge.setTileDirect(true);
        await bridge.dispose();
      },
    );

    test('NoShortcutBridge is silent', () async {
      const bridge = NoShortcutBridge();
      expect(await bridge.takeInitialCommand(), isNull);
      expect(await bridge.commands.isEmpty, isTrue);
    });
  });
}

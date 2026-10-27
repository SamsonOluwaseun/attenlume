import 'package:attenlume/platform/storage/method_channel_free_space_probe.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channelName = 'com.samlytics.attenlume/free_space';
  final log = <MethodCall>[];

  setUp(log.clear);

  group('FR-STO-01 MethodChannelFreeSpaceProbe [P1-12]', () {
    test(
      'FR-STO-01 invokes queryFreeSpace and parses available and total bytes',
      () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(const MethodChannel(channelName), (
              call,
            ) async {
              log.add(call);
              if (call.method == 'queryFreeSpace') {
                return {
                  'availableBytes': 10 * 1024 * 1024 * 1024,
                  'totalBytes': 64 * 1024 * 1024 * 1024,
                };
              }
              return null;
            });

        const probe = MethodChannelFreeSpaceProbe();
        final space = await probe.query('/data/user/0/app/media');

        expect(log, hasLength(1));
        expect(log.single.method, 'queryFreeSpace');
        expect(log.single.arguments, {'path': '/data/user/0/app/media'});
        expect(space, isNotNull);
        expect(space!.availableBytes, 10 * 1024 * 1024 * 1024);
        expect(space.totalBytes, 64 * 1024 * 1024 * 1024);
      },
    );

    test(
      'FR-STO-01 returns null when method channel returns null or empty',
      () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel(channelName),
              (call) async => null,
            );

        const probe = MethodChannelFreeSpaceProbe();
        final space = await probe.query('/non/existent');
        expect(space, isNull);
      },
    );

    test('FR-STO-01 returns null when method channel throws error', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel(channelName), (
            call,
          ) async {
            throw PlatformException(
              code: 'STATFS_FAILED',
              message: 'I/O Error',
            );
          });

      const probe = MethodChannelFreeSpaceProbe();
      final space = await probe.query('/faulty/path');
      expect(space, isNull);
    });
  });
}

import 'package:attenlume/domain/services/recording_state.dart';
import 'package:attenlume/shared/utilities/serial_lock.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FR-REC-09 recording state machine', () {
    test('FR-REC-09 every path in the build guide diagram is allowed', () {
      const paths = [
        [
          RecordingState.idle,
          RecordingState.starting,
          RecordingState.recording,
        ],
        [
          RecordingState.recording,
          RecordingState.paused,
          RecordingState.recording,
        ],
        [
          RecordingState.recording,
          RecordingState.switchingSegment,
          RecordingState.recording,
        ],
        [
          RecordingState.recording,
          RecordingState.interrupted,
          RecordingState.recovering,
          RecordingState.recording,
        ],
        [
          RecordingState.interrupted,
          RecordingState.userResumeRequired,
          RecordingState.recording,
        ],
        [
          RecordingState.recording,
          RecordingState.stopping,
          RecordingState.saved,
        ],
        [RecordingState.paused, RecordingState.stopping],
        [RecordingState.interrupted, RecordingState.stopping],
        [
          RecordingState.recording,
          RecordingState.storageStop,
          RecordingState.saved,
        ],
      ];
      for (final path in paths) {
        for (var i = 0; i + 1 < path.length; i++) {
          expect(
            canTransition(path[i], path[i + 1]),
            isTrue,
            reason: '${path[i].name} -> ${path[i + 1].name}',
          );
        }
      }
    });

    test('FR-REC-09 any state can fall to error recoverable', () {
      for (final from in RecordingState.values) {
        expect(canTransition(from, RecordingState.errorRecoverable), isTrue);
      }
    });

    test('FR-REC-09 shortcuts that skip a step are rejected', () {
      expect(
        canTransition(RecordingState.idle, RecordingState.recording),
        isFalse,
      );
      expect(
        canTransition(RecordingState.saved, RecordingState.recording),
        isFalse,
      );
      expect(
        canTransition(RecordingState.paused, RecordingState.saved),
        isFalse,
      );
      expect(
        canTransition(RecordingState.interrupted, RecordingState.recording),
        isFalse,
      );
      expect(
        canTransition(RecordingState.stopping, RecordingState.recording),
        isFalse,
      );
      expect(
        canTransition(RecordingState.idle, RecordingState.stopping),
        isFalse,
      );
    });

    test('FR-REC-09 only idle and saved leave the recorder free (NFR-04)', () {
      final free = RecordingState.values.where((s) => !s.holdsActivity);
      expect(free, {RecordingState.idle, RecordingState.saved});
    });
  });

  group('FR-REC-09 serial lock', () {
    test('FR-REC-09 actions run one at a time in request order', () async {
      final lock = SerialLock();
      final log = <String>[];
      Future<int> step(String name, int value) => lock.run(() async {
        log.add('$name start');
        await Future<void>.delayed(const Duration(milliseconds: 5));
        log.add('$name end');
        return value;
      });

      final results = await Future.wait([step('a', 1), step('b', 2)]);

      expect(results, [1, 2]);
      expect(log, ['a start', 'a end', 'b start', 'b end']);
      expect(lock.isBusy, isFalse);
    });

    test('FR-REC-09 a failing action does not block the queue', () async {
      final lock = SerialLock();
      final failed = lock.run<void>(() async => throw StateError('boom'));
      final next = lock.run(() async => 'ok');

      await expectLater(failed, throwsStateError);
      expect(await next, 'ok');
    });
  });
}

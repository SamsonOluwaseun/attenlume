import 'package:attenlume/domain/models/enums.dart';
import 'package:attenlume/domain/models/media.dart';
import 'package:attenlume/domain/services/review_timeline.dart';
import 'package:attenlume/features/playback_review/review_player_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fixtures/fake_playback_engine.dart';

final _t0 = DateTime.utc(2026, 11, 4, 9, 30);

RecordingSegment _segment(int sequence, int atMin, int lengthMin) =>
    RecordingSegment(
      id: 'seg-$sequence',
      activityId: 'act',
      sequence: sequence,
      filePath: 'seg-$sequence.m4a',
      state: SegmentState.finalised,
      requestedProfile: RecordingProfile.balanced,
      codec: 'aac_lc',
      container: 'm4a',
      channelCount: 1,
      sampleRateHz: 48000,
      requestedBitrateBps: 48000,
      startUtc: _t0.add(Duration(minutes: atMin)),
      durationMs: lengthMin * 60000,
      createdAt: _t0,
      updatedAt: _t0,
    );

void main() {
  late FakePlaybackEngine engine;
  late ReviewPlayerController player;

  setUp(() {
    engine = FakePlaybackEngine();
    // 0:00 to 10:00, a 3-minute gap, then 13:00 to 20:00.
    player = ReviewPlayerController(
      timeline: ReviewTimeline.build(
        segments: [_segment(1, 0, 10), _segment(2, 13, 7)],
      ),
      engine: engine,
      resolvePath: (s) async => '/media/${s.filePath}',
    );
  });

  tearDown(() => player.dispose());

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  group('FR-REV-01 review player [P1-17]', () {
    test('FR-REV-01 play opens the first segment, pause stops it', () async {
      await player.play();
      expect(engine.calls, ['open /media/seg-1.m4a', 'seek 0', 'play']);
      expect(player.isPlaying, isTrue);

      await player.togglePlay();
      expect(engine.playing, isFalse);
      expect(player.isPlaying, isFalse);
    });

    test(
      'FR-REV-01 runs from one segment into the next across the gap',
      () async {
        await player.play();
        engine.emitPosition(const Duration(minutes: 9, seconds: 59));
        await settle();
        expect(player.positionMs, 599000);

        engine.complete();
        await settle();
        await settle();
        expect(engine.openPath, '/media/seg-2.m4a');
        expect(engine.calls.last, 'play');
        expect(player.positionMs, 780000, reason: 'jumps the gap');

        engine.emitPosition(const Duration(minutes: 7));
        engine.complete();
        await settle();
        await settle();
        expect(player.isPlaying, isFalse, reason: 'stops after the last part');
        expect(player.positionMs, 1200000);

        // Play again starts from the beginning.
        await player.play();
        expect(engine.openPath, '/media/seg-1.m4a');
        expect(player.positionMs, 0);
      },
    );

    test('FR-REV-01 scrubbing into a gap lands on the next segment', () async {
      await player.seekTo(700000);
      expect(engine.openPath, '/media/seg-2.m4a');
      expect(engine.seekedTo, Duration.zero);
      expect(player.positionMs, 780000);

      await player.seekTo(120000);
      expect(engine.openPath, '/media/seg-1.m4a');
      expect(engine.seekedTo, const Duration(minutes: 2));
    });

    test(
      'FR-REV-01 skips 15 seconds of audio, across the gap and clamped',
      () async {
        await player.seekTo(785000); // 5 s into the second segment.
        await player.skipBack();
        expect(engine.openPath, '/media/seg-1.m4a');
        expect(player.positionMs, 590000, reason: 'the last 15 s heard');

        await player.skipForward();
        expect(player.positionMs, 785000);

        await player.seekTo(5000);
        await player.skipBack();
        expect(player.positionMs, 0);

        await player.seekTo(1195000);
        await player.skipForward();
        expect(player.positionMs, 1200000);
      },
    );

    test('FR-REV-01 speed control cycles through the speeds', () async {
      expect(player.speed, 1.0);
      await player.cycleSpeed();
      expect(player.speed, 1.25);
      expect(engine.speed, 1.25);
      await player.setSpeed(2.0);
      await player.cycleSpeed();
      expect(player.speed, 0.75);
    });

    test('FR-REV-01 a segment that will not open says so and stops', () async {
      engine.broken.add('/media/seg-1.m4a');
      await player.play();
      expect(player.isPlaying, isFalse);
      expect(player.error, 'Part 1 of this recording could not be opened.');

      // The other part still plays.
      await player.seekTo(800000);
      await player.play();
      expect(player.isPlaying, isTrue);
      expect(player.error, isNull);
    });

    test('FR-REV-01 dispose releases the player', () async {
      final other = ReviewPlayerController(
        timeline: ReviewTimeline.build(segments: [_segment(1, 0, 1)]),
        engine: FakePlaybackEngine(),
        resolvePath: (s) async => s.filePath,
      );
      final otherEngine = other.engine as FakePlaybackEngine;
      other.dispose();
      await settle();
      expect(otherEngine.disposed, isTrue);
    });
  });

  group('FR-REV-04 cut ranges while playing [P1-18]', () {
    CutRange cut(String id, int startMs, int endMs) => CutRange(
      id: id,
      activityId: 'act',
      startOffsetMs: startMs,
      endOffsetMs: endMs,
      createdAt: _t0,
      updatedAt: _t0,
    );

    test('FR-REV-04 play starts after a trimmed start', () async {
      player.cutRanges = [cut('c1', 0, 30000)];
      await player.play();
      expect(engine.seekedTo, const Duration(seconds: 30));
      expect(player.positionMs, 30000);
      expect(player.isPlaying, isTrue);
    });

    test('FR-REV-04 reaching a middle cut jumps to its end, across the '
        'gap when the cut runs into it', () async {
      player.cutRanges = [cut('c1', 9 * 60000, 14 * 60000)];
      await player.play();
      engine.emitPosition(const Duration(minutes: 9, seconds: 1));
      await settle();
      await settle();
      expect(engine.openPath, '/media/seg-2.m4a');
      expect(engine.seekedTo, const Duration(minutes: 1));
      expect(player.positionMs, 14 * 60000);
      expect(player.isPlaying, isTrue);
    });

    test('FR-REV-04 a trimmed end stops playback', () async {
      player.cutRanges = [cut('c1', 18 * 60000, 20 * 60000)];
      await player.seekTo(17 * 60000);
      await player.play();
      engine.emitPosition(const Duration(minutes: 5, seconds: 1));
      await settle();
      await settle();
      expect(player.isPlaying, isFalse);
      expect(engine.playing, isFalse);
      expect(player.positionMs, 20 * 60000);
    });

    test('FR-REV-04 overlapping and removed cuts are merged or ignored; '
        'kept time leaves them out', () {
      player.cutRanges = [
        cut('c1', 0, 60000),
        cut('c2', 30000, 120000),
        CutRange(
          id: 'c3',
          activityId: 'act',
          startOffsetMs: 300000,
          endOffsetMs: 400000,
          deletedAt: _t0,
          createdAt: _t0,
          updatedAt: _t0,
        ),
      ];
      expect(player.cuts, hasLength(1));
      expect(player.keptAudioMs, 17 * 60000 - 120000);
    });

    test(
      'FR-REV-04 the playhead can be put inside a cut while paused',
      () async {
        player.cutRanges = [cut('c1', 60000, 120000)];
        await player.seekTo(90000);
        expect(player.positionMs, 90000);
        await player.play();
        expect(player.positionMs, 120000);
      },
    );
  });
}

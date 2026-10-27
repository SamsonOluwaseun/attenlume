import 'dart:io';

import 'package:attenlume/app/theme/app_theme.dart';
import 'package:attenlume/data/filesystem/media_paths.dart';
import 'package:attenlume/data/local_database/database_provider.dart';
import 'package:attenlume/data/repositories/repository_providers.dart';
import 'package:attenlume/domain/models/activity.dart';
import 'package:attenlume/domain/models/enums.dart';
import 'package:attenlume/domain/models/media.dart';
import 'package:attenlume/domain/services/capture_settings.dart';
import 'package:attenlume/features/capture/recording_providers.dart';
import 'package:attenlume/features/playback_review/review_screen.dart';
import 'package:attenlume/platform/storage/free_space_probe.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fixtures/fake_playback_engine.dart';
import '../../fixtures/fixtures.dart';
import '../../fixtures/mp4_fixture.dart';

void main() {
  late TestData t;
  late Directory root;
  late Activity activity;
  late RecordingSegment segment;
  final start = DateTime.utc(2026, 11, 4, 9, 30);

  setUp(() async {
    t = TestData(start: start);
    root = Directory.systemTemp.createTempSync('permanent_trim_widget_');
  });

  tearDown(() async {
    await t.close();
    root.deleteSync(recursive: true);
  });

  /// One real 10 s fixture recording with the first 2 s cut.
  Future<void> build() async {
    final conference = await t.conference();
    activity = await t.activity(conference.id, title: 'Keynote');
    final path = MediaPaths.segment(conference.id, activity.id, 1);
    final file = MediaPaths.resolve(root, path);
    await file.parent.create(recursive: true);
    await writeMp4Fixture(file);
    final s = await t.media.startSegment(
      activityId: activity.id,
      filePath: path,
      requestedProfile: RecordingProfile.balanced,
      codec: 'aac_lc',
      container: 'm4a',
      channelCount: 1,
      sampleRateHz: 48000,
      requestedBitrateBps: 64000,
      startUtc: start,
    );
    segment = await t.media.finaliseSegment(
      s.id,
      endUtc: start.add(const Duration(seconds: 10)),
      endReason: SegmentEndReason.userStop,
      durationMs: 10000,
      bytes: file.lengthSync(),
    );
    await t.cuts.add(
      activity.id,
      startOffsetMs: 0,
      endOffsetMs: 2000,
      reason: 'Trim start',
    );
  }

  Widget subject(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    return ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(t.db),
        conferenceRepositoryProvider.overrideWithValue(t.conferences),
        activityRepositoryProvider.overrideWithValue(t.activities),
        mediaAssetRepositoryProvider.overrideWithValue(t.media),
        cutRangeRepositoryProvider.overrideWithValue(t.cuts),
        capturePlatformProvider.overrideWithValue(CapturePlatform.android),
        mediaFreeBytesProvider.overrideWith((ref) async => null),
        mediaRootProvider.overrideWithValue(() async => root),
        freeSpaceProbeProvider.overrideWithValue(const UnknownFreeSpaceProbe()),
        audioPlaybackEngineFactoryProvider.overrideWithValue(
          FakePlaybackEngine.new,
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: ReviewScreen(activityId: activity.id),
      ),
    );
  }

  Future<void> settle(WidgetTester tester, {int rounds = 8}) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  /// Pumps until [finder] shows: the trim does many real file reads, and
  /// each needs a pump to come back in the test zone.
  Future<void> settleUntil(WidgetTester tester, Finder finder) async {
    for (var i = 0; i < 400 && finder.evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(finder, findsOneWidget);
  }

  Future<void> openConfirm(WidgetTester tester) async {
    final button = find.byKey(const Key('trim-apply-permanently'));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await settle(tester);
    expect(find.text('Apply trims permanently?'), findsOneWidget);
    expect(find.textContaining('0:02 removed, 0:08 left'), findsOneWidget);
  }

  group('FR-REV-06 apply trims permanently on the review screen [P1-19]', () {
    testWidgets('FR-REV-06 confirm writes new files, then keeping the '
        'originals leaves them on disk', (tester) async {
      await tester.runAsync(build);
      await tester.pumpWidget(subject(tester));
      await settle(tester);

      await openConfirm(tester);
      await tester.tap(find.byKey(const Key('apply-trim-confirm')));
      await settleUntil(tester, find.text('Remove the originals?'));

      expect(find.text('Remove the originals?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('keep-originals')));
      await settle(tester);
      expect(
        find.text('Trims applied. Your originals are kept.'),
        findsOneWidget,
      );

      final rows = await tester.runAsync(
        () => t.media.segmentsFor(activity.id),
      );
      expect(rows!.single.filePath, endsWith('segment-001-trim-1.m4a'));
      final kept = Directory(
        MediaPaths.resolve(
          root,
          MediaPaths.originalsFolder(activity.conferenceId, activity.id),
        ).path,
      );
      expect(kept.listSync(), hasLength(1));
    });

    testWidgets('FR-REV-06 removing the originals deletes them', (
      tester,
    ) async {
      await tester.runAsync(build);
      await tester.pumpWidget(subject(tester));
      await settle(tester);

      await openConfirm(tester);
      await tester.tap(find.byKey(const Key('apply-trim-confirm')));
      await settleUntil(tester, find.text('Remove the originals?'));
      await tester.tap(find.byKey(const Key('remove-originals')));
      await settle(tester);

      expect(find.text('Trims applied. Originals removed.'), findsOneWidget);
      expect(MediaPaths.resolve(root, segment.filePath).existsSync(), isFalse);
      final kept = Directory(
        MediaPaths.resolve(
          root,
          MediaPaths.originalsFolder(activity.conferenceId, activity.id),
        ).path,
      );
      expect(kept.listSync(), isEmpty);
    });

    testWidgets('FR-REV-06 cancelling changes nothing', (tester) async {
      await tester.runAsync(build);
      await tester.pumpWidget(subject(tester));
      await settle(tester);

      await openConfirm(tester);
      await tester.tap(find.text('Cancel'));
      await settle(tester);

      final rows = await tester.runAsync(
        () => t.media.segmentsFor(activity.id),
      );
      expect(rows!.single.filePath, segment.filePath);
      expect(MediaPaths.resolve(root, segment.filePath).existsSync(), isTrue);
    });
  });
}

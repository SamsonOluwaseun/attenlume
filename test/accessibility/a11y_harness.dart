import 'dart:async';
import 'dart:io';

import 'package:attenlume/app/theme/app_theme.dart';
import 'package:attenlume/data/local_database/database_provider.dart';
import 'package:attenlume/data/repositories/repository_providers.dart';
import 'package:attenlume/domain/services/capture_settings.dart';
import 'package:attenlume/domain/services/device_timezone.dart';
import 'package:attenlume/domain/services/one_active_coordinator.dart';
import 'package:attenlume/domain/services/recording_service.dart';
import 'package:attenlume/domain/services/recording_state.dart';
import 'package:attenlume/features/capture/recording_providers.dart';
import 'package:attenlume/features/playback_review/review_screen.dart';
import 'package:attenlume/features/storage_manager/storage_manager_providers.dart';
import 'package:attenlume/platform/storage/free_space_probe.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../fixtures/fake_capture_engine.dart';
import '../fixtures/fake_photo_camera.dart';
import '../fixtures/fake_playback_engine.dart';
import '../fixtures/fake_timers.dart';
import '../fixtures/fixtures.dart';

/// Shared set-up for the NFR-09 accessibility suite [P1-26].
///
/// Real database and file work runs only inside `tester.runAsync`
/// ([A11yHarness.io] and [A11yHarness.settle]); widget tests that do I/O on
/// the fake clock hang.

class _FixedFreeSpace implements FreeSpaceProbe {
  const _FixedFreeSpace();

  @override
  Future<FreeSpace?> query(String path) async =>
      const FreeSpace(availableBytes: 50 << 30, totalBytes: 128 << 30);
}

class _LondonTimezone extends DeviceTimezoneService {
  const _LondonTimezone();

  @override
  Future<String> detectTimezone() async => 'Europe/London';
}

/// Phone (360 x 800 dp) and tablet (1280 x 800 dp) sizes.
enum A11ySize {
  phone(Size(1080, 2400), 3),
  tablet(Size(1280, 800), 1);

  const A11ySize(this.physical, this.ratio);
  final Size physical;
  final double ratio;
}

class A11yHarness {
  A11yHarness(this.tester);

  final WidgetTester tester;
  late final TestData t;
  late final Directory root;
  late final RecordingService recorder;
  late final OneActiveCoordinator oneActive;
  final engine = FakeCaptureEngine()..level = -20;
  final camera = FakePhotoCamera();
  final player = FakePlaybackEngine();

  Future<void> setUp() async {
    t = TestData();
    root = await tester.runAsync(
      () => Directory.systemTemp.createTemp('a11y_test_'),
    ) as Directory;
    recorder = RecordingService(
      engine: engine,
      activities: t.activities,
      media: t.media,
      mediaRoot: () async => root,
      platform: CapturePlatform.android,
      clock: () => t.clock(),
      rollTimer: FakeTimers().call,
      hashFile: (_) async => 'hash',
    );
    oneActive = OneActiveCoordinator(
      recorder: recorder,
      activities: t.activities,
      media: t.media,
      confirmations: InAppTriggerConfirmations(),
      clock: () => t.clock(),
    );
  }

  Future<void> tearDown() async {
    await tester.pumpWidget(const SizedBox());
    var done = false;
    unawaited(
      () async {
        await recorder.dispose();
        await t.close();
      }().whenComplete(() => done = true),
    );
    for (var i = 0; i < 200 && !done; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    await tester.runAsync(() async {
      if (root.existsSync()) await root.delete(recursive: true);
    });
  }

  /// Runs real I/O off the fake clock.
  Future<T> io<T>(Future<T> Function() work) async =>
      (await tester.runAsync(work)) as T;

  void size(A11ySize s, {double textScale = 1}) {
    tester.view.physicalSize = s.physical;
    tester.view.devicePixelRatio = s.ratio;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(() {
      tester.view.reset();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });
  }

  List<Override> get overrides => [
    appDatabaseProvider.overrideWithValue(t.db),
    settingsRepositoryProvider.overrideWithValue(t.settings),
    conferenceRepositoryProvider.overrideWithValue(t.conferences),
    activityRepositoryProvider.overrideWithValue(t.activities),
    mediaAssetRepositoryProvider.overrideWithValue(t.media),
    cutRangeRepositoryProvider.overrideWithValue(t.cuts),
    exportJobRepositoryProvider.overrideWithValue(t.exports),
    deviceTimezoneServiceProvider.overrideWithValue(const _LondonTimezone()),
    audioCaptureEngineProvider.overrideWithValue(engine),
    photoCameraProvider.overrideWithValue(camera),
    capturePlatformProvider.overrideWithValue(CapturePlatform.android),
    mediaRootProvider.overrideWithValue(() async => root),
    storageTempRootProvider.overrideWithValue(() async => root),
    freeSpaceProbeProvider.overrideWithValue(const _FixedFreeSpace()),
    mediaFreeBytesProvider.overrideWith((ref) async => 500 * 1024 * 1024),
    recordingServiceProvider.overrideWithValue(recorder),
    oneActiveCoordinatorProvider.overrideWithValue(oneActive),
    audioPlaybackEngineFactoryProvider.overrideWithValue(() => player),
  ];

  Widget app(
    Widget home, {
    ThemeData? theme,
    List<Override> extra = const [],
    RecordingStatus? status,
  }) => ProviderScope(
    overrides: [
      ...overrides,
      if (status != null)
        recordingStatusProvider.overrideWith((ref) => Stream.value(status)),
      ...extra,
    ],
    child: MaterialApp(theme: theme ?? AppTheme.light(), home: home),
  );

  /// Pumps frames and lets real work finish between them.
  Future<void> settle([int rounds = 10]) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
  }
}

/// Checks the four Flutter accessibility guidelines on what is on screen
/// (NFR-09): Android and iOS tap target sizes, labelled tap targets and
/// text contrast.
Future<void> expectMeetsGuidelines(
  WidgetTester tester, {
  bool contrast = true,
}) async {
  await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
  await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  if (contrast) {
    await expectLater(tester, meetsGuideline(textContrastGuideline));
  }
}

/// Scrolls through every scrollable on screen at 200% text so each part is
/// laid out; an overflow anywhere fails the test.
Future<void> scrollThrough(WidgetTester tester, A11yHarness h) async {
  final scrollables = find.byType(Scrollable);
  final count = scrollables.evaluate().length;
  for (var i = 0; i < count; i++) {
    final s = scrollables.at(i);
    if (s.evaluate().isEmpty) continue;
    final state = tester.state<ScrollableState>(s);
    if (state.axisDirection == AxisDirection.left ||
        state.axisDirection == AxisDirection.right) {
      continue;
    }
    final max = state.position.maxScrollExtent;
    var pos = 0.0;
    while (pos < max && max.isFinite) {
      pos += 400;
      state.position.jumpTo(pos.clamp(0, max));
      await h.settle(2);
    }
  }
}

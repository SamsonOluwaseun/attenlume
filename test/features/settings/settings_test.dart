import 'dart:io';

import 'package:attenlume/app/app_version.dart';
import 'package:attenlume/data/filesystem/photo_processor.dart';
import 'package:attenlume/data/local_database/database_provider.dart';
import 'package:attenlume/data/repositories/repository_providers.dart';
import 'package:attenlume/data/repositories/settings_repository.dart';
import 'package:attenlume/domain/models/enums.dart';
import 'package:attenlume/domain/services/capture_settings.dart';
import 'package:attenlume/domain/services/photo_capture_service.dart';
import 'package:attenlume/domain/services/recording_service.dart';
import 'package:attenlume/domain/services/recording_state.dart';
import 'package:attenlume/domain/services/safety_prompt_service.dart';
import 'package:attenlume/features/capture/recording_providers.dart';
import 'package:attenlume/features/conferences/conference_list_screen.dart';
import 'package:attenlume/features/guide/quick_guide_screen.dart';
import 'package:attenlume/features/privacy/privacy_screen.dart';
import 'package:attenlume/features/settings/settings_providers.dart';
import 'package:attenlume/features/settings/settings_screen.dart';
import 'package:attenlume/features/storage_manager/storage_manager_screen.dart';
import 'package:attenlume/platform/diagnostics/battery_probe.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import '../../fixtures/fake_capture_engine.dart';
import '../../fixtures/fake_photo_camera.dart';
import '../../fixtures/fixtures.dart';

void main() {
  late TestData t;

  setUp(() => t = TestData());
  tearDown(() => t.close());

  group('5.11 settings persist', () {
    test('FR-QUAL-02 5.11 the default profile set in Settings is copied '
        'into a new conference', () async {
      expect(
        await t.settings.globalDefaultRecordingProfile(),
        RecordingProfile.balanced,
      );
      await t.settings.setGlobalDefaultRecordingProfile(
        RecordingProfile.enhanced,
      );

      final conf = await t.conference();

      expect(conf.defaultRecordingProfile, RecordingProfile.enhanced);
    });

    test('FR-REC-06 5.11 safety thresholds default to 2 hours, 10 minutes '
        'and 15%', () async {
      final thresholds = await t.settings.safetyThresholds();
      expect(thresholds.longRecording, const Duration(hours: 2));
      expect(thresholds.silence, const Duration(minutes: 10));
      expect(thresholds.lowBatteryPercent, 15);
    });

    test('FR-REC-06 5.11 safety thresholds are saved', () async {
      await t.settings.setSafetyLongRecording(const Duration(hours: 3));
      await t.settings.setSafetySilence(const Duration(minutes: 30));
      await t.settings.setSafetyLowBatteryPercent(20);

      final thresholds = await SettingsRepository(t.db).safetyThresholds();
      expect(thresholds.longRecording, const Duration(hours: 3));
      expect(thresholds.silence, const Duration(minutes: 30));
      expect(thresholds.lowBatteryPercent, 20);
      expect(thresholds.silenceDbfs, const SafetyThresholds().silenceDbfs);
    });

    test('FR-REC-06 5.11 a damaged threshold reads as the default, never '
        'as off', () async {
      await t.db.writeSetting(
        SettingsRepository.safetyLongRecordingMinutesKey,
        '0',
      );
      await t.db.writeSetting(SettingsRepository.safetySilenceMinutesKey, 'x');
      await t.db.writeSetting(
        SettingsRepository.safetyLowBatteryPercentKey,
        '0',
      );

      final thresholds = await t.settings.safetyThresholds();
      expect(thresholds.longRecording, const Duration(hours: 2));
      expect(thresholds.silence, const Duration(minutes: 10));
      expect(thresholds.lowBatteryPercent, 15);
    });

    test('FR-PHO-02 5.11 photos are space saving unless keep highest '
        'quality is turned on', () async {
      expect((await t.settings.photoQuality()).keepOriginal, isFalse);
      expect((await t.settings.photoQuality()).maxLongEdge, 2048);

      await t.settings.setPhotoKeepHighestQuality(true);

      expect(await SettingsRepository(t.db).photoKeepHighestQuality(), isTrue);
      expect((await t.settings.photoQuality()).keepOriginal, isTrue);
    });

    test('5.11 theme follows the device unless changed', () async {
      expect(await t.settings.themeMode(), ThemeMode.system);
      await t.settings.setThemeMode(ThemeMode.dark);
      expect(await SettingsRepository(t.db).themeMode(), ThemeMode.dark);
    });
  });

  group('5.11 settings take effect', () {
    test('FR-PHO-02 5.11 the photo service uses the photo quality chosen '
        'in Settings for each photo', () async {
      final root = await Directory.systemTemp.createTemp('settings_photo_');
      addTearDown(() => root.delete(recursive: true));
      final used = <PhotoQuality>[];
      final service = PhotoCaptureService(
        camera: FakePhotoCamera()
          ..photoData = img.encodeJpg(img.Image(width: 300, height: 200)),
        activities: t.activities,
        media: t.media,
        mediaRoot: () async => root,
        qualitySource: t.settings.photoQuality,
        process:
            ({
              required File photo,
              required File thumbnail,
              PhotoQuality quality = const PhotoQuality(),
            }) async {
              used.add(quality);
              return const ProcessedPhoto(bytes: 1, sha256: 'hash');
            },
      );
      final conf = await t.conference();
      final act = await t.activity(conf.id);

      final first = await service.capture(act.id);
      await t.settings.setPhotoKeepHighestQuality(true);
      final second = await service.capture(act.id);

      expect(used.map((q) => q.keepOriginal), [false, true]);
      expect(first.originalKept, isFalse);
      expect(second.originalKept, isTrue);
    });

    test('FR-REC-06 5.11 the safety prompt service uses the thresholds '
        'saved in Settings and follows changes', () async {
      final root = await Directory.systemTemp.createTemp('settings_safety_');
      addTearDown(() => root.delete(recursive: true));
      final engine = FakeCaptureEngine();
      final recorder = RecordingService(
        engine: engine,
        activities: t.activities,
        media: t.media,
        mediaRoot: () async => root,
        platform: CapturePlatform.android,
        clock: t.clock.call,
        hashFile: (_) async => 'hash',
      );
      await t.settings.setSafetyLongRecording(const Duration(hours: 1));
      await t.settings.setSafetyLowBatteryPercent(30);
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(t.db),
          settingsRepositoryProvider.overrideWithValue(t.settings),
          audioCaptureEngineProvider.overrideWithValue(engine),
          recordingServiceProvider.overrideWithValue(recorder),
          batteryProbeProvider.overrideWithValue(const UnknownBatteryProbe()),
        ],
      );
      addTearDown(container.dispose);

      final service = container.read(safetyPromptServiceProvider);
      await container.read(safetyThresholdsSettingProvider.future);
      expect(service.thresholds.longRecording, const Duration(hours: 1));
      expect(service.thresholds.lowBatteryPercent, 30);

      await t.settings.setSafetySilence(const Duration(minutes: 5));
      container.invalidate(safetyThresholdsSettingProvider);
      await container.read(safetyThresholdsSettingProvider.future);
      // Same service, new thresholds: a running recording is not touched.
      expect(
        identical(container.read(safetyPromptServiceProvider), service),
        isTrue,
      );
      expect(service.thresholds.silence, const Duration(minutes: 5));
    });
  });

  group('5.11 Settings screen', () {
    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 8; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    Widget app(Widget home, {List<Override> overrides = const []}) =>
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(t.db),
            settingsRepositoryProvider.overrideWithValue(t.settings),
            conferenceRepositoryProvider.overrideWithValue(t.conferences),
            activityRepositoryProvider.overrideWithValue(t.activities),
            recordingStatusProvider.overrideWith(
              (ref) => Stream.value(RecordingStatus.idle),
            ),
            ...overrides,
          ],
          child: MaterialApp(home: home),
        );

    void tallScreen(WidgetTester tester) {
      tester.view.physicalSize = const Size(1080, 4000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
    }

    testWidgets('5.11 My conferences menu opens Settings', (tester) async {
      tallScreen(tester);
      await tester.pumpWidget(app(const ConferenceListScreen()));
      await settle(tester);

      await tester.tap(find.byKey(const Key('conference-list-menu')));
      await settle(tester);
      expect(find.byKey(const Key('menu-settings')), findsOneWidget);
      await tester.tap(find.byKey(const Key('menu-settings')));
      await settle(tester);

      expect(find.byType(SettingsScreen), findsOneWidget);
    });

    testWidgets('5.11 About shows the app name, version, publisher and '
        'MIT licence', (tester) async {
      tallScreen(tester);
      await tester.pumpWidget(app(const SettingsScreen()));
      await settle(tester);

      final about = find.byKey(const Key('settings-about'));
      expect(about, findsOneWidget);
      expect(
        find.descendant(of: about, matching: find.text('Attenlume')),
        findsOneWidget,
      );
      final subtitle = tester
          .widgetList<Text>(
            find.descendant(of: about, matching: find.byType(Text)),
          )
          .map((t) => t.data)
          .join('\n');
      expect(subtitle, contains('Version $appVersion'));
      expect(subtitle, contains('Samlytics Data Services'));
      expect(subtitle, contains('MIT licence'));
    });

    testWidgets('FR-PRI-06 5.11 Privacy and app lock opens the Privacy '
        'screen', (tester) async {
      tallScreen(tester);
      await tester.pumpWidget(app(const SettingsScreen()));
      await settle(tester);

      await tester.tap(find.byKey(const Key('settings-privacy')));
      await settle(tester);

      expect(find.byType(PrivacyScreen), findsOneWidget);
    });

    testWidgets('FR-STO-05 5.11 Storage opens the Storage Manager', (
      tester,
    ) async {
      tallScreen(tester);
      await tester.pumpWidget(app(const SettingsScreen()));
      await settle(tester);

      await tester.tap(find.byKey(const Key('settings-storage')));
      // The Storage Manager loads from disk; only check it opened.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(StorageManagerScreen), findsOneWidget);
    });

    testWidgets('FR-UI-09 5.11 Quick guide opens the guide', (tester) async {
      tallScreen(tester);
      await tester.pumpWidget(app(const SettingsScreen()));
      await settle(tester);

      await tester.tap(find.byKey(const Key('settings-quick-guide')));
      await settle(tester);

      expect(find.byType(QuickGuideScreen), findsOneWidget);
    });

    testWidgets('5.11 Third-party licences opens the licence page', (
      tester,
    ) async {
      tallScreen(tester);
      await tester.pumpWidget(app(const SettingsScreen()));
      await settle(tester);

      await tester.tap(find.byKey(const Key('settings-licences')));
      await settle(tester);

      expect(find.byType(LicensePage), findsOneWidget);
    });

    testWidgets('FR-QUAL-02 5.11 choosing a default profile saves it', (
      tester,
    ) async {
      tallScreen(tester);
      await tester.pumpWidget(app(const SettingsScreen()));
      await settle(tester);
      expect(
        find.descendant(
          of: find.byKey(const Key('settings-default-profile')),
          matching: find.textContaining('Balanced'),
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('settings-default-profile')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('choice-Enhanced')));
      await settle(tester);

      final saved = await tester.runAsync(
        t.settings.globalDefaultRecordingProfile,
      );
      expect(saved, RecordingProfile.enhanced);
      expect(
        find.descendant(
          of: find.byKey(const Key('settings-default-profile')),
          matching: find.textContaining('Enhanced'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('FR-REC-06 5.11 choosing safety thresholds saves them', (
      tester,
    ) async {
      tallScreen(tester);
      await tester.pumpWidget(app(const SettingsScreen()));
      await settle(tester);

      await tester.tap(find.byKey(const Key('settings-long-recording')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('choice-3 hours')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('settings-silence')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('choice-15 minutes')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('settings-low-battery')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('choice-20%')));
      await settle(tester);

      final saved = await tester.runAsync(t.settings.safetyThresholds);
      expect(saved!.longRecording, const Duration(hours: 3));
      expect(saved.silence, const Duration(minutes: 15));
      expect(saved.lowBatteryPercent, 20);
    });

    testWidgets('FR-PHO-02 5.11 choosing keep highest quality saves it', (
      tester,
    ) async {
      tallScreen(tester);
      await tester.pumpWidget(app(const SettingsScreen()));
      await settle(tester);

      await tester.tap(find.byKey(const Key('settings-photo-quality')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('choice-Keep highest quality')));
      await settle(tester);

      final saved = await tester.runAsync(t.settings.photoKeepHighestQuality);
      expect(saved, isTrue);
    });

    testWidgets('5.11 choosing a theme saves it', (tester) async {
      tallScreen(tester);
      await tester.pumpWidget(app(const SettingsScreen()));
      await settle(tester);

      await tester.tap(find.byKey(const Key('settings-theme')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('choice-Dark')));
      await settle(tester);

      final saved = await tester.runAsync(t.settings.themeMode);
      expect(saved, ThemeMode.dark);
    });
  });
}

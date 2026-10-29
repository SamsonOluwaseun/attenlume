import 'dart:io';

import 'package:attenlume/app/theme/app_theme.dart';
import 'package:attenlume/data/local_database/app_database.dart';
import 'package:attenlume/data/local_database/database_provider.dart';
import 'package:attenlume/data/repositories/conference_repository.dart';
import 'package:attenlume/domain/services/device_timezone.dart';
import 'package:attenlume/features/capture/recording_providers.dart';
import 'package:attenlume/features/conferences/conference_home_screen.dart';
import 'package:attenlume/features/conferences/conference_list_screen.dart';
import 'package:attenlume/features/conferences/conference_wizard_screen.dart';
import 'package:attenlume/features/storage_manager/storage_manager_providers.dart';
import 'package:attenlume/features/storage_manager/storage_manager_screen.dart';
import 'package:attenlume/platform/storage/free_space_probe.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fixtures/fake_capture_engine.dart';

class _FakeDeviceTimezoneService extends DeviceTimezoneService {
  const _FakeDeviceTimezoneService();

  @override
  Future<String> detectTimezone() async => 'Europe/London';
}

void main() {
  late AppDatabase db;
  late ConferenceRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = ConferenceRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  Widget createSubject() {
    return ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        deviceTimezoneServiceProvider.overrideWithValue(
          const _FakeDeviceTimezoneService(),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const ConferenceListScreen(),
      ),
    );
  }

  testWidgets(
    'FR-CONF-08 active and archived conferences display in tabs and open home',
    (tester) async {
      await repo.create(
        name: 'Active Summit 2026',
        timezone: 'Europe/London',
        venue: 'London Arena',
      );
      final archived = await repo.create(
        name: 'Past Summit 2025',
        timezone: 'Europe/London',
      );
      await repo.archive(archived.id);

      await tester.pumpWidget(createSubject());
      await tester.pumpAndSettle();

      // Active tab shows active only
      expect(find.text('Active Summit 2026'), findsOneWidget);
      expect(find.text('London Arena'), findsOneWidget);
      expect(find.text('Past Summit 2025'), findsNothing);

      // Switch to Archived tab
      await tester.tap(find.text('Archived'));
      await tester.pumpAndSettle();

      expect(find.text('Past Summit 2025'), findsOneWidget);
      expect(find.text('Active Summit 2026'), findsNothing);

      // Tap card to open ConferenceHomeScreen
      await tester.tap(find.text('Past Summit 2025'));
      await tester.pumpAndSettle();

      expect(find.byType(ConferenceHomeScreen), findsOneWidget);
      expect(find.text('This conference is archived.'), findsOneWidget);
    },
  );

  testWidgets(
    'FR-CONF-08 new conference FAB navigates to ConferenceWizardScreen',
    (tester) async {
      await tester.pumpWidget(createSubject());
      await tester.pumpAndSettle();

      final fab = find.byKey(const Key('new-conference-fab'));
      expect(fab, findsOneWidget);
      await tester.tap(fab);
      await tester.pumpAndSettle();

      expect(find.byType(ConferenceWizardScreen), findsOneWidget);
      expect(find.text('New conference'), findsOneWidget);
    },
  );

  testWidgets('FR-STO-06 the list reloads after the Storage Manager, so a '
      'conference deleted there is gone', (tester) async {
    final sandbox = Directory.systemTemp.createTempSync('attenlume_list_');
    addTearDown(() => sandbox.deleteSync(recursive: true));
    final conf = await tester.runAsync(
      () => repo.create(
        name: 'Samlytics Conference 2026',
        timezone: 'Europe/London',
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          deviceTimezoneServiceProvider.overrideWithValue(
            const _FakeDeviceTimezoneService(),
          ),
          audioCaptureEngineProvider.overrideWithValue(FakeCaptureEngine()),
          mediaRootProvider.overrideWithValue(() async => sandbox),
          storageTempRootProvider.overrideWithValue(() async => sandbox),
          freeSpaceProbeProvider.overrideWithValue(
            const UnknownFreeSpaceProbe(),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const ConferenceListScreen(),
        ),
      ),
    );
    Future<void> settle() async {
      for (var i = 0; i < 20; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
        await tester.pump(const Duration(milliseconds: 20));
      }
    }

    await settle();
    expect(find.text('Samlytics Conference 2026'), findsOneWidget);

    await tester.tap(find.byKey(const Key('open-storage-manager-button')));
    await settle();
    expect(find.byType(StorageManagerScreen), findsOneWidget);

    // Stands in for Delete local copies removing the conference.
    await tester.runAsync(() => repo.delete(conf!.id));
    await tester.pageBack();
    await tester.pump(const Duration(seconds: 1));
    await settle();

    expect(find.byType(StorageManagerScreen), findsNothing);
    expect(find.text('Samlytics Conference 2026'), findsNothing);
  });
}

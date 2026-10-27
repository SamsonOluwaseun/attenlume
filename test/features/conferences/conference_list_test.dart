import 'package:attenlume/app/theme/app_theme.dart';
import 'package:attenlume/data/local_database/app_database.dart';
import 'package:attenlume/data/local_database/database_provider.dart';
import 'package:attenlume/data/repositories/conference_repository.dart';
import 'package:attenlume/domain/services/device_timezone.dart';
import 'package:attenlume/features/conferences/conference_home_screen.dart';
import 'package:attenlume/features/conferences/conference_list_screen.dart';
import 'package:attenlume/features/conferences/conference_wizard_screen.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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
}

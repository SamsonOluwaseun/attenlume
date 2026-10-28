import 'package:attenlume/app/theme/app_theme.dart';
import 'package:attenlume/app/theme/tokens.dart';
import 'package:attenlume/data/local_database/app_database.dart';
import 'package:attenlume/data/local_database/database_provider.dart';
import 'package:attenlume/data/repositories/conference_repository.dart';
import 'package:attenlume/domain/models/enums.dart';
import 'package:attenlume/domain/services/device_timezone.dart';
import 'package:attenlume/features/conferences/conference_home_screen.dart';
import 'package:attenlume/features/onboarding/welcome_screen.dart';
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

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  Widget createSubject({ThemeData? theme}) {
    return ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        deviceTimezoneServiceProvider.overrideWithValue(
          const _FakeDeviceTimezoneService(),
        ),
      ],
      child: MaterialApp(
        theme: theme ?? AppTheme.light(),
        home: const WelcomeScreen(),
      ),
    );
  }

  Color? logoPanelColour(WidgetTester tester) {
    final panel = tester.widget<DecoratedBox>(
      find.byKey(const Key('welcome-logo-panel')),
    );
    return (panel.decoration as BoxDecoration).color;
  }

  testWidgets('NFR-09 the logo sits on a cream panel only in the dark theme, '
      'so its navy wordmark stays readable', (tester) async {
    await tester.pumpWidget(createSubject(theme: AppTheme.dark()));
    await tester.pumpAndSettle();
    expect(logoPanelColour(tester), TokenColors.light.surface);

    await tester.pumpWidget(createSubject());
    await tester.pumpAndSettle();
    expect(logoPanelColour(tester), Colors.transparent);
  });

  testWidgets(
    'FR-CONF-01 quick start creates conference with one text field and one button [FR-CONF-01, FR-CONF-06]',
    (tester) async {
      await tester.pumpWidget(createSubject());
      await tester.pumpAndSettle();

      // Verify the policy notice is clearly presented (FR-CONF-06)
      expect(find.text(WelcomeScreen.policyNotice), findsOneWidget);

      // Count interactions: exactly 1 text entry and 1 button tap (FR-CONF-01)
      var interactionCount = 0;

      final nameInput = find.byKey(const Key('conference-name-input'));
      expect(nameInput, findsOneWidget);
      await tester.enterText(nameInput, 'Health Security 2026');
      interactionCount++;

      final createButton = find.byKey(const Key('create-conference-button'));
      expect(createButton, findsOneWidget);
      await tester.tap(createButton);
      interactionCount++;

      // Assert interaction budget
      expect(interactionCount, equals(2));

      // Pump several frames
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      // Land on ConferenceHomeScreen (FR-ACT-01 / J1)
      expect(find.byType(ConferenceHomeScreen), findsOneWidget);
      expect(find.text('Health Security 2026'), findsWidgets);
      expect(find.byKey(const Key('start-activity-button')), findsOneWidget);

      // Verify stored row in database
      final repo = ConferenceRepository(db);
      final conferences = await repo.getRecent();
      expect(conferences.length, equals(1));

      final created = conferences.first;
      expect(created.name, 'Health Security 2026');
      expect(created.defaultRecordingProfile, RecordingProfile.balanced);
      expect(created.policyAcknowledgedAt, isNotNull);
      expect(created.isArchived, isFalse);
    },
  );

  testWidgets(
    'FR-CONF-01 quick start rejects blank conference name with user feedback',
    (tester) async {
      await tester.pumpWidget(createSubject());
      await tester.pumpAndSettle();

      final createButton = find.byKey(const Key('create-conference-button'));
      await tester.tap(createButton);
      await tester.pumpAndSettle();

      // Should not navigate
      expect(find.byType(ConferenceHomeScreen), findsNothing);
      expect(find.text('Please enter a conference name'), findsOneWidget);

      final repo = ConferenceRepository(db);
      final conferences = await repo.getRecent();
      expect(conferences.isEmpty, isTrue);
    },
  );
}

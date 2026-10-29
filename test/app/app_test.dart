import 'package:attenlume/app/app.dart';
import 'package:attenlume/data/local_database/app_database.dart';
import 'package:attenlume/data/local_database/database_provider.dart';
import 'package:attenlume/data/repositories/settings_repository.dart';
import 'package:attenlume/domain/services/crash_recovery_service.dart';
import 'package:attenlume/features/capture/recording_providers.dart';
import 'package:attenlume/features/onboarding/welcome_screen.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  Widget createSubject() {
    return ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        crashRecoveryReportProvider.overrideWith(
          (ref) async => RecoveryReport.empty,
        ),
      ],
      child: const AttenlumeApp(),
    );
  }

  testWidgets('P0-02 app starts on the welcome screen with the tagline', (
    tester,
  ) async {
    await tester.pumpWidget(createSubject());
    await tester.pumpAndSettle();
    expect(find.byType(WelcomeScreen), findsOneWidget);
    expect(find.text(WelcomeScreen.tagline), findsOneWidget);
    expect(
      find.bySemanticsLabel('Attenlume by Samlytics Data Services'),
      findsOneWidget,
    );
  });

  testWidgets('NFR-01 no sign-in is offered in the free core', (tester) async {
    await tester.pumpWidget(createSubject());
    await tester.pumpAndSettle();
    expect(
      find.textContaining(RegExp('sign in', caseSensitive: false)),
      findsNothing,
    );
  });

  testWidgets('P0-02 app follows the system theme with Montserrat', (
    tester,
  ) async {
    await tester.pumpWidget(createSubject());
    await tester.pumpAndSettle();
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.system);
    expect(app.theme!.textTheme.bodyLarge!.fontFamily, 'Montserrat');
    expect(app.darkTheme!.brightness, Brightness.dark);
  });

  testWidgets('5.11 app uses the theme chosen in Settings', (tester) async {
    await tester.runAsync(
      () => db.writeSetting(SettingsRepository.themeModeKey, 'dark'),
    );
    await tester.pumpWidget(createSubject());
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.dark);
  });
}

import 'package:attenlume/app/app.dart';
import 'package:attenlume/features/onboarding/welcome_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('P0-02 app starts on the welcome screen with the tagline', (
    tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: AttenlumeApp()));
    expect(find.byType(WelcomeScreen), findsOneWidget);
    expect(find.text(WelcomeScreen.tagline), findsOneWidget);
    expect(
      find.bySemanticsLabel('Attenlume by Samlytics Data Services'),
      findsOneWidget,
    );
  });

  testWidgets('NFR-01 no sign-in is offered in the free core', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: AttenlumeApp()));
    expect(
      find.textContaining(RegExp('sign in', caseSensitive: false)),
      findsNothing,
    );
  });

  testWidgets('P0-02 app follows the system theme with Montserrat', (
    tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: AttenlumeApp()));
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.system);
    expect(app.theme!.textTheme.bodyLarge!.fontFamily, 'Montserrat');
    expect(app.darkTheme!.brightness, Brightness.dark);
  });
}

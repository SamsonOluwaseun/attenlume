import 'package:attenlume/app/theme/app_theme.dart';
import 'package:attenlume/data/repositories/repository_providers.dart';
import 'package:attenlume/data/repositories/settings_repository.dart';
import 'package:attenlume/domain/ai/summary_prompt.dart';
import 'package:attenlume/features/settings/summary_instructions_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fixtures/fixtures.dart';

/// Keeps the instructions in memory so the widget test needs no database.
class _Settings extends SettingsRepository {
  _Settings(super.db, [this.saved]);
  String? saved;
  @override
  Future<String?> summaryInstructions() async => saved;
  @override
  Future<void> setSummaryInstructions(String? text) async =>
      saved = text == null || text.trim().isEmpty ? null : text.trim();
}

void main() {
  late TestData data;
  setUp(() => data = TestData());
  tearDown(() => data.close());

  Future<_Settings> pump(WidgetTester tester, {String? saved}) async {
    final settings = _Settings(data.db, saved);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [settingsRepositoryProvider.overrideWithValue(settings)],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => SummaryInstructionsScreen.open(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return settings;
  }

  Future<void> tapKey(WidgetTester tester, String key) async {
    await tester.ensureVisible(find.byKey(Key(key)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key(key)));
  }

  String field(WidgetTester tester) => tester
      .widget<TextField>(find.byKey(const Key('summary-instructions-field')))
      .controller!
      .text;

  testWidgets('P3-12 shows the default, saves an edit and resets', (
    tester,
  ) async {
    final settings = await pump(tester);
    expect(field(tester), defaultSummaryInstructions);

    await tester.enterText(
      find.byKey(const Key('summary-instructions-field')),
      'Write for a finance director.',
    );
    await tapKey(tester, 'summary-instructions-save');
    await tester.pumpAndSettle();
    expect(settings.saved, 'Write for a finance director.');
    expect(find.text('Summary instructions saved.'), findsOneWidget);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(field(tester), 'Write for a finance director.');
    await tapKey(tester, 'summary-instructions-reset');
    await tester.pumpAndSettle();
    expect(settings.saved, isNull);
    expect(field(tester), defaultSummaryInstructions);
  });

  testWidgets('P3-12 saving the unchanged default keeps following the '
      'default', (tester) async {
    final settings = await pump(tester);
    await tapKey(tester, 'summary-instructions-save');
    await tester.pumpAndSettle();
    expect(settings.saved, isNull);
  });

  test('P3-12 settings store instructions and blank means default', () async {
    final settings = SettingsRepository(data.db);
    expect(await settings.summaryInstructions(), isNull);
    await settings.setSummaryInstructions('  Ask about cost.  ');
    expect(await settings.summaryInstructions(), 'Ask about cost.');
    await settings.setSummaryInstructions(null);
    expect(await settings.summaryInstructions(), isNull);
  });
}

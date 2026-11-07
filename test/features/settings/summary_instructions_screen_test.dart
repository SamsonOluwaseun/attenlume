import 'package:attenlume/app/theme/app_theme.dart';
import 'package:attenlume/data/repositories/repository_providers.dart';
import 'package:attenlume/data/repositories/settings_repository.dart';
import 'package:attenlume/domain/ai/summary_prompt.dart';
import 'package:attenlume/features/ai/language_model_providers.dart';
import 'package:attenlume/features/settings/summary_instructions_screen.dart';
import 'package:attenlume/features/summaries/summary_providers.dart';
import 'package:attenlume/platform/ai/language_model_descriptor.dart';
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

  Future<_Settings> pump(
    WidgetTester tester, {
    String? saved,
    int Function(String text) counter = instructionTokenEstimate,
  }) async {
    final settings = _Settings(data.db, saved);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(settings),
          effectiveDefaultInstructionsProvider.overrideWith(
            (ref) async => defaultSummaryInstructions,
          ),
          instructionTokenCounterProvider.overrideWithValue(
            (text) async => counter(text),
          ),
        ],
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

  testWidgets('P3-12 with the small model the editor shows its compact '
      'default', (tester) async {
    final settings = _Settings(data.db);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(settings),
          effectiveDefaultInstructionsProvider.overrideWith(
            (ref) async => compactSummaryInstructions,
          ),
          instructionTokenCounterProvider.overrideWithValue(
            (text) async => instructionTokenEstimate(text),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const SummaryInstructionsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(field(tester), compactSummaryInstructions);
    // Saving it unchanged keeps following the default.
    await tapKey(tester, 'summary-instructions-save');
    await tester.pumpAndSettle();
    expect(settings.saved, isNull);
  });

  testWidgets('P3-12 instructions too long for the model cannot be saved', (
    tester,
  ) async {
    final settings = await pump(tester);
    await tester.enterText(
      find.byKey(const Key('summary-instructions-field')),
      'word ' * 400,
    );
    await tester.pump();
    expect(
      find.textContaining('Too long for the on-device model'),
      findsOneWidget,
    );
    final save = tester.widget<FilledButton>(
      find.byKey(const Key('summary-instructions-save')),
    );
    expect(save.onPressed, isNull);
    expect(settings.saved, isNull);
  });

  testWidgets('P3-12 the limit uses the model\'s own count when installed', (
    tester,
  ) async {
    // Long but ordinary English: the estimate is too high, the model's
    // tokenizer finds it fits, so it can be saved.
    final longEnglish = 'Write clearly for busy executives. ' * 40;
    expect(
      instructionTokenEstimate(longEnglish),
      greaterThan(maxSummaryInstructionTokens),
    );
    final settings = await pump(tester, counter: (text) => 300);
    await tester.enterText(
      find.byKey(const Key('summary-instructions-field')),
      longEnglish,
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Too long'), findsNothing);
    await tapKey(tester, 'summary-instructions-save');
    await tester.pumpAndSettle();
    expect(settings.saved, longEnglish.trim());
  });

  test('P3-12 the small model gets the compact default; saved instructions '
      'always win', () async {
    Future<String?> read({String? saved, required bool small}) async {
      final container = ProviderContainer(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(
            _Settings(data.db, saved),
          ),
          activeLanguageModelDescriptorProvider.overrideWith(
            (ref) async => small
                ? LanguageModelDescriptor.gemma3_1B
                : LanguageModelDescriptor.gemma4E2B,
          ),
        ],
      );
      addTearDown(container.dispose);
      return container.read(summaryInstructionsProvider)();
    }

    expect(await read(small: false), isNull);
    expect(await read(small: true), compactSummaryInstructions);
    expect(await read(saved: 'Mine.', small: true), 'Mine.');
    expect(await read(saved: 'Mine.', small: false), 'Mine.');
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

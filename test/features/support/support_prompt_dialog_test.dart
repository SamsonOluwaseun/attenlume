import 'package:attenlume/app/theme/app_theme.dart';
import 'package:attenlume/features/support/support_prompt_dialog.dart';
import 'package:attenlume/features/support/support_prompt_policy.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  void phoneSize(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }

  Future<void> pumpDialogHost(
    WidgetTester tester, {
    required SupportPromptKind kind,
    required void Function(SupportPromptDecision? decision) onResult,
    ThemeData? theme,
    double textScale = 1.0,
  }) async {
    phoneSize(tester);
    await tester.pumpWidget(
      MaterialApp(
        theme: theme ?? AppTheme.light(),
        home: MediaQuery(
          data: MediaQueryData(
            textScaler: TextScaler.linear(textScale),
          ),
          child: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                key: const Key('open-support-dialog'),
                onPressed: () async {
                  final result = await showSupportPrompt(context, kind);
                  onResult(result);
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('open-support-dialog')));
    await tester.pumpAndSettle();
  }

  group('SupportPromptDialog copy & buttons (FR-SUP-01, FR-SUP-02, ADR-065)', () {
    testWidgets('initial prompt shows exact UK English copy and files ownership reassurance', (tester) async {
      SupportPromptDecision? decision;
      await pumpDialogHost(
        tester,
        kind: SupportPromptKind.initial,
        onResult: (res) => decision = res,
      );

      expect(find.byKey(const Key('support-prompt-dialog')), findsOneWidget);
      expect(
        find.text(
          'Your export is ready. Enjoying Attenlume? An optional gift helps us '
          'improve it and cover app-store costs. Your files are yours whether you give or not.',
        ),
        findsOneWidget,
      );
      expect(find.text('Gift now'), findsOneWidget);
      expect(find.text('Maybe later'), findsOneWidget);
      expect(find.text('Don’t ask again'), findsOneWidget);

      // Dismiss dialog
      await tester.tapAt(const Offset(10, 10)); // Tap barrier
      await tester.pumpAndSettle();
      expect(decision, isNull);
    });

    testWidgets('reminder prompt shows neutral copy without pressure or guilt', (tester) async {
      SupportPromptDecision? decision;
      await pumpDialogHost(
        tester,
        kind: SupportPromptKind.reminder,
        onResult: (res) => decision = res,
      );

      expect(
        find.text(
          'Enjoying Attenlume? You can support its development with an optional gift.',
        ),
        findsOneWidget,
      );
      expect(find.text('Gift now'), findsOneWidget);
      expect(find.text('Maybe later'), findsOneWidget);
      expect(find.text('Don’t ask again'), findsOneWidget);

      await tester.tapAt(const Offset(10, 10)); // Tap barrier to dismiss
      await tester.pumpAndSettle();
      expect(decision, isNull);
    });

    testWidgets('tapping Maybe later returns maybeLater decision', (tester) async {
      SupportPromptDecision? decision;
      await pumpDialogHost(
        tester,
        kind: SupportPromptKind.initial,
        onResult: (res) => decision = res,
      );

      await tester.tap(find.byKey(const Key('support-prompt-maybe-later')));
      await tester.pumpAndSettle();

      expect(decision, isNotNull);
      expect(decision!.isMaybeLater, isTrue);
      expect(decision!.paymentCompleted, isFalse);
    });

    testWidgets('tapping Don’t ask again returns dontAskAgain decision', (tester) async {
      SupportPromptDecision? decision;
      await pumpDialogHost(
        tester,
        kind: SupportPromptKind.initial,
        onResult: (res) => decision = res,
      );

      await tester.tap(find.byKey(const Key('support-prompt-dont-ask-again')));
      await tester.pumpAndSettle();

      expect(decision, isNotNull);
      expect(decision!.isDontAskAgain, isTrue);
      expect(decision!.paymentCompleted, isFalse);
    });

    testWidgets('tapping Gift now without amount selection returns giftNow with null amount', (tester) async {
      SupportPromptDecision? decision;
      await pumpDialogHost(
        tester,
        kind: SupportPromptKind.initial,
        onResult: (res) => decision = res,
      );

      await tester.tap(find.byKey(const Key('support-prompt-gift-now')));
      await tester.pumpAndSettle();

      expect(decision, isNotNull);
      expect(decision!.isGiftNow, isTrue);
      expect(decision!.selectedAmount, isNull);
      expect(decision!.paymentCompleted, isFalse);
    });

    testWidgets('selecting suggested £5 amount and tapping Gift now returns declarative choice', (tester) async {
      SupportPromptDecision? decision;
      await pumpDialogHost(
        tester,
        kind: SupportPromptKind.initial,
        onResult: (res) => decision = res,
      );

      // Select £5
      await tester.tap(find.byKey(const Key('support-amount-5')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('support-prompt-gift-now')));
      await tester.pumpAndSettle();

      expect(decision, isNotNull);
      expect(decision!.isGiftNow, isTrue);
      expect(decision!.selectedAmount, equals(SupportGiftAmount.five));
      expect(decision!.paymentCompleted, isFalse);
    });
  });

  group('SupportPromptDialog themes and 200% accessibility scaling', () {
    testWidgets('renders cleanly in dark theme', (tester) async {
      await pumpDialogHost(
        tester,
        kind: SupportPromptKind.initial,
        onResult: (_) {},
        theme: AppTheme.dark(),
      );

      expect(find.byKey(const Key('support-prompt-dialog')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders at 200% text scale without overflow', (tester) async {
      await pumpDialogHost(
        tester,
        kind: SupportPromptKind.initial,
        onResult: (_) {},
        textScale: 2.0,
      );

      expect(find.byKey(const Key('support-prompt-dialog')), findsOneWidget);
      // Ensure no RenderFlex overflow exception was thrown
      expect(tester.takeException(), isNull);
    });
  });
}

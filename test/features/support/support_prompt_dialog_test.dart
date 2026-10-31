import 'package:attenlume/app/theme/app_theme.dart';
import 'package:attenlume/features/support/support_prompt_dialog.dart';
import 'package:attenlume/features/support/support_prompt_policy.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  void phoneSize(WidgetTester tester) {
    // 360x800 logical phone screen (e.g. standard Android phone)
    tester.view.physicalSize = const Size(360, 800);
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
        // MaterialApp.builder places the scaled MediaQuery ABOVE the Navigator,
        // ensuring that the modal dialog route and overlay are properly scaled.
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
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
    );
    await tester.tap(find.byKey(const Key('open-support-dialog')));
    await tester.pumpAndSettle();
  }

  group(
    'SupportPromptDialog copy & buttons (FR-SUP-01, FR-SUP-02, ADR-065)',
    () {
      testWidgets(
        'initial prompt shows exact UK English copy and files ownership reassurance',
        (tester) async {
          SupportPromptDecision? decision;
          await pumpDialogHost(
            tester,
            kind: SupportPromptKind.initial,
            onResult: (res) => decision = res,
          );

          expect(
            find.byKey(const Key('support-prompt-dialog')),
            findsOneWidget,
          );
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

          // Dismiss dialog via barrier tap
          await tester.tapAt(const Offset(10, 10));
          await tester.pumpAndSettle();
          expect(decision, isNull);
        },
      );

      testWidgets(
        'reminder prompt shows neutral copy without pressure or guilt',
        (tester) async {
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

          await tester.tapAt(const Offset(10, 10));
          await tester.pumpAndSettle();
          expect(decision, isNull);
        },
      );

      testWidgets('tapping Maybe later returns maybeLater decision', (
        tester,
      ) async {
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

      testWidgets('tapping Don’t ask again returns dontAskAgain decision', (
        tester,
      ) async {
        SupportPromptDecision? decision;
        await pumpDialogHost(
          tester,
          kind: SupportPromptKind.initial,
          onResult: (res) => decision = res,
        );

        await tester.tap(
          find.byKey(const Key('support-prompt-dont-ask-again')),
        );
        await tester.pumpAndSettle();

        expect(decision, isNotNull);
        expect(decision!.isDontAskAgain, isTrue);
        expect(decision!.paymentCompleted, isFalse);
      });

      testWidgets(
        'tapping Gift now without amount selection returns giftNow with null amount',
        (tester) async {
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
        },
      );

      testWidgets(
        'selecting suggested £5 amount and tapping Gift now returns declarative choice',
        (tester) async {
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
        },
      );
    },
  );

  group('SupportPromptDialog real 200% phone viewport & actions (360x800)', () {
    testWidgets(
      '200% text scale in light theme: scales overlay, taps Gift now without overflow',
      (tester) async {
        SupportPromptDecision? decision;
        await pumpDialogHost(
          tester,
          kind: SupportPromptKind.initial,
          onResult: (res) => decision = res,
          theme: AppTheme.light(),
          textScale: 2.0,
        );

        final dialogContext = tester.element(
          find.byKey(const Key('support-prompt-dialog')),
        );
        expect(MediaQuery.textScalerOf(dialogContext).scale(16), equals(32.0));

        // Select amount chip (£5) and ensure visible
        await tester.ensureVisible(find.byKey(const Key('support-amount-5')));
        await tester.tap(find.byKey(const Key('support-amount-5')));
        await tester.pumpAndSettle();

        // Tap Gift now
        await tester.ensureVisible(
          find.byKey(const Key('support-prompt-gift-now')),
        );
        await tester.tap(find.byKey(const Key('support-prompt-gift-now')));
        await tester.pumpAndSettle();

        expect(decision, isNotNull);
        expect(decision!.isGiftNow, isTrue);
        expect(decision!.selectedAmount, equals(SupportGiftAmount.five));
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '200% text scale in dark theme: scales overlay, taps Maybe later without overflow',
      (tester) async {
        SupportPromptDecision? decision;
        await pumpDialogHost(
          tester,
          kind: SupportPromptKind.initial,
          onResult: (res) => decision = res,
          theme: AppTheme.dark(),
          textScale: 2.0,
        );

        final dialogContext = tester.element(
          find.byKey(const Key('support-prompt-dialog')),
        );
        expect(MediaQuery.textScalerOf(dialogContext).scale(16), equals(32.0));

        // Tap Maybe later
        await tester.ensureVisible(
          find.byKey(const Key('support-prompt-maybe-later')),
        );
        await tester.tap(find.byKey(const Key('support-prompt-maybe-later')));
        await tester.pumpAndSettle();

        expect(decision, isNotNull);
        expect(decision!.isMaybeLater, isTrue);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('200% text scale: taps Don’t ask again without overflow', (
      tester,
    ) async {
      SupportPromptDecision? decision;
      await pumpDialogHost(
        tester,
        kind: SupportPromptKind.initial,
        onResult: (res) => decision = res,
        textScale: 2.0,
      );

      final dialogContext = tester.element(
        find.byKey(const Key('support-prompt-dialog')),
      );
      expect(MediaQuery.textScalerOf(dialogContext).scale(16), equals(32.0));

      // Tap Don't ask again
      await tester.ensureVisible(
        find.byKey(const Key('support-prompt-dont-ask-again')),
      );
      await tester.tap(find.byKey(const Key('support-prompt-dont-ask-again')));
      await tester.pumpAndSettle();

      expect(decision, isNotNull);
      expect(decision!.isDontAskAgain, isTrue);
      expect(tester.takeException(), isNull);
    });
  });
}

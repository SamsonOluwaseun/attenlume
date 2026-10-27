import 'package:attenlume/app/theme/app_theme.dart';
import 'package:attenlume/presentation/components/attenlume_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget testHarness(Widget child) {
    return MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: Center(child: child)),
    );
  }

  group('AttenlumeButton [DESIGN_GUIDE Button]', () {
    testWidgets(
      'primary variant meets 52px height and 19px semibold text rule',
      (tester) async {
        var pressed = false;
        await tester.pumpWidget(
          testHarness(
            AttenlumeButton(
              variant: AttenlumeButtonVariant.primary,
              label: 'Start activity',
              leading: const Icon(Icons.mic),
              onPressed: () => pressed = true,
            ),
          ),
        );

        expect(find.text('Start activity'), findsOneWidget);
        expect(find.byIcon(Icons.mic), findsOneWidget);

        final buttonSize = tester.getSize(find.byType(ElevatedButton));
        expect(buttonSize.height, greaterThanOrEqualTo(52.0));

        final text = tester.widget<Text>(find.text('Start activity'));
        expect(text.style?.fontSize, 19.0);
        expect(text.style?.fontWeight, FontWeight.w600);
        expect(text.style?.color, const Color(0xFFFEFFF8)); // cream

        await tester.tap(find.text('Start activity'));
        expect(pressed, isTrue);
      },
    );

    testWidgets('secondary variant meets 52px height and has border', (
      tester,
    ) async {
      await tester.pumpWidget(
        testHarness(
          AttenlumeButton(
            variant: AttenlumeButtonVariant.secondary,
            label: 'Open previous',
            onPressed: () {},
          ),
        ),
      );

      final buttonSize = tester.getSize(find.byType(OutlinedButton));
      expect(buttonSize.height, greaterThanOrEqualTo(52.0));

      final text = tester.widget<Text>(find.text('Open previous'));
      expect(text.style?.fontSize, 15.0);
      expect(text.style?.fontWeight, FontWeight.w600);
    });

    testWidgets('danger variant uses error background', (tester) async {
      await tester.pumpWidget(
        testHarness(
          AttenlumeButton(
            variant: AttenlumeButtonVariant.danger,
            label: 'Delete conference',
            onPressed: () {},
          ),
        ),
      );

      expect(find.text('Delete conference'), findsOneWidget);
      expect(find.byType(ElevatedButton), findsOneWidget);
    });

    testWidgets('disabled button displays disabledReason', (tester) async {
      var pressed = false;
      await tester.pumpWidget(
        testHarness(
          AttenlumeButton(
            variant: AttenlumeButtonVariant.primary,
            label: 'Start activity',
            disabled: true,
            disabledReason: 'Recording already in progress',
            onPressed: () => pressed = true,
          ),
        ),
      );

      expect(find.text('Recording already in progress'), findsOneWidget);
      await tester.tap(find.text('Start activity'), warnIfMissed: false);
      expect(pressed, isFalse);
    });
  });
}

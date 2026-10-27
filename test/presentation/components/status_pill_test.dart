import 'package:attenlume/app/theme/app_theme.dart';
import 'package:attenlume/app/theme/tokens.dart';
import 'package:attenlume/domain/models/activity.dart';
import 'package:attenlume/presentation/components/status_pill.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget testHarness(Widget child, {bool isDark = false}) {
    return MaterialApp(
      theme: isDark ? AppTheme.dark() : AppTheme.light(),
      home: Scaffold(body: Center(child: child)),
    );
  }

  group('StatusPill [DESIGN_GUIDE StatusPill]', () {
    testWidgets(
      'renders recording state with navy pill, lime dot and cream text on light surface',
      (tester) async {
        await tester.pumpWidget(
          testHarness(
            const StatusPill(
              status: StatusPillStatus.recording,
              isOnNavy: false,
            ),
          ),
        );

        expect(find.text('Recording'), findsOneWidget);
        // Container box decoration check
        final container = tester.widget<Container>(
          find.byType(Container).first,
        );
        final decoration = container.decoration as BoxDecoration;
        // Navy fill (0xFF00212B)
        expect(decoration.color, const Color(0xFF00212B));
        // Radius pill
        expect(
          decoration.borderRadius,
          const BorderRadius.all(Radius.circular(TokenRadius.radiusPill)),
        );

        // Text color is cream
        final textWidget = tester.widget<Text>(find.text('Recording'));
        expect(textWidget.style?.color, const Color(0xFFFEFFF8));
      },
    );

    testWidgets('renders recording state with live fill when on navy surface', (
      tester,
    ) async {
      await tester.pumpWidget(
        testHarness(
          const StatusPill(status: StatusPillStatus.recording, isOnNavy: true),
        ),
      );

      expect(find.text('Recording'), findsOneWidget);
      final container = tester.widget<Container>(find.byType(Container).first);
      final decoration = container.decoration as BoxDecoration;
      // Live lime fill
      expect(decoration.color, const Color(0xFFDCFF38));
    });

    testWidgets('renders paused and interrupted with border and icon', (
      tester,
    ) async {
      await tester.pumpWidget(
        testHarness(const StatusPill(status: StatusPillStatus.paused)),
      );
      expect(find.text('Paused'), findsOneWidget);
      expect(find.byIcon(Icons.pause_rounded), findsOneWidget);

      await tester.pumpWidget(
        testHarness(const StatusPill(status: StatusPillStatus.interrupted)),
      );
      expect(find.text('Interrupted'), findsOneWidget);
      expect(find.byIcon(Icons.phone_disabled_rounded), findsOneWidget);
    });

    testWidgets('renders saved state with success fill and check icon', (
      tester,
    ) async {
      await tester.pumpWidget(
        testHarness(const StatusPill(status: StatusPillStatus.saved)),
      );
      expect(find.text('Saved'), findsOneWidget);
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);

      final container = tester.widget<Container>(find.byType(Container).first);
      final decoration = container.decoration as BoxDecoration;
      expect(decoration.color, const Color(0xFFC2E812)); // success color
    });

    testWidgets('renders private state with lock icon', (tester) async {
      await tester.pumpWidget(
        testHarness(const StatusPill(status: StatusPillStatus.private)),
      );
      expect(find.text('Private'), findsOneWidget);
      expect(find.byIcon(Icons.lock_outline_rounded), findsOneWidget);
    });
  });
}

import 'package:attenlume/app/theme/app_theme.dart';
import 'package:attenlume/app/theme/tokens.dart';
import 'package:attenlume/presentation/components/bookmark_chip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget wrapWidget(Widget child, {bool liveTheme = true}) {
    return MaterialApp(
      theme: liveTheme ? AppTheme.live() : AppTheme.light(),
      home: Scaffold(body: Center(child: child)),
    );
  }

  group('FR-UI-04 BookmarkChip', () {
    testWidgets('FR-UI-04 meets minimum touch target height of 48px', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrapWidget(const BookmarkChip(label: 'Key slide', onLiveSurface: true)),
      );

      final chipFinder = find.byType(BookmarkChip);
      expect(chipFinder, findsOneWidget);
      final size = tester.getSize(chipFinder);
      expect(size.height, greaterThanOrEqualTo(TokenSize.tapMin));
    });

    testWidgets('FR-UI-04 displays label text correctly', (tester) async {
      await tester.pumpWidget(
        wrapWidget(
          const BookmarkChip(label: 'Important moment', onLiveSurface: true),
        ),
      );

      expect(find.text('Important moment'), findsOneWidget);
    });

    testWidgets(
      'FR-UI-04 tapping on live surface invokes callback and flashes',
      (tester) async {
        var tapped = false;
        await tester.pumpWidget(
          wrapWidget(
            BookmarkChip(
              label: 'Question',
              onLiveSurface: true,
              onPress: () => tapped = true,
            ),
          ),
        );

        await tester.tap(find.text('Question'));
        expect(tapped, isTrue);

        // Flashing state for 600 ms
        await tester.pump(const Duration(milliseconds: 100));
        // Settle after flash timer finishes
        await tester.pump(const Duration(milliseconds: 600));
      },
    );

    testWidgets('FR-UI-04 non-live light screen rendering', (tester) async {
      await tester.pumpWidget(
        wrapWidget(
          const BookmarkChip(
            label: 'Quote',
            onLiveSurface: false,
            selected: true,
          ),
          liveTheme: false,
        ),
      );

      expect(find.text('Quote'), findsOneWidget);
      final text = tester.widget<Text>(find.text('Quote'));
      expect(text.style?.color, isNotNull);
    });
  });
}

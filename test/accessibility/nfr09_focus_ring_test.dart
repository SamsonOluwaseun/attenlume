import 'package:attenlume/app/theme/app_theme.dart';
import 'package:attenlume/presentation/components/focus_ring_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// NFR-09 keyboard focus ring (DESIGN_GUIDE States: 2px `focus`, 2px
/// offset) [P1-26].
void main() {
  Widget app({required VoidCallback onA}) => MaterialApp(
    theme: AppTheme.light(),
    builder: (context, child) => FocusRingOverlay(child: child!),
    home: Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FilledButton(
              key: const Key('a'),
              onPressed: onA,
              child: const Text('First'),
            ),
            OutlinedButton(
              key: const Key('b'),
              onPressed: () {},
              child: const Text('Second'),
            ),
          ],
        ),
      ),
    ),
  );

  testWidgets('NFR-09 no focus ring for touch', (tester) async {
    await tester.pumpWidget(app(onA: () {}));
    await tester.tap(find.byKey(const Key('a')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('focus-ring')), findsNothing);
  });

  testWidgets('NFR-09 Tab shows a 2px focus-token ring 2px outside the '
      'focused control, and Enter activates it', (tester) async {
    var pressed = 0;
    await tester.pumpWidget(app(onA: () => pressed++));

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();

    final ring = find.byKey(const Key('focus-ring'));
    expect(ring, findsOneWidget);
    final button = tester.getRect(find.byKey(const Key('a')));
    // The button's tap area is padded to 48 dp; the ring sits 2px outside
    // that box with a 2px stroke.
    final focusBox = tester.getRect(
      find
          .descendant(
            of: find.byKey(const Key('a')),
            matching: find.byType(Focus),
          )
          .first,
    );
    expect(tester.getRect(ring), focusBox.inflate(4));
    expect(button.contains(focusBox.center), isTrue);

    final box = tester.widget<DecoratedBox>(
      find.descendant(of: ring, matching: find.byType(DecoratedBox)),
    );
    final border = (box.decoration as BoxDecoration).border! as Border;
    expect(border.top.width, 2);
    expect(border.top.color, const Color(0xFF4392F1));

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(pressed, 1);

    // The ring follows focus to the next control.
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    final second = tester.getRect(find.byKey(const Key('b')));
    expect(tester.getRect(ring).overlaps(second), isTrue);
    expect(tester.getRect(ring).contains(button.center), isFalse);
  });
}

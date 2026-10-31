import 'dart:io';
import 'dart:ui' as ui;

import 'package:attenlume/app/theme/app_theme.dart';
import 'package:attenlume/features/support/support_prompt_dialog.dart';
import 'package:attenlume/features/support/support_prompt_policy.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('FR-SUP-01/03 owner amounts are £5 £10 £20 and Other', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(540, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    if (const bool.fromEnvironment('CAPTURE_GUIDE')) {
      await tester.runAsync(() async {
        final fonts = FontLoader('Montserrat')
          ..addFont(rootBundle.load('assets/fonts/Montserrat-Regular.ttf'))
          ..addFont(rootBundle.load('assets/fonts/Montserrat-Bold.ttf'));
        final icons = FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
        await fonts.load();
        await icons.load();
      });
    }
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const RepaintBoundary(
          key: Key('support-guide-capture'),
          child: Scaffold(
            body: Center(
              child: SupportPromptDialog(kind: SupportPromptKind.initial),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('£2'), findsNothing);
    expect(find.text('£5'), findsOneWidget);
    expect(find.text('£10'), findsOneWidget);
    expect(find.text('£20'), findsOneWidget);
    expect(find.text('Other'), findsOneWidget);
    await tester.tap(find.byKey(const Key('support-amount-20')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<ChoiceChip>(find.byKey(const Key('support-amount-20')))
          .selected,
      isTrue,
    );
    await tester.tap(find.byKey(const Key('support-amount-other')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<ChoiceChip>(find.byKey(const Key('support-amount-other')))
          .selected,
      isTrue,
    );
    if (const bool.fromEnvironment('CAPTURE_GUIDE')) {
      await tester.runAsync(() async {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const Key('support-guide-capture')),
        );
        final image = await boundary.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('tool/logs/support-guide.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
      await tester.pump();
    }
  });
}

import 'dart:io';

import 'package:attenlume/app/theme/app_theme.dart';
import 'package:attenlume/features/guide/guide_content.dart';
import 'package:attenlume/features/guide/guide_model.dart';
import 'package:attenlume/features/guide/quick_guide_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  List<String> allImages() => [
    for (final section in quickGuide.sections)
      for (final step in section.steps) ...step.images,
    quickGuide.privacyImage,
  ];

  test('NFR-09 every screenshot the quick guide names is bundled', () {
    for (final name in allImages()) {
      expect(
        File(guideImageAsset(name)).existsSync(),
        isTrue,
        reason: '$name is missing from assets/guide',
      );
    }
  });

  test('NFR-09 the quick guide uses only Samlytics test names', () {
    final text = [
      quickGuide.intro,
      for (final section in quickGuide.sections)
        for (final step in section.steps) ...step.points,
    ].join(' ');
    expect(text, isNot(contains(RegExp('ukhsa', caseSensitive: false))));
  });

  testWidgets('NFR-09 the quick guide shows every section and step', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 20000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light(), home: const QuickGuideScreen()),
    );
    await tester.pumpAndSettle();

    for (final section in quickGuide.sections) {
      expect(
        find.text('${section.number}  ${section.title}'),
        findsWidgets,
        reason: section.title,
      );
    }
    final steps = quickGuide.sections.expand((s) => s.steps).toList();
    for (var i = 0; i < steps.length; i++) {
      expect(find.text('Step ${i + 1}: ${steps[i].title}'), findsOneWidget);
    }
    expect(find.text(quickGuide.privacyTitle), findsOneWidget);
    // Every screenshot plus the Samlytics Data Services logo at the top.
    expect(find.byType(Image), findsNWidgets(allImages().length + 1));
    expect(find.byKey(const Key('quick-guide-company-logo')), findsOneWidget);
    expect(find.bySemanticsLabel('Samlytics Data Services'), findsWidgets);
  });
}

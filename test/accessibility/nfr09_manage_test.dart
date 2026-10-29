import 'package:attenlume/app/theme/app_theme.dart';
import 'package:attenlume/domain/services/export_service.dart';
import 'package:attenlume/features/export/export_providers.dart';
import 'package:attenlume/features/export/export_sheet.dart';
import 'package:attenlume/features/export/import_export_screen.dart';
import 'package:attenlume/features/guide/quick_guide_screen.dart';
import 'package:attenlume/features/playback_review/review_screen.dart';
import 'package:attenlume/features/privacy/privacy_screen.dart';
import 'package:attenlume/features/privacy/sensitive_export_warning.dart';
import 'package:attenlume/features/settings/settings_screen.dart';
import 'package:attenlume/features/storage_manager/storage_manager_screen.dart';
import 'package:attenlume/platform/storage/free_space_probe.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../fixtures/fake_export_sharer.dart';
import '../fixtures/fixtures.dart';
import 'a11y_harness.dart';

class _Destinations implements ExportDestinations {
  const _Destinations();

  @override
  bool get canChoose => true;

  @override
  Future<String?> defaultFolder() async => '/exports';

  @override
  Future<String?> choose() async => null;
}

typedef Screen = Widget Function(SampleConference s);

/// NFR-09 accessibility of review, export, import, Storage Manager,
/// Settings, Privacy and app lock, and the quick guide [P1-26].
void main() {
  List<Override> extra(A11yHarness h) => [
    exportServiceProvider.overrideWithValue(
      ExportService(
        conferences: h.t.conferences,
        activities: h.t.activities,
        media: h.t.media,
        cuts: h.t.cuts,
        jobs: h.t.exports,
        mediaRoot: () async => h.root,
        tempRoot: () async => h.root,
        freeSpace: const UnknownFreeSpaceProbe(),
      ),
    ),
    exportDestinationsProvider.overrideWithValue(const _Destinations()),
    exportSharerProvider.overrideWithValue(FakeExportSharer()),
  ];

  final screens = <String, Screen>{
    'review': (s) => ReviewScreen(activityId: s.keynote.id),
    'export sheet': (s) =>
        Scaffold(body: ExportSheet(conferenceId: s.conference.id)),
    'import': (_) => const ImportExportScreen(),
    'Storage Manager': (_) => const StorageManagerScreen(),
    'Settings': (_) => const SettingsScreen(),
    'Privacy and app lock': (_) => const PrivacyScreen(),
    'quick guide': (_) => const QuickGuideScreen(),
  };

  Future<A11yHarness> open(
    WidgetTester tester,
    Screen screen, {
    A11ySize size = A11ySize.phone,
    double textScale = 1,
    ThemeData? theme,
  }) async {
    final h = A11yHarness(tester);
    await h.setUp();
    addTearDown(h.tearDown);
    h.size(size, textScale: textScale);
    final sample = await h.io(() => SampleConference.build(h.t));
    await tester.pumpWidget(
      h.app(screen(sample), theme: theme, extra: extra(h)),
    );
    await h.settle(20);
    return h;
  }

  group('NFR-09 review, export, storage and settings screens', () {
    screens.forEach((name, screen) {
      for (final (themeName, theme) in [
        ('light', AppTheme.light()),
        ('dark', AppTheme.dark()),
      ]) {
        testWidgets('NFR-09 $name ($themeName) meets tap target, label and '
            'contrast guidelines', (tester) async {
          final handle = tester.ensureSemantics();
          await open(tester, screen, theme: theme);
          await expectMeetsGuidelines(tester);
          handle.dispose();
        });
      }

      for (final size in A11ySize.values) {
        testWidgets('NFR-09 $name at 200% text on ${size.name} has no '
            'overflow', (tester) async {
          final h = await open(tester, screen, size: size, textScale: 2);
          await scrollThrough(tester, h);
        });
      }
    });

    testWidgets('NFR-09 export privacy warning meets the guidelines and '
        'holds at 200% text', (tester) async {
      final handle = tester.ensureSemantics();
      final h = await open(tester, screens['export sheet']!, textScale: 2);
      await tester.ensureVisible(find.byKey(const Key('export-start')));
      await tester.tap(find.byKey(const Key('export-start')));
      await h.settle();
      expect(find.byType(SensitiveExportWarning), findsOneWidget);
      await expectMeetsGuidelines(tester);
      handle.dispose();
    });
  });
}

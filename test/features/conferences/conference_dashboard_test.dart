import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:attenlume/app/theme/app_theme.dart';
import 'package:attenlume/domain/models/activity.dart';
import 'package:attenlume/domain/models/enums.dart';
import 'package:attenlume/features/conferences/activity_detail_sheet.dart';
import 'package:attenlume/features/conferences/conference_dashboard.dart';
import 'package:attenlume/features/conferences/conference_home_screen.dart';
import 'package:attenlume/features/conferences/conference_list_screen.dart';
import 'package:attenlume/features/shell/app_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../accessibility/a11y_harness.dart';
import '../../fixtures/fixtures.dart';

void main() {
  Future<A11yHarness> harness(WidgetTester tester) async {
    final h = A11yHarness(tester);
    await h.setUp();
    addTearDown(h.tearDown);
    h.size(A11ySize.tablet);
    return h;
  }

  testWidgets(
    'P1-39 wide overview uses local counts, searches and opens existing details',
    (tester) async {
      final h = await harness(tester);
      final sample = await h.io(() => SampleConference.build(h.t));
      const capture = bool.fromEnvironment('CAPTURE_DESKTOP_GUIDE');
      if (capture) {
        final fonts = FontLoader('Montserrat');
        for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
          fonts.addFont(rootBundle.load('assets/fonts/Montserrat-$weight.ttf'));
        }
        await fonts.load();
        await (FontLoader(
          'MaterialIcons',
        )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      }
      final boundaryKey = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundaryKey,
          child: capture
              ? ProviderScope(
                  overrides: h.overrides,
                  child: MaterialApp(
                    theme: AppTheme.light(),
                    debugShowCheckedModeBanner: false,
                    home: const AppShell(),
                  ),
                )
              : h.app(const AppShell()),
        ),
      );
      await h.settle(25);
      if (capture) {
        await tester.runAsync(() async {
          final boundary =
              boundaryKey.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 1);
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          File('assets/guide/desktop-overview.png')
              .writeAsBytesSync(data!.buffer.asUint8List());
          image.dispose();
        });
      }
      expect(
        find.byKey(const Key('conference-overview-layout')),
        findsOneWidget,
      );
      expect(find.text('17 min recorded'), findsOneWidget);
      final pane = find.byKey(const Key('conference-dashboard'));
      expect(
        find.descendant(of: pane, matching: find.text('3')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: pane, matching: find.text('6.2 MB')),
        findsOneWidget,
      );
      for (final label in ['Photos', 'Bookmarks']) {
        expect(
          find.descendant(
            of: find.byKey(ValueKey('dashboard-stat-$label')),
            matching: find.text('1'),
          ),
          findsOneWidget,
        );
      }

      final search = find.byKey(const Key('dashboard-activity-search'));
      await tester.ensureVisible(search);
      await tester.enterText(search, 'Data Mesh');
      await tester.pump();
      expect(
        find.byKey(Key('dashboard-activity-${sample.keynote.id}')),
        findsOneWidget,
      );
      expect(
        find.byKey(Key('dashboard-activity-${sample.reflection.id}')),
        findsNothing,
      );
      await tester.enterText(search, 'no match');
      await tester.pump();
      expect(find.text('No activities match your search.'), findsOneWidget);
      await tester.enterText(search, 'Data Mesh');
      await tester.pump();
      final activity = find.byKey(
        Key('dashboard-activity-${sample.keynote.id}'),
      );
      await tester.ensureVisible(activity);
      await tester.tap(activity);
      await h.settle(25);
      expect(find.byType(ActivityDetailSheet), findsOneWidget);
      await h.io(
        () => h.t.media.addBookmark(
          activityId: sample.keynote.id,
          source: BookmarkSource.ui,
        ),
      );
      Navigator.of(tester.element(find.byType(ActivityDetailSheet))).pop();
      await h.settle(25);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('dashboard-stat-Bookmarks')),
        -200,
        scrollable: find
            .descendant(
              of: find.byKey(const Key('conference-dashboard')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('dashboard-stat-Bookmarks')),
          matching: find.text('2'),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'P1-39 selection and query survive window resizing; phone keeps conference route',
    (tester) async {
      final h = await harness(tester);
      final sample = await h.io(() => SampleConference.build(h.t));
      await h.io(() => h.t.conference());
      await tester.pumpWidget(h.app(const AppShell()));
      await h.settle(25);
      await tester.tap(
        find.byKey(Key('conference-card-${sample.conference.id}')),
      );
      await h.settle();
      expect(find.text('17 min recorded'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('conference-search-field')),
        'Samlytics',
      );
      tester.view.physicalSize = const Size(800, 800);
      await tester.pump();
      expect(find.byKey(const Key('conference-dashboard')), findsNothing);
      tester.view.physicalSize = const Size(1280, 800);
      await tester.pump();
      await h.settle();
      expect(find.text('17 min recorded'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('conference-search-field')))
            .controller!
            .text,
        'Samlytics',
      );
      tester.view.physicalSize = const Size(360, 800);
      await tester.pump();
      await tester.tap(
        find.byKey(Key('conference-card-${sample.conference.id}')),
      );
      await h.settle(25);
      expect(find.byType(ConferenceHomeScreen), findsOneWidget);
    },
  );

  testWidgets('P1-39 empty and archived conferences show truthful states', (
    tester,
  ) async {
    final h = await harness(tester);
    final conference = await h.io(() => h.t.conference());
    await h.io(() => h.t.conferences.archive(conference.id));
    await tester.pumpWidget(h.app(const ConferenceListScreen()));
    await h.settle(20);
    expect(find.byKey(const Key('conference-dashboard')), findsNothing);
    await tester.tap(find.text('Archived'));
    await h.settle(20);
    expect(find.text('Archived conference'), findsOneWidget);
    expect(
      find.text(
        'Nothing captured yet. Open this conference to start your first activity.',
      ),
      findsOneWidget,
    );
    expect(find.text('0 min recorded'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('conference-search-field')),
      'missing',
    );
    await tester.pump();
    expect(find.byKey(const Key('conference-dashboard')), findsNothing);
  });

  testWidgets('P1-39 overview handles loading and failure then retries', (
    tester,
  ) async {
    final h = await harness(tester);
    final conference = await h.io(() => h.t.conference());
    final pending = Completer<List<ActivitySummary>>();
    var attempts = 0;
    await tester.pumpWidget(
      h.app(
        ConferenceDashboard(
          conference: conference,
          onOpenConference: () {},
          onChanged: () {},
        ),
        extra: [
          conferenceDashboardProvider(conference.id).overrideWith((ref) {
            attempts++;
            return attempts == 1 ? pending.future : Future.value([]);
          }),
        ],
      ),
    );
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    pending.completeError(StateError('test failure'));
    await h.settle();
    expect(
      find.text('Could not load the conference overview.'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('dashboard-retry')));
    await h.settle();
    expect(find.text('0 min recorded'), findsOneWidget);
  });

  for (final dark in [false, true]) {
    testWidgets(
      'P1-39 NFR-09 overview at 200% text in ${dark ? 'dark' : 'light'} theme',
      (tester) async {
        final h = await harness(tester);
        h.size(A11ySize.tablet, textScale: 2);
        await h.io(() => SampleConference.build(h.t));
        await tester.pumpWidget(
          h.app(
            const AppShell(),
            theme: dark ? AppTheme.dark() : AppTheme.light(),
          ),
        );
        await h.settle(25);
        expect(
          find.byKey(const Key('conference-overview-layout')),
          findsOneWidget,
        );
        final search = find.byKey(const Key('dashboard-activity-search'));
        await tester.scrollUntilVisible(
          search,
          200,
          scrollable: find
              .descendant(
                of: find.byKey(const Key('conference-dashboard')),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.enterText(search, 'Data Mesh');
        await tester.pump();
        await tester.drag(
          find.byKey(const Key('conference-dashboard')),
          const Offset(0, -600),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
      },
    );
  }
}

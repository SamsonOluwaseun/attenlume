import 'dart:async';

import 'package:attenlume/data/repositories/repository_providers.dart';
import 'package:attenlume/domain/models/conference.dart';
import 'package:attenlume/domain/models/activity.dart';
import 'package:attenlume/domain/services/recording_state.dart';
import 'package:attenlume/features/conferences/conference_home_screen.dart';
import 'package:attenlume/features/conferences/conference_list_screen.dart';
import 'package:attenlume/features/conferences/conference_wizard_screen.dart';
import 'package:attenlume/features/conferences/start_activity_sheet.dart';
import 'package:attenlume/features/onboarding/welcome_screen.dart';
import 'package:attenlume/features/settings/settings_screen.dart';
import 'package:attenlume/features/shell/app_shell.dart';
import 'package:attenlume/features/shell/library_page.dart';
import 'package:attenlume/features/shell/record_page.dart';
import 'package:attenlume/features/storage_manager/storage_manager_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../accessibility/a11y_harness.dart';
import '../../fixtures/fixtures.dart';

/// Navigation shell (FR-UI-11, ADR-052) [P1-39].
void main() {
  Future<A11yHarness> open(
    WidgetTester tester,
    Widget home, {
    Size physical = const Size(1080, 2400),
    double ratio = 3,
    RecordingStatus? status,
    bool sample = false,
  }) async {
    final h = A11yHarness(tester);
    await h.setUp();
    addTearDown(h.tearDown);
    tester.view.physicalSize = physical;
    tester.view.devicePixelRatio = ratio;
    addTearDown(tester.view.reset);
    if (sample) await h.io(() => SampleConference.build(h.t));
    await tester.pumpWidget(h.app(home, status: status));
    await h.settle();
    return h;
  }

  group('FR-UI-11 layout', () {
    test('FR-UI-11 the side rail starts at 840 dp', () {
      expect(AppShell.railBreakpoint, 840);
      expect(AppShell.useRail(839.9), isFalse);
      expect(AppShell.useRail(840), isTrue);
    });

    testWidgets('FR-UI-11 a phone shows the bottom bar with Conferences, '
        'Record, Library and Settings', (tester) async {
      await open(tester, const AppShell());

      expect(find.byKey(const Key('shell-navigation-bar')), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);
      for (final d in ShellDestination.values) {
        expect(find.byKey(Key('nav-${d.name}')), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(NavigationBar),
            matching: find.text(d.label),
          ),
          findsOneWidget,
        );
      }
      expect(find.byType(ConferenceListScreen), findsOneWidget);
    });

    testWidgets('FR-UI-11 a tablet or Windows window shows the side rail', (
      tester,
    ) async {
      await open(
        tester,
        const AppShell(),
        physical: const Size(1280, 800),
        ratio: 1,
      );

      expect(find.byKey(const Key('shell-navigation-rail')), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      for (final d in ShellDestination.values) {
        expect(
          find.descendant(
            of: find.byType(NavigationRail),
            matching: find.text(d.label),
          ),
          findsOneWidget,
        );
      }
      await tester.tap(find.text('Settings'));
      await tester.pump();
      expect(find.byType(SettingsScreen), findsOneWidget);
    });
  });

  group('FR-UI-11 resizing', () {
    testWidgets('FR-UI-11 crossing the breakpoint keeps the search text and '
        'the selected tab', (tester) async {
      final h = await open(tester, const AppShell(), sample: true);
      await tester.enterText(
        find.byKey(const Key('conference-search-field')),
        'Samlytics',
      );
      await tester.tap(find.text('Archived'));
      await h.settle(20);

      // Phone to a wide Windows window, then back.
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      await h.settle();
      expect(find.byType(NavigationRail), findsOneWidget);
      TextField field() => tester.widget<TextField>(
        find.byKey(const Key('conference-search-field')),
      );
      expect(field().controller!.text, 'Samlytics');

      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3;
      await h.settle();
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(field().controller!.text, 'Samlytics');
      final tabs = DefaultTabController.maybeOf(
        tester.element(find.byType(TabBar)),
      );
      final bar = tester.widget<TabBar>(find.byType(TabBar));
      expect((bar.controller ?? tabs)!.index, 1);
    });
  });

  group('FR-UI-11 destinations', () {
    testWidgets('FR-UI-11 conference scroll survives destination refresh', (
      tester,
    ) async {
      final h = A11yHarness(tester);
      await h.setUp();
      addTearDown(h.tearDown);
      h.size(A11ySize.phone);
      final conferences = await h.io(() async {
        for (var i = 0; i < 30; i++) {
          await h.t.conferences.create(
            name: 'Samlytics Conference 2026',
            timezone: 'Europe/London',
          );
        }
        return h.t.conferences.getAll();
      });
      final refresh = Completer<List<Conference>>();
      var reads = 0;
      await tester.pumpWidget(
        h.app(
          const AppShell(),
          extra: [
            allConferencesFutureProvider.overrideWith((ref) {
              reads++;
              return reads == 1 ? Future.value(conferences) : refresh.future;
            }),
          ],
        ),
      );
      await h.settle();
      final list = find.byKey(const PageStorageKey('active-conferences-list'));
      ScrollPosition position() => tester
          .state<ScrollableState>(
            find.descendant(of: list, matching: find.byType(Scrollable)),
          )
          .position;
      await tester.drag(list, const Offset(0, -650));
      await h.settle(25);
      final offset = position().pixels;
      expect(offset, greaterThan(0));
      await tester.tap(find.byKey(const Key('nav-library')));
      await h.settle();
      await tester.tap(find.byKey(const Key('nav-conferences')));
      await h.settle();
      expect(reads, 2);
      expect(position().pixels, closeTo(offset, 1));
      refresh.complete(conferences);
      await h.settle();
      expect(position().pixels, closeTo(offset, 1));
    });

    testWidgets('FR-PRI-02 Settings retains recording status and quick Stop', (
      tester,
    ) async {
      final h = await open(
        tester,
        const AppShell(),
        status: const RecordingStatus(
          state: RecordingState.recording,
          activityId: 'aaaaaaaa-0000-4000-8000-000000000001',
        ),
      );
      await tester.tap(find.byKey(const Key('nav-settings')));
      await h.settle();
      expect(find.byKey(const Key('recording-banner')), findsOneWidget);
      final stop = find.byKey(const Key('recording-banner-stop'));
      expect(stop.hitTestable(), findsOneWidget);
      expect(tester.widget<TextButton>(stop).onPressed, isNotNull);
      expect(find.text('Recording'), findsWidgets);
    });

    testWidgets('FR-UI-11 each destination opens its page, and the list '
        'keeps its search when you come back', (tester) async {
      final h = await open(tester, const AppShell(), sample: true);

      await tester.enterText(
        find.byKey(const Key('conference-search-field')),
        'Samlytics',
      );
      await tester.tap(find.byKey(const Key('nav-record')));
      await h.settle();
      expect(find.byType(RecordPage), findsOneWidget);

      await tester.tap(find.byKey(const Key('nav-library')));
      await h.settle();
      expect(find.byType(LibraryPage), findsOneWidget);

      await tester.tap(find.byKey(const Key('nav-settings')));
      await h.settle();
      expect(find.byType(SettingsScreen), findsOneWidget);

      await tester.tap(find.byKey(const Key('nav-conferences')));
      await h.settle();
      final field = tester.widget<TextField>(
        find.byKey(const Key('conference-search-field')),
      );
      expect(field.controller!.text, 'Samlytics');
    });

    testWidgets('FR-UI-11 in the shell, My conferences keeps New conference '
        'and Import an export; Settings and the Storage Manager are in the '
        'bar', (tester) async {
      await open(tester, const AppShell());

      expect(find.byKey(const Key('new-conference-fab')), findsOneWidget);
      expect(
        find.byKey(const Key('open-storage-manager-button')),
        findsNothing,
      );
      await tester.tap(find.byKey(const Key('conference-list-menu')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('menu-import')), findsOneWidget);
      expect(find.byKey(const Key('menu-settings')), findsNothing);
    });

    testWidgets('FR-UI-11 Library opens the Storage Manager', (tester) async {
      final h = await open(
        tester,
        const AppShell(initial: ShellDestination.library),
      );

      expect(find.byKey(const Key('library-import')), findsOneWidget);
      await tester.tap(find.byKey(const Key('library-storage-manager')));
      await h.settle();
      expect(find.byType(StorageManagerScreen), findsOneWidget);
    });

    testWidgets('FR-UI-11 opening a conference covers the shell, so the bar '
        'is not shown on conference home or recording', (tester) async {
      final h = await open(tester, const AppShell(), sample: true);

      await tester.tap(find.text('Samlytics Conference 2026'));
      await h.settle(30); // past the page transition
      expect(find.byType(ConferenceHomeScreen), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
    });
  });

  group('FR-UI-11 Record', () {
    testWidgets('FR-UI-11 with no conference, Record offers to create one', (
      tester,
    ) async {
      final h = await open(
        tester,
        const AppShell(initial: ShellDestination.record),
      );

      expect(find.byKey(const Key('record-no-conference')), findsOneWidget);
      await tester.tap(find.byKey(const Key('record-new-conference')));
      await h.settle();
      expect(find.byType(ConferenceWizardScreen), findsOneWidget);
    });

    testWidgets('FR-UI-11 Record starts an activity in the most recent '
        'conference and opens the recorder', (tester) async {
      Activity? recorded;
      final h = await open(
        tester,
        RecordPage(openRecorder: (_, a) async => recorded = a),
        sample: true,
      );

      expect(find.byKey(const Key('record-conference-name')), findsOneWidget);
      expect(find.text('Samlytics Conference 2026'), findsOneWidget);

      await tester.tap(find.byKey(const Key('record-start-activity')));
      await h.settle();
      expect(find.byType(StartActivitySheet), findsOneWidget);

      await tester.tap(find.text('Keynote').first);
      await h.settle(20);
      expect(recorded, isNotNull);
      expect(recorded!.title, isNotEmpty);
    });

    testWidgets('FR-UI-11 while a recording is held, Record returns to it', (
      tester,
    ) async {
      await open(
        tester,
        const RecordPage(),
        status: const RecordingStatus(
          state: RecordingState.recording,
          activityId: 'aaaaaaaa-0000-4000-8000-000000000001',
        ),
      );

      expect(find.byKey(const Key('record-held')), findsOneWidget);
      expect(find.byKey(const Key('record-open-recording')), findsOneWidget);
      expect(find.byKey(const Key('record-start-activity')), findsNothing);
    });
  });

  group('FR-UI-11 Record reloads', () {
    testWidgets('FR-UI-11 Record reloads its conference after Open '
        'conference, so an archived one is no longer the target', (
      tester,
    ) async {
      final h = await open(tester, const RecordPage(), sample: true);
      expect(find.byKey(const Key('record-start-activity')), findsOneWidget);

      await tester.tap(find.byKey(const Key('record-open-conference')));
      await h.settle(30);
      expect(find.byType(ConferenceHomeScreen), findsOneWidget);
      await h.io(() async {
        final all = await h.t.conferences.getAll();
        await h.t.conferences.archive(all.single.id);
      });
      await tester.pageBack();
      await h.settle(30);

      expect(find.byKey(const Key('record-no-conference')), findsOneWidget);
      expect(find.byKey(const Key('record-start-activity')), findsNothing);
    });
  });

  group('NFR-01 welcome', () {
    testWidgets('NFR-01 welcome has no sign-in, and Open previous opens My '
        'conferences inside the shell', (tester) async {
      final h = await open(tester, const WelcomeScreen());

      expect(
        find.textContaining(RegExp('sign in', caseSensitive: false)),
        findsNothing,
      );
      await tester.ensureVisible(find.byKey(const Key('open-previous-button')));
      await tester.tap(find.byKey(const Key('open-previous-button')));
      await h.settle();
      expect(find.byType(AppShell), findsOneWidget);
      expect(find.byType(ConferenceListScreen), findsOneWidget);
      expect(find.byType(NavigationBar), findsOneWidget);
    });
  });
}

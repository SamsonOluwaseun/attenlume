import 'dart:convert';

import 'package:attenlume/app/theme/app_theme.dart';
import 'package:attenlume/domain/models/planned_session.dart';
import 'package:attenlume/domain/services/agenda_parser.dart';
import 'package:attenlume/features/agenda/agenda_import_screen.dart';
import 'package:attenlume/features/agenda/agenda_providers.dart';
import 'package:attenlume/features/conferences/conference_home_screen.dart';
import 'package:attenlume/features/conferences/start_activity_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fixtures/fixtures.dart';
import 'a11y_harness.dart';

class _Picker implements AgendaFilePicker {
  const _Picker();

  @override
  Future<PickedAgendaFile?> pick({required int maxBytes}) async =>
      PickedAgendaFile('agenda.csv', utf8.encode(_csv));
}

/// Long titles, several speakers and a bad row, so the layouts are tried
/// with real-looking text.
const _csv =
    'title,speaker,room,start,end,type\n'
    'Opening keynote: where enterprise data architecture improves '
    'reproducibility,Samlytics Data Services; Guest speaker,Main stage,'
    '2026-11-04 09:00,2026-11-04 09:45,Keynote\n'
    'Data Mesh in Practice,Samlytics Data Services,Hall A,'
    '2026-11-04 10:00,2026-11-04 10:45,Talk\n'
    'How is AI applied in public health response?,Samlytics Data Services,'
    'Room 3,2026-11-04 11:00,2026-11-04 12:00,Panel\n'
    'Exhibition open,,Expo hall,2026-11-05,,\n'
    'Lunch,,,whenever,,\n';

/// NFR-09 accessibility of the agenda (P2-07, ADR-082): the conference
/// page's agenda, the import preview and Start activity with an agenda,
/// against Flutter's guidelines and at 200% text.
void main() {
  final now = DateTime.utc(2026, 11, 4, 10, 10);

  Future<(A11yHarness, SampleConference)> setUp(
    WidgetTester tester, {
    A11ySize size = A11ySize.phone,
    double textScale = 1,
  }) async {
    final h = A11yHarness(tester);
    await h.setUp();
    addTearDown(h.tearDown);
    h.size(size, textScale: textScale);
    final sample = await h.io(() async {
      final s = await SampleConference.build(h.t);
      final result = parseAgendaFile(
        fileName: 'agenda.csv',
        bytes: utf8.encode(_csv),
        timezone: s.conference.timezone,
      );
      await h.t.plannedSessions.addAll(
        s.conference.id,
        result.entries,
        source: AgendaSource.csv,
      );
      return s;
    });
    return (h, sample);
  }

  final extra = [
    agendaClockProvider.overrideWithValue(() => now),
    agendaFilePickerProvider.overrideWithValue(const _Picker()),
  ];

  Future<A11yHarness> home(
    WidgetTester tester, {
    A11ySize size = A11ySize.phone,
    double textScale = 1,
    ThemeData? theme,
  }) async {
    final (h, s) = await setUp(tester, size: size, textScale: textScale);
    await tester.pumpWidget(
      h.app(
        ConferenceHomeScreen(
          conferenceId: s.conference.id,
          openRecorder: (_, _) async {},
        ),
        theme: theme,
        extra: extra,
      ),
    );
    await h.settle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('agenda-section')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await h.settle(2);
    return h;
  }

  Future<A11yHarness> preview(
    WidgetTester tester, {
    A11ySize size = A11ySize.phone,
    double textScale = 1,
    ThemeData? theme,
  }) async {
    final (h, s) = await setUp(tester, size: size, textScale: textScale);
    // An empty agenda, so the preview has new sessions to save.
    await h.io(() => h.t.plannedSessions.deleteAllFor(s.conference.id));
    await tester.pumpWidget(
      h.app(
        AgendaImportScreen(conference: s.conference),
        theme: theme,
        extra: extra,
      ),
    );
    await h.settle();
    final choose = find.byKey(const Key('agenda-choose-file-button'));
    await tester.ensureVisible(choose);
    await h.settle(2);
    await tester.tap(choose);
    await h.settle();
    expect(find.byKey(const Key('agenda-preview-summary')), findsOneWidget);
    return h;
  }

  Future<A11yHarness> sheet(
    WidgetTester tester, {
    double textScale = 1,
    ThemeData? theme,
    bool pick = true,
  }) async {
    final (h, s) = await setUp(tester, textScale: textScale);
    await tester.pumpWidget(
      h.app(
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => StartActivitySheet.show(
                  context,
                  conferenceId: s.conference.id,
                ),
                child: const Text('Start'),
              ),
            ),
          ),
        ),
        theme: theme,
        extra: extra,
      ),
    );
    await h.settle();
    await tester.tap(find.text('Start'));
    await h.settle();
    expect(find.text('From the agenda'), findsOneWidget);
    if (pick) {
      await tester.tap(
        find.descendant(
          of: find.byType(ListTile),
          matching: find.text('Data Mesh in Practice'),
        ),
      );
      await h.settle();
      expect(find.byKey(const Key('start-from-agenda-button')), findsOne);
    }
    return h;
  }

  group('NFR-09 P2-07 agenda', () {
    for (final (themeName, theme) in [
      ('light', AppTheme.light()),
      ('dark', AppTheme.dark()),
    ]) {
      testWidgets('NFR-09 P2-07 conference page agenda ($themeName) meets '
          'the guidelines', (tester) async {
        final handle = tester.ensureSemantics();
        await home(tester, theme: theme);
        await expectMeetsGuidelines(tester);
        handle.dispose();
      });

      testWidgets('NFR-09 P2-07 import preview ($themeName) meets the '
          'guidelines', (tester) async {
        final handle = tester.ensureSemantics();
        await preview(tester, theme: theme);
        await expectMeetsGuidelines(tester);
        handle.dispose();
      });

      testWidgets('NFR-09 P2-07 start from the agenda ($themeName) meets the '
          'guidelines', (tester) async {
        final handle = tester.ensureSemantics();
        await sheet(tester, theme: theme);
        await expectMeetsGuidelines(tester);
        handle.dispose();
      });
    }

    for (final size in A11ySize.values) {
      testWidgets('NFR-09 P2-07 conference page agenda at 200% text on '
          '${size.name} has no overflow', (tester) async {
        final h = await home(tester, size: size, textScale: 2);
        await scrollThrough(tester, h);
      });

      testWidgets('NFR-09 P2-07 import preview at 200% text on ${size.name} '
          'has no overflow', (tester) async {
        final h = await preview(tester, size: size, textScale: 2);
        await scrollThrough(tester, h);
      });
    }

    testWidgets('NFR-09 P2-07 start from the agenda at 200% text has no '
        'overflow', (tester) async {
      final h = await sheet(tester, textScale: 2);
      await tester.tap(find.byKey(const Key('start-agenda-show-all')));
      await h.settle(2);
      await scrollThrough(tester, h);
    });

    testWidgets('NFR-09 P2-07 an agenda row reads its title, time, speakers '
        'and room as one item', (tester) async {
      final handle = tester.ensureSemantics();
      await home(tester);
      final row = tester.getSemantics(
        find
            .ancestor(
              of: find.text('Data Mesh in Practice'),
              matching: find.byType(ListTile),
            )
            .first,
      );
      expect(row.label, contains('Data Mesh in Practice'));
      expect(row.label, contains('Samlytics Data Services · Hall A'));
      handle.dispose();
    });
  });
}

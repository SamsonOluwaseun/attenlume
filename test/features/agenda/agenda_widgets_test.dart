import 'dart:convert';
import 'dart:io';

import 'package:attenlume/app/theme/app_theme.dart';
import 'package:attenlume/data/local_database/database_provider.dart';
import 'package:attenlume/data/repositories/repository_providers.dart';
import 'package:attenlume/domain/models/activity.dart';
import 'package:attenlume/domain/models/conference.dart';
import 'package:attenlume/domain/models/planned_session.dart';
import 'package:attenlume/domain/services/agenda_parser.dart';
import 'package:attenlume/domain/services/agenda_template.dart';
import 'package:attenlume/features/activities/consent_check_dialog.dart';
import 'package:attenlume/features/agenda/agenda_import_screen.dart';
import 'package:attenlume/features/agenda/agenda_providers.dart';
import 'package:attenlume/features/conferences/conference_home_screen.dart';
import 'package:attenlume/features/conferences/start_activity_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fixtures/fixtures.dart';

/// Hands back a fixed file instead of opening the system picker.
class FakeAgendaPicker implements AgendaFilePicker {
  FakeAgendaPicker(this.file);

  PickedAgendaFile? file;
  int calls = 0;

  @override
  Future<PickedAgendaFile?> pick({required int maxBytes}) async {
    calls++;
    return file;
  }
}

/// Records what would be saved instead of opening a Save dialog or the
/// share sheet.
class FakeTemplateSaver implements AgendaTemplateSaver {
  String? fileName;
  List<int>? bytes;
  String? reply = 'Template saved to agenda.csv';
  Object? error;

  @override
  Future<String?> save(String fileName, List<int> bytes) async {
    this.fileName = fileName;
    this.bytes = bytes;
    if (error case final e?) throw e;
    return reply;
  }
}

const agendaCsv =
    'title,speaker,room,start,end,type\n'
    'Opening keynote,Samlytics Data Services,Main stage,'
    '2026-11-04 09:00,2026-11-04 09:45,Keynote\n'
    'Data Mesh in Practice,Samlytics Data Services,Hall A,'
    '2026-11-04 10:00,2026-11-04 10:45,Talk\n'
    'Evening reception,,Foyer,2026-11-04 18:00,2026-11-04 20:00,Reception\n'
    ',,,2026-11-04 12:00,,\n'
    'Lunch,,,whenever,,\n';

void main() {
  late TestData t;
  late FakeAgendaPicker picker;
  late FakeTemplateSaver saver;
  // 10:10 London time on the first day: the talk at 10:00 is on now.
  final now = DateTime.utc(2026, 11, 4, 10, 10);

  setUp(() {
    t = TestData();
    saver = FakeTemplateSaver();
    picker = FakeAgendaPicker(
      PickedAgendaFile('agenda.csv', utf8.encode(agendaCsv)),
    );
  });
  tearDown(() => t.close());

  Widget app(Widget home) => ProviderScope(
    overrides: [
      appDatabaseProvider.overrideWithValue(t.db),
      conferenceRepositoryProvider.overrideWithValue(t.conferences),
      activityRepositoryProvider.overrideWithValue(t.activities),
      mediaAssetRepositoryProvider.overrideWithValue(t.media),
      plannedSessionRepositoryProvider.overrideWithValue(t.plannedSessions),
      agendaFilePickerProvider.overrideWithValue(picker),
      agendaTemplateSaverProvider.overrideWithValue(saver),
      agendaClockProvider.overrideWithValue(() => now),
    ],
    child: MaterialApp(theme: AppTheme.light(), home: home),
  );

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  Future<Conference> conference() => t.conferences.create(
    name: 'Samlytics Conference 2026',
    timezone: 'Europe/London',
    startDate: DateTime.utc(2026, 11, 4),
    endDate: DateTime.utc(2026, 11, 5),
  );

  Future<void> importCsv(Conference c, [String text = agendaCsv]) async {
    final result = parseAgendaFile(
      fileName: 'agenda.csv',
      bytes: utf8.encode(text),
      timezone: c.timezone,
    );
    await t.plannedSessions.addAll(
      c.id,
      result.entries,
      source: AgendaSource.csv,
    );
  }

  group('P2-07 import screen', () {
    testWidgets('P2-07 shows a preview with counts and reasons before saving, '
        'then saves only new sessions', (tester) async {
      phone(tester);
      final c = await conference();
      // One session is already on the agenda.
      await importCsv(
        c,
        'title,start,end\nOpening keynote,2026-11-04 09:00,2026-11-04 09:45\n',
      );
      int? popped;
      await tester.pumpWidget(
        app(
          Builder(
            builder: (context) => TextButton(
              onPressed: () async =>
                  popped = await AgendaImportScreen.open(context, c),
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Nothing is uploaded'), findsOneWidget);

      await tester.tap(find.byKey(const Key('agenda-choose-file-button')));
      await tester.pumpAndSettle();
      expect(picker.calls, 1);
      expect(
        find.text(
          '3 sessions found in agenda.csv. 2 new, 1 already on the agenda, '
          '2 rows skipped.',
        ),
        findsOneWidget,
      );
      // Nothing is saved before the user confirms.
      expect(await t.plannedSessions.countFor(c.id), 1);

      await tester.scrollUntilVisible(
        find.text('Line 6: Start time not understood: "whenever".'),
        200,
      );
      expect(find.text('Line 5: No title.'), findsOneWidget);
      expect(find.text('Data Mesh in Practice'), findsOneWidget);
      expect(find.text('Wed 4 Nov, 10:00 to 10:45'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.byKey(const Key('agenda-save-button')),
        200,
      );
      expect(find.text('Save 2 sessions'), findsOneWidget);
      await tester.tap(find.byKey(const Key('agenda-save-button')));
      await tester.pumpAndSettle();

      expect(popped, 2);
      final saved = await t.plannedSessions.listFor(c.id);
      expect(saved.map((s) => s.title), [
        'Opening keynote',
        'Data Mesh in Practice',
        'Evening reception',
      ]);
    });

    testWidgets('P2-07 a file that cannot be read says why and saves '
        'nothing', (tester) async {
      phone(tester);
      final c = await conference();
      picker.file = PickedAgendaFile(
        'people.csv',
        utf8.encode('name only\nSamlytics Data Services\n'),
      );
      await tester.pumpWidget(app(AgendaImportScreen(conference: c)));
      await tester.tap(find.byKey(const Key('agenda-choose-file-button')));
      await tester.pumpAndSettle();
      expect(find.textContaining('No title column found'), findsOneWidget);
      expect(find.byKey(const Key('agenda-save-button')), findsNothing);

      picker.file = const PickedAgendaFile('big.ics', [], tooLarge: true);
      await tester.tap(find.byKey(const Key('agenda-choose-file-button')));
      await tester.pumpAndSettle();
      expect(find.textContaining('larger than 2 MB'), findsOneWidget);
      expect(await t.plannedSessions.countFor(c.id), 0);
    });
  });

  group('P2-07 start from the agenda', () {
    Future<Activity?> openSheet(
      WidgetTester tester,
      Conference c, {
      PlannedSession? initial,
    }) async {
      Activity? created;
      await tester.pumpWidget(
        app(
          Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async => created = await StartActivitySheet.show(
                  context,
                  conferenceId: c.id,
                  initialSession: initial,
                ),
                child: const Text('Start'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();
      return created;
    }

    testWidgets('P2-07 lists sessions near now first and picking one fills in '
        'title, speaker, room and type', (tester) async {
      phone(tester);
      final c = await conference();
      await importCsv(c);
      Activity? created;
      await tester.pumpWidget(
        app(
          Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async => created = await StartActivitySheet.show(
                  context,
                  conferenceId: c.id,
                ),
                child: const Text('Start'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();

      expect(find.text('From the agenda'), findsOneWidget);
      final tiles = tester
          .widgetList<ListTile>(find.byType(ListTile))
          .map((t) => ((t.title as Text?)?.data))
          .toList();
      // On now first, then nearest: 09:00 keynote, then 18:00 reception.
      expect(tiles, [
        'Data Mesh in Practice',
        'Opening keynote',
        'Evening reception',
      ]);
      expect(find.textContaining('On now · Wed 4 Nov, 10:00'), findsOneWidget);

      await tester.tap(find.text('Data Mesh in Practice'));
      await tester.pumpAndSettle();
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, 'Data Mesh in Practice');
      expect(
        find.text(
          'Picked: Data Mesh in Practice. Type: Session. '
          'Samlytics Data Services · Hall A.',
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('start-from-agenda-button')));
      await tester.pumpAndSettle();
      expect(created, isNotNull);
      final a = (await t.activities.get(created!.id))!;
      expect(a.title, 'Data Mesh in Practice');
      expect(a.speakerNames, ['Samlytics Data Services']);
      expect(a.room, 'Hall A');
      expect(a.typeId, builtinTypeId('session'));
      expect(a.plannedStart, DateTime.utc(2026, 11, 4, 10));
    });

    testWidgets('P2-07 the picked session type comes from the file; a type '
        'chip overrides it and keeps the details', (tester) async {
      phone(tester);
      final c = await conference();
      await importCsv(c);
      await openSheet(tester, c);
      await tester.tap(find.text('Opening keynote'));
      await tester.pumpAndSettle();
      expect(find.text('Start keynote'), findsOneWidget);

      await tester.ensureVisible(
        find.byKey(const Key('activity-type-chip-workshop')),
      );
      await tester.tap(find.byKey(const Key('activity-type-chip-workshop')));
      await tester.pumpAndSettle();
      final a = (await t.activities.listForConference(c.id)).single;
      expect(a.title, 'Opening keynote');
      expect(a.typeId, builtinTypeId('workshop'));
      expect(a.room, 'Main stage');
    });

    testWidgets('P2-07 a networking session still asks the consent question '
        '(FR-ACT-07)', (tester) async {
      phone(tester);
      final c = await conference();
      await importCsv(c);
      await openSheet(tester, c);
      await tester.tap(find.text('Evening reception'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('start-from-agenda-button')));
      await tester.pumpAndSettle();
      expect(find.byType(ConsentCheckDialog), findsOneWidget);
    });

    testWidgets('P2-07 tapping a picked session again clears it', (
      tester,
    ) async {
      phone(tester);
      final c = await conference();
      await importCsv(c);
      await openSheet(tester, c);
      await tester.tap(find.text('Opening keynote'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(ListTile),
          matching: find.text('Opening keynote'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('start-from-agenda-button')), findsNothing);
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, isEmpty);
    });

    testWidgets('P2-07 without an agenda the sheet is unchanged', (
      tester,
    ) async {
      phone(tester);
      final c = await conference();
      await openSheet(tester, c);
      expect(find.text('From the agenda'), findsNothing);
      expect(find.byKey(const Key('activity-type-chip-session')), findsOne);
    });
  });

  group('P2-07 conference page', () {
    testWidgets('P2-07 lists planned sessions; tapping one opens Start '
        'activity with it picked; Clear agenda asks first', (tester) async {
      phone(tester);
      final c = await conference();
      await importCsv(c);
      await tester.pumpWidget(
        app(
          ConferenceHomeScreen(
            conferenceId: c.id,
            openRecorder: (_, _) async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Agenda (3 planned)'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Evening reception'), 200);
      expect(find.text('Wed 4 Nov, 18:00 to 20:00'), findsOneWidget);

      await tester.tap(find.text('Evening reception'));
      await tester.pumpAndSettle();
      expect(find.byType(StartActivitySheet), findsOneWidget);
      expect(find.text('Start networking'), findsOneWidget);
      await tester.tap(find.byTooltip('Cancel'));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.byKey(const Key('agenda-clear-button')),
        200,
      );
      await tester.tap(find.byKey(const Key('agenda-clear-button')));
      await tester.pumpAndSettle();
      expect(find.text('Clear the agenda?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('agenda-clear-confirm')));
      await tester.pumpAndSettle();
      expect(await t.plannedSessions.countFor(c.id), 0);
      expect(find.text('Agenda'), findsOneWidget);
      expect(find.text('Import agenda'), findsOneWidget);
    });

    testWidgets('P2-07 a long agenda shows the sessions near now, and all on '
        'request', (tester) async {
      phone(tester);
      final c = await conference();
      final rows = StringBuffer('title,start\n');
      for (var h = 8; h < 18; h++) {
        rows.writeln(
          'Talk at $h,2026-11-04 ${h.toString().padLeft(2, '0')}:00',
        );
      }
      await importCsv(c, rows.toString());
      await tester.pumpWidget(
        app(
          ConferenceHomeScreen(
            conferenceId: c.id,
            openRecorder: (_, _) async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Agenda (10 planned)'), findsOneWidget);
      expect(find.text('Talk at 10'), findsOneWidget);
      expect(find.text('Talk at 17'), findsNothing);
      await tester.scrollUntilVisible(
        find.byKey(const Key('agenda-show-all-button')),
        200,
      );
      await tester.tap(find.byKey(const Key('agenda-show-all-button')));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Talk at 17'), 200);
      expect(find.text('Talk at 17'), findsOneWidget);
    });
  });

  group('P2-07a CSV template', () {
    testWidgets('FR-ACT-10 Download CSV template sits beside Import agenda and '
        'saves the template', (tester) async {
      phone(tester);
      final c = await conference();
      await tester.pumpWidget(
        app(
          ConferenceHomeScreen(
            conferenceId: c.id,
            openRecorder: (_, _) async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      final button = find.byKey(const Key('agenda-template-button'));
      await tester.scrollUntilVisible(button, 200);
      expect(find.text('Import agenda'), findsOneWidget);
      expect(find.text('Download CSV template'), findsOneWidget);

      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(saver.fileName, agendaTemplateFileName);
      expect(saver.bytes, agendaCsvTemplateBytes());
      expect(find.text('Template saved to agenda.csv'), findsOneWidget);
    });

    testWidgets('FR-ACT-10 cancelling says nothing; a failed save says so', (
      tester,
    ) async {
      phone(tester);
      final c = await conference();
      await tester.pumpWidget(
        app(
          ConferenceHomeScreen(
            conferenceId: c.id,
            openRecorder: (_, _) async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      final button = find.byKey(const Key('agenda-template-button'));
      await tester.scrollUntilVisible(button, 200);

      saver.reply = null;
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);

      saver.error = const FileSystemException('denied');
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(
        find.text('The template could not be saved. Try another folder.'),
        findsOneWidget,
      );
    });
  });
}

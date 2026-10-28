import 'dart:async';
import 'dart:io';

import 'package:attenlume/app/theme/app_theme.dart';
import 'package:attenlume/data/filesystem/export_writer.dart';
import 'package:attenlume/data/local_database/database_provider.dart';
import 'package:attenlume/data/repositories/repository_providers.dart';
import 'package:attenlume/domain/models/enums.dart';
import 'package:attenlume/domain/services/export_service.dart';
import 'package:attenlume/features/conferences/conference_home_screen.dart';
import 'package:attenlume/features/export/export_providers.dart';
import 'package:attenlume/features/export/export_sheet.dart';
import 'package:attenlume/platform/share/export_sharer.dart';
import 'package:attenlume/platform/storage/free_space_probe.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fixtures/fake_export_sharer.dart';
import '../../fixtures/fake_free_space_probe.dart';
import '../../fixtures/fixtures.dart';

/// Real planning and preflight; [run] is recorded instead of writing.
class _RecordingExportService extends ExportService {
  _RecordingExportService(TestData t, Directory root, FreeSpaceProbe probe)
    : super(
        conferences: t.conferences,
        activities: t.activities,
        media: t.media,
        cuts: t.cuts,
        jobs: t.exports,
        mediaRoot: () async => root,
        tempRoot: () async => root,
        freeSpace: probe,
        reserveBytes: 0,
        clock: t.clock.call,
      );

  final runs = <(ExportRequest, String)>[];

  /// When set, [run] waits for it, so a test can act mid-export.
  Completer<void>? gate;
  Future<void>? lastCancel;

  @override
  Future<ExportOutcome> run(
    ExportRequest request, {
    required String destinationParent,
    void Function(ExportWriteProgress progress)? onProgress,
    Future<void>? cancel,
  }) async {
    runs.add((request, destinationParent));
    lastCancel = cancel;
    onProgress?.call(
      const ExportWriteProgress(
        filesDone: 1,
        filesTotal: 2,
        bytesDone: 10,
        bytesTotal: 20,
      ),
    );
    if (gate case final g?) await g.future;
    return ExportOutcome(
      jobId: 'job',
      outputPath:
          '$destinationParent/2026-11-04_data-summit-london'
          '${request.format == ExportFormat.zip ? '.zip' : ''}',
      fileCount: 7,
      bytes: 2048,
      verification: VerificationLevel.checksum,
    );
  }
}

class _FakeDestinations implements ExportDestinations {
  _FakeDestinations({this.initial, this.canChoose = false, this.picked});

  final String? initial;
  final String? picked;
  @override
  final bool canChoose;

  @override
  Future<String?> defaultFolder() async => initial;

  @override
  Future<String?> choose() async => picked;
}

/// Taps Export and accepts the FR-PRI-05 warning.
Future<void> startExport(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const Key('export-start')));
  await tester.tap(find.byKey(const Key('export-start')));
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('sensitive-export-warning')), findsOneWidget);
  await tester.tap(find.byKey(const Key('sensitive-export-continue')));
  await tester.pumpAndSettle();
}

void main() {
  late TestData t;
  late Directory root;
  late FakeFreeSpaceProbe probe;
  late _RecordingExportService service;

  setUp(() {
    t = TestData();
    root = Directory.systemTemp.createTempSync('export_sheet_test');
    probe = FakeFreeSpaceProbe(8 << 30);
    service = _RecordingExportService(t, root, probe);
  });

  tearDown(() async {
    await t.close();
    root.deleteSync(recursive: true);
  });

  Widget subject(
    WidgetTester tester,
    Widget child, {
    ExportDestinations? destinations,
    ExportSharer? sharer,
  }) {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    return ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(t.db),
        conferenceRepositoryProvider.overrideWithValue(t.conferences),
        activityRepositoryProvider.overrideWithValue(t.activities),
        mediaAssetRepositoryProvider.overrideWithValue(t.media),
        exportServiceProvider.overrideWithValue(service),
        exportDestinationsProvider.overrideWithValue(
          destinations ?? _FakeDestinations(initial: '/exports'),
        ),
        // Windows-like unless a test says otherwise: no share sheet.
        exportSharerProvider.overrideWithValue(
          sharer ?? FakeExportSharer(canShare: false),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: child),
      ),
    );
  }

  testWidgets(
    'FR-EXP-01 FR-EXP-10 sheet shows scope, format, audio, private off and size',
    (tester) async {
      final sample = await SampleConference.build(t);
      await tester.pumpWidget(
        subject(tester, ExportSheet(conferenceId: sample.conference.id)),
      );
      await tester.pumpAndSettle();

      for (final label in [
        'Whole conference',
        'One day',
        'Choose activities',
        'Everything',
        'Audio only',
        'Photos only',
        'Notes and details only',
        'Original recordings',
        'Trimmed copies',
        'Originals and cut list',
        'Folder',
        'ZIP',
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      final toggle = tester.widget<SwitchListTile>(
        find.byKey(const Key('export-include-private')),
      );
      expect(toggle.value, isFalse);
      final summary = tester.widget<Text>(
        find.byKey(const Key('export-preflight')),
      );
      expect(summary.data, contains('2 activities'));
      expect(summary.data, contains('1 private activity left out.'));
      expect(summary.data, contains('8.0 GB free there.'));
      expect(find.text('/exports'), findsOneWidget);
    },
  );

  testWidgets('FR-EXP-05 not enough space blocks the export', (tester) async {
    final sample = await SampleConference.build(t);
    probe.availableBytes = 100;
    await tester.pumpWidget(
      subject(tester, ExportSheet(conferenceId: sample.conference.id)),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('export-insufficient')), findsOneWidget);
    await tester.tap(find.byKey(const Key('export-start')));
    await tester.pumpAndSettle();
    expect(service.runs, isEmpty);
  });

  testWidgets('FR-EXP-02 FR-EXP-10 export uses the chosen options and shows '
      'where it went', (tester) async {
    final sample = await SampleConference.build(t);
    await tester.pumpWidget(
      subject(tester, ExportSheet(conferenceId: sample.conference.id)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('ZIP'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Trimmed copies'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('export-include-private')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.byKey(const Key('export-preflight'))).data,
      contains('3 activities'),
    );

    await startExport(tester);

    final (request, destination) = service.runs.single;
    expect(destination, '/exports');
    expect(request.format, ExportFormat.zip);
    expect(request.audioMode, ExportAudioMode.trimmed);
    expect(request.includePrivate, isTrue);
    expect(request.selection, isA<WholeConference>());
    expect(find.text('Export saved'), findsOneWidget);
    expect(
      find.text('/exports/2026-11-04_data-summit-london.zip'),
      findsOneWidget,
    );
  });

  testWidgets('FR-EXP-01 one activity from the activity details', (
    tester,
  ) async {
    final sample = await SampleConference.build(t);
    await tester.pumpWidget(
      subject(
        tester,
        ExportSheet(
          conferenceId: sample.conference.id,
          activityId: sample.keynote.id,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final summary = tester.widget<Text>(
      find.byKey(const Key('export-preflight')),
    );
    expect(summary.data, contains('1 activity,'));
    final box = tester.widget<CheckboxListTile>(
      find.byKey(Key('export-activity-${sample.keynote.id}')),
    );
    expect(box.value, isTrue);
  });

  testWidgets('FR-EXP-02 on Windows the user chooses the folder first', (
    tester,
  ) async {
    final sample = await SampleConference.build(t);
    await tester.pumpWidget(
      subject(
        tester,
        ExportSheet(conferenceId: sample.conference.id),
        destinations: _FakeDestinations(canChoose: true, picked: r'D:\Out'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Choose a folder for the export.'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('export-start')));
    await tester.tap(find.byKey(const Key('export-start')));
    await tester.pumpAndSettle();
    expect(service.runs, isEmpty);

    await tester.ensureVisible(find.byKey(const Key('export-choose-folder')));
    await tester.tap(find.byKey(const Key('export-choose-folder')));
    await tester.pumpAndSettle();
    expect(find.text(r'D:\Out'), findsOneWidget);
    await startExport(tester);
    expect(service.runs.single.$2, r'D:\Out');
  });

  testWidgets('FR-PRI-05 the sensitive-content warning comes before every '
      'export; Cancel stops it', (tester) async {
    final sample = await SampleConference.build(t);
    await tester.pumpWidget(
      subject(tester, ExportSheet(conferenceId: sample.conference.id)),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('export-start')));
    await tester.tap(find.byKey(const Key('export-start')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('sensitive-export-warning')), findsOneWidget);
    await tester.tap(find.byKey(const Key('sensitive-export-cancel')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('sensitive-export-warning')), findsNothing);
    expect(service.runs, isEmpty);
    expect(find.byKey(const Key('export-sheet')), findsOneWidget);

    await startExport(tester);
    expect(service.runs, hasLength(1));
    expect(find.text('Export saved'), findsOneWidget);
  });

  testWidgets('FR-EXP-05 while exporting, Back and a tap outside do not '
      'close the sheet', (tester) async {
    final sample = await SampleConference.build(t);
    service.gate = Completer<void>();
    await tester.pumpWidget(
      subject(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () =>
                ExportSheet.show(context, conferenceId: sample.conference.id),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await startExport(tester);
    expect(find.byKey(const Key('export-progress')), findsOneWidget);

    // Back (system or app bar) asks the route to pop: refused.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('export-sheet')), findsOneWidget);
    // A tap on the barrier above the sheet: refused.
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('export-sheet')), findsOneWidget);
    // The close button is disabled while running.
    final close = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.close_rounded),
    );
    expect(close.onPressed, isNull);

    service.gate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Export saved'), findsOneWidget);
    // Finished: Back closes it again.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('export-sheet')), findsNothing);
  });

  testWidgets('FR-EXP-05 Cancel during an export reaches the service', (
    tester,
  ) async {
    final sample = await SampleConference.build(t);
    service.gate = Completer<void>();
    await tester.pumpWidget(
      subject(tester, ExportSheet(conferenceId: sample.conference.id)),
    );
    await tester.pumpAndSettle();
    await startExport(tester);
    var cancelled = false;
    unawaited(service.lastCancel!.then((_) => cancelled = true));
    await tester.ensureVisible(find.byKey(const Key('export-cancel')));
    await tester.tap(find.byKey(const Key('export-cancel')));
    await tester.pump();
    expect(cancelled, isTrue);
    service.gate!.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('FR-EXP-01 conference home has an Export action', (tester) async {
    final sample = await SampleConference.build(t);
    await tester.pumpWidget(
      subject(
        tester,
        ConferenceHomeScreen(
          conferenceId: sample.conference.id,
          openRecorder: (context, activity) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('export-conference-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('export-sheet')), findsOneWidget);
  });
  group('FR-EXP-02 ADR-042 sharing on Android and iOS', () {
    bool selected(WidgetTester tester, String label) => tester
        .widget<ChoiceChip>(find.byKey(Key('export-option-$label')))
        .selected;

    testWidgets('FR-EXP-02 ZIP is the default format on Android and iOS', (
      tester,
    ) async {
      final sample = await SampleConference.build(t);
      await tester.pumpWidget(
        subject(
          tester,
          ExportSheet(conferenceId: sample.conference.id),
          sharer: FakeExportSharer(),
        ),
      );
      await tester.pumpAndSettle();
      expect(selected(tester, 'ZIP'), isTrue);
      expect(selected(tester, 'Folder'), isFalse);
      expect(
        tester.widget<Text>(find.byKey(const Key('export-format-hint'))).data,
        contains('share to Files, Google Drive or an AI app'),
      );
      await startExport(tester);
      expect(service.runs.single.$1.format, ExportFormat.zip);
    });

    testWidgets('FR-EXP-02 Folder stays the default on Windows', (
      tester,
    ) async {
      final sample = await SampleConference.build(t);
      await tester.pumpWidget(
        subject(tester, ExportSheet(conferenceId: sample.conference.id)),
      );
      await tester.pumpAndSettle();
      expect(selected(tester, 'Folder'), isTrue);
      expect(selected(tester, 'ZIP'), isFalse);
    });

    testWidgets('FR-EXP-02 after a ZIP export Share opens the share sheet '
        'with the export file and shows its size', (tester) async {
      final sample = await SampleConference.build(t);
      final sharer = FakeExportSharer();
      await tester.pumpWidget(
        subject(
          tester,
          ExportSheet(conferenceId: sample.conference.id),
          sharer: sharer,
        ),
      );
      await tester.pumpAndSettle();
      await startExport(tester);

      expect(find.text('Export saved'), findsOneWidget);
      expect(find.byKey(const Key('export-share')), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('export-share-size'))).data,
        startsWith('2026-11-04_data-summit-london.zip, 2.0 KB.'),
      );
      expect(sharer.shared, isEmpty);

      await tester.ensureVisible(find.byKey(const Key('export-share')));
      await tester.tap(find.byKey(const Key('export-share')));
      await tester.pumpAndSettle();
      final call = sharer.shared.single;
      expect(call.path, '/exports/2026-11-04_data-summit-london.zip');
      expect(call.subject, '2026-11-04_data-summit-london');
      expect(call.origin, isNotNull);
      // Sharing does not close the sheet or remove the result.
      expect(find.text('Export saved'), findsOneWidget);
    });

    testWidgets('FR-EXP-02 a share sheet that fails to open says so', (
      tester,
    ) async {
      final sample = await SampleConference.build(t);
      final sharer = FakeExportSharer()..error = StateError('no activity');
      await tester.pumpWidget(
        subject(
          tester,
          ExportSheet(conferenceId: sample.conference.id),
          sharer: sharer,
        ),
      );
      await tester.pumpAndSettle();
      await startExport(tester);
      await tester.ensureVisible(find.byKey(const Key('export-share')));
      await tester.tap(find.byKey(const Key('export-share')));
      await tester.pumpAndSettle();
      expect(
        find.text('Couldn\'t open the share options. Try again.'),
        findsOneWidget,
      );
    });

    testWidgets('FR-EXP-02 a folder export on Android and iOS steers to ZIP '
        'instead of offering Share', (tester) async {
      final sample = await SampleConference.build(t);
      await tester.pumpWidget(
        subject(
          tester,
          ExportSheet(conferenceId: sample.conference.id),
          sharer: FakeExportSharer(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Folder'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.byKey(const Key('export-format-hint'))).data,
        contains('Choose ZIP'),
      );
      await startExport(tester);
      expect(service.runs.single.$1.format, ExportFormat.folder);
      expect(find.byKey(const Key('export-share')), findsNothing);
      expect(find.byKey(const Key('export-share-zip-hint')), findsOneWidget);
    });

    testWidgets('FR-EXP-02 on Windows there is no Share button after an '
        'export', (tester) async {
      final sample = await SampleConference.build(t);
      await tester.pumpWidget(
        subject(tester, ExportSheet(conferenceId: sample.conference.id)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('ZIP'));
      await tester.pumpAndSettle();
      await startExport(tester);
      expect(find.text('Export saved'), findsOneWidget);
      expect(find.byKey(const Key('export-share')), findsNothing);
      expect(find.byKey(const Key('export-share-zip-hint')), findsNothing);
      expect(find.byKey(const Key('export-copy-path')), findsOneWidget);
    });

    test('ADR-042 a ZIP is shared as application/zip', () {
      expect(SharePlusExportSharer.mimeTypeFor('/x/a.zip'), 'application/zip');
      expect(SharePlusExportSharer.mimeTypeFor('/x/A.ZIP'), 'application/zip');
      expect(
        SharePlusExportSharer.mimeTypeFor('/x/a'),
        'application/octet-stream',
      );
    });
  });
}

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
import 'package:attenlume/platform/storage/free_space_probe.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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

  @override
  Future<ExportOutcome> run(
    ExportRequest request, {
    required String destinationParent,
    void Function(ExportWriteProgress progress)? onProgress,
    Future<void>? cancel,
  }) async {
    runs.add((request, destinationParent));
    onProgress?.call(
      const ExportWriteProgress(
        filesDone: 1,
        filesTotal: 2,
        bytesDone: 10,
        bytesTotal: 20,
      ),
    );
    return ExportOutcome(
      jobId: 'job',
      outputPath: '$destinationParent/2026-11-04_data-summit-london',
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

    await tester.ensureVisible(find.byKey(const Key('export-start')));
    await tester.tap(find.byKey(const Key('export-start')));
    await tester.pumpAndSettle();

    final (request, destination) = service.runs.single;
    expect(destination, '/exports');
    expect(request.format, ExportFormat.zip);
    expect(request.audioMode, ExportAudioMode.trimmed);
    expect(request.includePrivate, isTrue);
    expect(request.selection, isA<WholeConference>());
    expect(find.text('Export saved'), findsOneWidget);
    expect(find.text('/exports/2026-11-04_data-summit-london'), findsOneWidget);
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
    await tester.ensureVisible(find.byKey(const Key('export-start')));
    await tester.tap(find.byKey(const Key('export-start')));
    await tester.pumpAndSettle();
    expect(service.runs.single.$2, r'D:\Out');
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
}

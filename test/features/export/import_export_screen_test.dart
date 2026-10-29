import 'dart:io';

import 'package:attenlume/app/theme/app_theme.dart';
import 'package:attenlume/data/filesystem/export_writer.dart';
import 'package:attenlume/data/filesystem/media_paths.dart';
import 'package:attenlume/data/local_database/database_provider.dart';
import 'package:attenlume/domain/models/enums.dart';
import 'package:attenlume/domain/services/device_timezone.dart';
import 'package:attenlume/domain/services/export_import_service.dart';
import 'package:attenlume/domain/services/export_service.dart';
import 'package:attenlume/features/capture/recording_providers.dart';
import 'package:attenlume/features/conferences/conference_list_screen.dart';
import 'package:attenlume/features/export/export_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../fixtures/fake_capture_engine.dart';
import '../../fixtures/fake_free_space_probe.dart';
import '../../fixtures/fixtures.dart';

class _FakeDeviceTimezoneService extends DeviceTimezoneService {
  const _FakeDeviceTimezoneService();

  @override
  Future<String> detectTimezone() async => 'Europe/London';
}

class _FakePicker implements ImportPicker {
  _FakePicker(this.path, {this.canPickFolder = true});

  final String path;
  @override
  final bool canPickFolder;
  var folderPicks = 0;

  @override
  Future<String?> pickFolder() async {
    folderPicks++;
    return path;
  }

  @override
  Future<String?> pickZip() async => null;
}

Future<ExportWriteResult> _inlineWriter(
  ExportWritePlan plan, {
  void Function(ExportWriteProgress progress)? onProgress,
  Future<void>? cancel,
}) => writeExport(plan, onProgress: onProgress);

void main() {
  late TestData source; // The device that exported.
  late TestData app; // The device the app runs on.
  late Directory temp;
  late String exportPath;

  setUp(() async {
    source = TestData();
    app = TestData();
    temp = await Directory.systemTemp.createTemp('import_screen_test');
    final media = Directory(p.join(temp.path, 'old', 'media'))
      ..createSync(recursive: true);
    final c = await source.conferences.create(
      name: 'Samlytics Conference 2026',
      timezone: 'Europe/London',
      startDate: DateTime.utc(2026, 11, 4),
    );
    final a = await source.activity(c.id, title: 'Data Mesh in Practice');
    final seg = await source.media.startSegment(
      activityId: a.id,
      filePath: 'pending.m4a',
      requestedProfile: RecordingProfile.balanced,
      codec: 'aac_lc',
      container: 'm4a',
      channelCount: 1,
      sampleRateHz: 48000,
      requestedBitrateBps: 48000,
      startUtc: DateTime.utc(2026, 11, 4, 9),
    );
    final rel = MediaPaths.segment(c.id, a.id, 1);
    final file = MediaPaths.resolve(media, rel);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(List.generate(3000, (i) => i % 200));
    await source.media.finaliseSegment(
      seg.id,
      endUtc: DateTime.utc(2026, 11, 4, 9, 1),
      endReason: SegmentEndReason.userStop,
      filePath: rel,
      durationMs: 60000,
      bytes: 3000,
    );
    await source.media.addBookmark(
      activityId: a.id,
      source: BookmarkSource.ui,
      atUtc: DateTime.utc(2026, 11, 4, 9, 0, 30),
      label: 'Key point',
    );
    final exporter = ExportService(
      conferences: source.conferences,
      activities: source.activities,
      media: source.media,
      cuts: source.cuts,
      jobs: source.exports,
      mediaRoot: () async => media,
      tempRoot: () async => Directory(p.join(temp.path, 'cache')),
      freeSpace: FakeFreeSpaceProbe(64 << 30),
      reserveBytes: 0,
      writer: _inlineWriter,
      clock: source.clock.call,
    );
    exportPath = (await exporter.run(
      ExportRequest(conferenceId: c.id),
      destinationParent: p.join(temp.path, 'dest'),
    )).outputPath;
  });

  tearDown(() async {
    await source.close();
    await app.close();
    await temp.delete(recursive: true);
  });

  Widget subject(_FakePicker picker) => ProviderScope(
    overrides: [
      appDatabaseProvider.overrideWithValue(app.db),
      deviceTimezoneServiceProvider.overrideWithValue(
        const _FakeDeviceTimezoneService(),
      ),
      audioCaptureEngineProvider.overrideWithValue(FakeCaptureEngine()),
      importPickerProvider.overrideWithValue(picker),
      exportImportServiceProvider.overrideWithValue(
        ExportImportService(
          db: app.db,
          activities: app.activities,
          mediaRoot: () async => Directory(p.join(temp.path, 'new', 'media')),
          freeSpace: FakeFreeSpaceProbe(64 << 30),
          reserveBytes: 0,
        ),
      ),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      home: const ConferenceListScreen(),
    ),
  );

  /// Real file and database work runs outside the fake clock.
  Future<void> pumpUntil(WidgetTester tester, Finder finder) async {
    for (var i = 0; i < 300 && finder.evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(finder, findsWidgets);
  }

  Future<void> openImport(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.tap(find.byKey(const Key('conference-list-menu')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('menu-settings')), findsOneWidget);
    await tester.tap(find.byKey(const Key('menu-import')));
    await tester.pumpAndSettle();
    expect(find.text('Import an export'), findsWidgets);
  }

  testWidgets('FR-EXP-11 Import an export from My conferences: preview with '
      'checksum result, import and summary', (tester) async {
    final picker = _FakePicker(exportPath);
    await tester.pumpWidget(subject(picker));
    await pumpUntil(tester, find.textContaining('No active conferences'));

    await openImport(tester);
    await tester.tap(find.byKey(const Key('import-pick-folder')));
    await pumpUntil(tester, find.byKey(const Key('import-conference-name')));

    expect(picker.folderPicks, 1);
    expect(find.text('Samlytics Conference 2026'), findsOneWidget);
    expect(find.byKey(const Key('import-check-ok')), findsOneWidget);
    expect(find.textContaining('match checksums.sha256'), findsOneWidget);
    expect(find.text('Data Mesh in Practice'), findsOneWidget);
    expect(find.byKey(const Key('import-as-copy')), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('import-start')));
    await tester.tap(find.byKey(const Key('import-start')));
    await pumpUntil(tester, find.byKey(const Key('import-done')));
    expect(
      find.textContaining('1 activity, 1 recording, 0 photos, 1 bookmark'),
      findsOneWidget,
    );
    expect(find.text('The export itself was not changed.'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('import-close')));
    await tester.tap(find.byKey(const Key('import-close')));
    await tester.pumpAndSettle();
    await pumpUntil(tester, find.text('Samlytics Conference 2026'));
    final all = await tester.runAsync(
      () => app.conferences.getAll(includeArchived: true),
    );
    expect(all!.single.name, 'Samlytics Conference 2026');
  });

  testWidgets('FR-EXP-11 a checksum mismatch is shown and Import is '
      'disabled', (tester) async {
    await tester.runAsync(() async {
      final audio = Directory(exportPath)
          .listSync(recursive: true)
          .whereType<File>()
          .firstWhere((f) => f.path.endsWith('.m4a'));
      await audio.writeAsBytes([1, 2, 3], mode: FileMode.append);
    });
    await tester.pumpWidget(subject(_FakePicker(exportPath)));
    await pumpUntil(tester, find.textContaining('No active conferences'));
    await openImport(tester);
    await tester.tap(find.byKey(const Key('import-pick-folder')));
    await pumpUntil(tester, find.byKey(const Key('import-conference-name')));

    expect(find.byKey(const Key('import-check-failed')), findsOneWidget);
    expect(find.textContaining('Does not match: activities/'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('import-start')));
    await tester.tap(find.byKey(const Key('import-start')));
    await tester.pump();
    expect(find.byKey(const Key('import-done')), findsNothing);

    // Leaving discards the staged copies; nothing was imported.
    await tester.pageBack();
    await tester.pumpAndSettle();
    final all = await tester.runAsync(
      () => app.conferences.getAll(includeArchived: true),
    );
    expect(all, isEmpty);
  });

  testWidgets('FR-EXP-11 without a folder picker (phones and tablets) only '
      'the ZIP is offered', (tester) async {
    await tester.pumpWidget(
      subject(_FakePicker(exportPath, canPickFolder: false)),
    );
    await pumpUntil(tester, find.textContaining('No active conferences'));
    await openImport(tester);
    expect(find.byKey(const Key('import-pick-zip')), findsOneWidget);
    expect(find.byKey(const Key('import-pick-folder')), findsNothing);
    expect(find.text('On a phone or tablet, import the ZIP.'), findsOneWidget);
  });

  testWidgets('FR-EXP-11 on a desktop both choices are offered', (
    tester,
  ) async {
    await tester.pumpWidget(subject(_FakePicker(exportPath)));
    await pumpUntil(tester, find.textContaining('No active conferences'));
    await openImport(tester);
    expect(find.byKey(const Key('import-pick-zip')), findsOneWidget);
    expect(find.byKey(const Key('import-pick-folder')), findsOneWidget);
    expect(find.byKey(const Key('import-zip-only')), findsNothing);
  });
}

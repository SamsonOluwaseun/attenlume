import 'dart:io';

import 'package:attenlume/app/theme/app_theme.dart';
import 'package:attenlume/data/filesystem/media_paths.dart';
import 'package:attenlume/data/local_database/database_provider.dart';
import 'package:attenlume/data/repositories/repository_providers.dart';
import 'package:attenlume/domain/models/enums.dart';
import 'package:attenlume/features/capture/recording_providers.dart';
import 'package:attenlume/features/storage_manager/storage_manager_providers.dart';
import 'package:attenlume/features/storage_manager/storage_manager_screen.dart';
import 'package:attenlume/platform/storage/free_space_probe.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../fixtures/fixtures.dart';

class FixedFreeSpace implements FreeSpaceProbe {
  const FixedFreeSpace();

  @override
  Future<FreeSpace?> query(String path) async =>
      const FreeSpace(availableBytes: 50 << 30, totalBytes: 128 << 30);
}

/// Real database and file work only completes outside the fake clock of
/// `testWidgets`, so every set-up step runs in `tester.runAsync` and the
/// screen is pumped until it shows what is expected. Plain `pumpAndSettle`
/// never settles while the loading spinner turns and the work it waits for
/// cannot finish: that was why these tests used to hang.
void main() {
  late TestData t;
  late Directory sandbox;
  late Directory root;
  late Directory temp;

  setUp(() {
    t = TestData();
    sandbox = Directory.systemTemp.createTempSync('attenlume_storage_ui_');
    root = Directory(p.join(sandbox.path, 'media'))..createSync();
    temp = Directory(p.join(sandbox.path, 'cache'))..createSync();
  });

  tearDown(() async {
    await t.close();
    sandbox.deleteSync(recursive: true);
  });

  File write(String rel, int bytes) {
    final f = MediaPaths.resolve(root, rel);
    f.parent.createSync(recursive: true);
    f.writeAsBytesSync(List.filled(bytes, 1));
    return f;
  }

  Future<void> segment(String activityId, String rel, int bytes) async {
    write(rel, bytes);
    final s = await t.media.startSegment(
      activityId: activityId,
      filePath: rel,
      requestedProfile: RecordingProfile.balanced,
      codec: 'aac_lc',
      container: 'm4a',
      channelCount: 1,
      sampleRateHz: 48000,
      requestedBitrateBps: 48000,
      inputRoute: 'built_in',
      startUtc: t.clock(),
    );
    await t.media.finaliseSegment(
      s.id,
      endUtc: t.clock().add(const Duration(minutes: 1)),
      endReason: SegmentEndReason.userStop,
      durationMs: 60000,
      bytes: bytes,
      sha256: 'f' * 64,
      observedBitrateBps: 48000,
    );
  }

  Future<void> verifiedExport(String conferenceId) async {
    final job = await t.exports.create(
      conferenceId: conferenceId,
      scope: const {
        'kind': 'conference',
        'content': 'everything',
        'format': 'folder',
        'audio_mode': 'original',
        'include_private': true,
        'include_kept_originals': false,
      },
      format: ExportFormat.folder,
      audioMode: ExportAudioMode.original,
    );
    await t.exports.complete(job.id, VerificationLevel.checksum);
  }

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(t.db),
          conferenceRepositoryProvider.overrideWithValue(t.conferences),
          activityRepositoryProvider.overrideWithValue(t.activities),
          mediaAssetRepositoryProvider.overrideWithValue(t.media),
          cutRangeRepositoryProvider.overrideWithValue(t.cuts),
          exportJobRepositoryProvider.overrideWithValue(t.exports),
          mediaRootProvider.overrideWithValue(() async => root),
          storageTempRootProvider.overrideWithValue(() async => temp),
          freeSpaceProbeProvider.overrideWithValue(const FixedFreeSpace()),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const StorageManagerScreen(),
        ),
      ),
    );
  }

  /// Pumps, letting real work run between frames, until [finder] matches.
  Future<void> pumpUntil(WidgetTester tester, Finder finder) async {
    for (var i = 0; i < 200 && finder.evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(finder, findsWidgets);
  }

  /// Pumps until [finder] matches nothing.
  Future<void> pumpUntilGone(WidgetTester tester, Finder finder) async {
    for (var i = 0; i < 200 && finder.evaluate().isNotEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(finder, findsNothing);
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pump();
    await tester.tap(finder);
    await tester.pump();
  }

  testWidgets('FR-STO-05 shows sizes by kind, the conference and its export '
      'status', (tester) async {
    late String conferenceId;
    await tester.runAsync(() async {
      final conf = await t.conference();
      conferenceId = conf.id;
      final act = await t.activity(conf.id, title: 'Opening keynote');
      await segment(
        act.id,
        MediaPaths.segment(conf.id, act.id, 1),
        12 * 1024 * 1024,
      );
    });

    await open(tester);
    await pumpUntil(tester, find.byKey(const Key('storage-overview-card')));

    expect(find.text('Storage Manager'), findsOneWidget);
    expect(find.text('Audio: 12 MB'), findsOneWidget);
    expect(find.text('Photos: 0 B'), findsOneWidget);
    expect(find.text('Models: 0 B'), findsOneWidget);
    expect(find.textContaining('Free on this device:'), findsOneWidget);
    expect(find.text('Samlytics Conference 2026'), findsOneWidget);
    expect(find.text('Not exported'), findsOneWidget);
    expect(find.byKey(Key('export-conference-$conferenceId')), findsOneWidget);
  });

  testWidgets('FR-STO-05 FR-STO-06 activities show sizes; Delete local copies '
      'is off without a verified export and says why', (tester) async {
    late String conferenceId;
    late String activityId;
    await tester.runAsync(() async {
      final conf = await t.conference();
      conferenceId = conf.id;
      final act = await t.activity(conf.id, title: 'Morning keynote');
      activityId = act.id;
      await t.activity(conf.id, title: 'Afternoon workshop');
      await segment(act.id, MediaPaths.segment(conf.id, act.id, 1), 5000);
    });

    await open(tester);
    await pumpUntil(tester, find.text('Samlytics Conference 2026'));
    await tap(tester, find.text('Samlytics Conference 2026'));

    expect(find.text('Morning keynote'), findsOneWidget);
    expect(find.text('Afternoon workshop'), findsOneWidget);
    expect(
      find.byKey(Key('activity-storage-tile-$activityId')),
      findsOneWidget,
    );
    final button = tester.widget<TextButton>(
      find.byKey(Key('delete-local-conference-$conferenceId')),
    );
    expect(button.onPressed, isNull);
    expect(find.textContaining('Needs a verified export'), findsWidgets);
  });

  testWidgets('FR-STO-06 kept originals are listed and can be removed', (
    tester,
  ) async {
    late File original;
    await tester.runAsync(() async {
      final conf = await t.conference();
      final act = await t.activity(conf.id, title: 'Workshop');
      original = write(
        p.posix.join(
          MediaPaths.originalsFolder(conf.id, act.id),
          'segment-001.m4a',
        ),
        2 * 1024 * 1024,
      );
    });

    await open(tester);
    await pumpUntil(tester, find.text('Originals kept after trimming'));
    expect(find.text('1 file, 2.0 MB'), findsOneWidget);
    expect(
      find.text('Samlytics Conference 2026 · Workshop · 2.0 MB'),
      findsOneWidget,
    );

    await tap(tester, find.byKey(const Key('remove-kept-originals-button')));
    expect(find.text('Remove kept originals?'), findsOneWidget);
    await tap(
      tester,
      find.byKey(const Key('confirm-remove-kept-originals-dialog-button')),
    );
    await pumpUntilGone(tester, find.text('Originals kept after trimming'));
    expect(original.existsSync(), isFalse);
  });

  testWidgets('FR-STO-06 Delete local copies after a verified export shows a '
      'preview, then a separate confirmation, then deletes', (tester) async {
    late String conferenceId;
    late File audio;
    await tester.runAsync(() async {
      final conf = await t.conference();
      conferenceId = conf.id;
      final act = await t.activity(conf.id, title: 'Talk');
      final rel = MediaPaths.segment(conf.id, act.id, 1);
      await segment(act.id, rel, 3 * 1024 * 1024);
      audio = MediaPaths.resolve(root, rel);
      await verifiedExport(conf.id);
    });

    await open(tester);
    await pumpUntil(tester, find.text('Verified'));

    await tap(tester, find.byKey(Key('delete-local-conference-$conferenceId')));
    await pumpUntil(tester, find.text('Files to delete:'));
    expect(find.text('Audio recordings'), findsOneWidget);

    await tap(tester, find.byKey(const Key('continue-delete-local-button')));
    await pumpUntil(tester, find.text('Delete for good?'));
    expect(audio.existsSync(), isTrue);

    await tap(tester, find.byKey(const Key('confirm-delete-local-button')));
    await pumpUntil(tester, find.text('No conferences yet.'));
    expect(audio.existsSync(), isFalse);
  });

  testWidgets('FR-STO-06 Cancel at the confirmation deletes nothing', (
    tester,
  ) async {
    late String conferenceId;
    late File audio;
    await tester.runAsync(() async {
      final conf = await t.conference();
      conferenceId = conf.id;
      final act = await t.activity(conf.id, title: 'Talk');
      final rel = MediaPaths.segment(conf.id, act.id, 1);
      await segment(act.id, rel, 1000);
      audio = MediaPaths.resolve(root, rel);
      await verifiedExport(conf.id);
    });

    await open(tester);
    await pumpUntil(tester, find.text('Verified'));
    await tap(tester, find.byKey(Key('delete-local-conference-$conferenceId')));
    await pumpUntil(tester, find.text('Files to delete:'));
    await tap(tester, find.byKey(const Key('continue-delete-local-button')));
    await pumpUntil(tester, find.text('Delete for good?'));
    await tap(tester, find.text('Cancel'));
    await pumpUntilGone(tester, find.text('Delete for good?'));

    expect(audio.existsSync(), isTrue);
    expect(find.text('Samlytics Conference 2026'), findsOneWidget);
  });

  testWidgets('FR-STO-06 FR-REC-08 Clear temporary files removes orphaned '
      'waveforms and keeps partial recordings', (tester) async {
    late File orphan;
    late File partial;
    await tester.runAsync(() async {
      final conf = await t.conference();
      final act = await t.activity(conf.id);
      orphan = write(MediaPaths.waveform(conf.id, act.id, 'gone'), 1500);
      partial = write(
        MediaPaths.partial(MediaPaths.segment(conf.id, act.id, 1)),
        900,
      );
    });

    await open(tester);
    await pumpUntil(tester, find.byKey(const Key('clear-safe-temp-button')));
    await tap(tester, find.byKey(const Key('clear-safe-temp-button')));
    expect(find.text('Clear safe temporary files'), findsOneWidget);
    expect(find.textContaining('Unfinished recordings'), findsOneWidget);

    await tap(tester, find.byKey(const Key('confirm-clear-temp-button')));
    await pumpUntil(tester, find.textContaining('Cleared 1 temporary file'));
    expect(orphan.existsSync(), isFalse);
    expect(partial.existsSync(), isTrue);
  });

  testWidgets('FR-STO-06 Manage models explains that no models are '
      'downloaded', (tester) async {
    await open(tester);
    await pumpUntil(tester, find.byKey(const Key('manage-models-button')));
    await tap(tester, find.byKey(const Key('manage-models-button')));

    expect(find.text('Manage offline models'), findsOneWidget);
    expect(find.textContaining('No offline models'), findsOneWidget);
    await tap(tester, find.byKey(const Key('close-models-dialog-button')));
    await pumpUntilGone(tester, find.text('Manage offline models'));
  });
}

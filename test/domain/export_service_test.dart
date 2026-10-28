import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:attenlume/data/filesystem/export_space.dart';
import 'package:attenlume/data/filesystem/export_writer.dart';
import 'package:attenlume/data/filesystem/folder_export.dart';
import 'package:attenlume/data/filesystem/media_paths.dart';
import 'package:attenlume/data/filesystem/safe_export_paths.dart';
import 'package:attenlume/data/local_database/app_database.dart';
import 'package:attenlume/domain/models/activity.dart';
import 'package:attenlume/domain/models/enums.dart';
import 'package:attenlume/domain/models/media.dart';
import 'package:attenlume/domain/services/export_service.dart';
import 'package:attenlume/domain/services/permanent_trim_service.dart';
import 'package:attenlume/domain/services/private_notes.dart';
import 'package:attenlume/platform/audio_trimmer/mp4_sample_trimmer.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../fixtures/fake_free_space_probe.dart';
import '../fixtures/fixtures.dart';
import '../fixtures/mp4_fixture.dart';

Future<ExportWriteResult> inlineWriter(
  ExportWritePlan plan, {
  void Function(ExportWriteProgress progress)? onProgress,
  Future<void>? cancel,
}) {
  var cancelled = false;
  cancel?.then((_) => cancelled = true);
  return writeExport(
    plan,
    onProgress: onProgress,
    isCancelled: () => cancelled,
  );
}

void main() {
  late TestData t;
  late Directory temp;
  late Directory mediaRoot;
  late Directory dest;
  late FakeFreeSpaceProbe probe;
  late ExportService service;

  setUp(() async {
    t = TestData();
    temp = await Directory.systemTemp.createTemp('export_service_test');
    mediaRoot = Directory(p.join(temp.path, 'media'))..createSync();
    dest = Directory(p.join(temp.path, 'dest'))..createSync();
    probe = FakeFreeSpaceProbe(64 << 30);
    service = ExportService(
      conferences: t.conferences,
      activities: t.activities,
      media: t.media,
      cuts: t.cuts,
      jobs: t.exports,
      mediaRoot: () async => mediaRoot,
      tempRoot: () async => Directory(p.join(temp.path, 'cache')),
      freeSpace: probe,
      reserveBytes: 0,
      writer: inlineWriter,
      clock: t.clock.call,
    );
  });

  tearDown(() async {
    await t.close();
    await temp.delete(recursive: true);
  });

  /// A finalised segment whose file exists. [mp4] writes a real AAC-in-MP4
  /// fixture (about 10 s) so it can be trimmed.
  Future<RecordingSegment> segment(
    Activity a,
    DateTime start, {
    Duration length = const Duration(seconds: 10),
    bool mp4 = false,
    int fileBytes = 5000,
    SegmentState state = SegmentState.finalised,
  }) async {
    final s = await t.media.startSegment(
      activityId: a.id,
      filePath: 'pending.m4a',
      requestedProfile: RecordingProfile.balanced,
      codec: 'aac_lc',
      container: 'm4a',
      channelCount: 1,
      sampleRateHz: 48000,
      requestedBitrateBps: 48000,
      startUtc: start,
    );
    final rel = MediaPaths.segment(a.conferenceId, a.id, s.sequence);
    final file = MediaPaths.resolve(mediaRoot, rel);
    await file.parent.create(recursive: true);
    if (mp4) {
      await writeMp4Fixture(file);
    } else {
      await file.writeAsBytes(List.generate(fileBytes, (i) => i % 251));
    }
    return t.media.finaliseSegment(
      s.id,
      endUtc: start.add(length),
      endReason: SegmentEndReason.userStop,
      filePath: rel,
      durationMs: mp4 ? 10027 : length.inMilliseconds,
      bytes: file.lengthSync(),
      state: state,
    );
  }

  Future<Photo> photo(Activity a, DateTime at, {String? label}) async {
    final id = t.ids();
    final rel = MediaPaths.photo(a.conferenceId, a.id, id);
    final file = MediaPaths.resolve(mediaRoot, rel);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(List.filled(1200, 7));
    return t.media.addPhoto(
      id: id,
      activityId: a.id,
      filePath: rel,
      takenUtc: at,
      source: PhotoSource.inApp,
      label: label,
    );
  }

  /// A conference over two days: a keynote with audio, a photo, a
  /// bookmark and notes on day one; a session on day two; a private
  /// reflection on day one.
  Future<(String, Activity, Activity, Activity)> conference() async {
    final c = await t.conferences.create(
      name: 'Samlytics Conference 2026',
      timezone: 'Europe/London',
      startDate: DateTime.utc(2026, 11, 4),
      endDate: DateTime.utc(2026, 11, 5),
    );
    final day1 = DateTime.utc(2026, 11, 4, 9, 30);
    t.clock.set(day1);
    final keynote = await t.activity(
      c.id,
      typeKey: 'keynote',
      title: 'Data Mesh in Practice',
    );
    await segment(keynote, day1);
    await segment(keynote, day1.add(const Duration(minutes: 1)));
    await photo(keynote, day1.add(const Duration(seconds: 30)), label: 'Slide');
    await t.media.addBookmark(
      activityId: keynote.id,
      source: BookmarkSource.ui,
      atUtc: day1.add(const Duration(seconds: 5)),
      label: 'Key point, really',
    );
    await t.media.addBookmark(
      activityId: keynote.id,
      source: BookmarkSource.ui,
      atUtc: day1.add(const Duration(seconds: 6)),
      label: 'Private thought',
      note: 'My own view',
    );
    await t.activities.update(
      keynote.id,
      const ActivitiesCompanion(
        notesMd: Value(
          'Public note.\n\n**[Private reflection]** Secret.\n\n'
          '**[Quick thought]** Shareable.',
        ),
      ),
    );

    t.clock.set(DateTime.utc(2026, 11, 4, 12));
    final reflection = await t.activity(c.id, typeKey: 'personal_reflection');
    await segment(reflection, DateTime.utc(2026, 11, 4, 12));
    expect(reflection.isPrivate, isTrue);

    final day2 = DateTime.utc(2026, 11, 5, 11);
    t.clock.set(day2);
    final session = await t.activity(c.id, title: 'Catalogues');
    await segment(session, day2);
    return (c.id, keynote, reflection, session);
  }

  List<String> pathsOf(ExportPlan plan) =>
      plan.entries.map((e) => e.relativePath).toList();

  group('FR-EXP-01 scopes', () {
    test(
      'FR-EXP-01 whole conference holds every non-private activity',
      () async {
        final (id, _, _, _) = await conference();
        final plan = await service.plan(ExportRequest(conferenceId: id));
        expect(plan.rootName, '2026-11-04_samlytics-conference-2026');
        expect(plan.activityCount, 2);
        expect(plan.privateActivitiesExcluded, 1);
        final paths = pathsOf(plan);
        expect(paths.first, 'conference.json');
        expect(
          paths,
          containsAll([
            'activities/001_0930_keynote_data-mesh-in-practice/audio/segment-001.m4a',
            'activities/001_0930_keynote_data-mesh-in-practice/audio/segment-002.m4a',
            'activities/001_0930_keynote_data-mesh-in-practice/photos/2026-11-04T09-30-30Z_slide.jpg',
            'activities/001_0930_keynote_data-mesh-in-practice/activity.json',
            'activities/001_0930_keynote_data-mesh-in-practice/notes.md',
            'activities/001_0930_keynote_data-mesh-in-practice/bookmarks.csv',
            'activities/003_1100_session_catalogues/audio/segment-001.m4a',
          ]),
        );
        expect(paths.where((x) => x.contains('reflection')), isEmpty);
      },
    );

    test('FR-EXP-01 selected activities only', () async {
      final (id, _, _, session) = await conference();
      final plan = await service.plan(
        ExportRequest(
          conferenceId: id,
          selection: SelectedActivities({session.id}),
        ),
      );
      expect(plan.activityCount, 1);
      expect(
        pathsOf(plan).where((x) => x.startsWith('activities/')),
        everyElement(startsWith('activities/003_1100_session_catalogues/')),
      );
    });

    test('FR-EXP-01 one day uses the conference timezone', () async {
      final (id, _, _, _) = await conference();
      expect(await service.activityDays(id), [
        DateTime.utc(2026, 11, 4),
        DateTime.utc(2026, 11, 5),
      ]);
      final plan = await service.plan(
        ExportRequest(
          conferenceId: id,
          selection: OneDay(DateTime(2026, 11, 5)),
        ),
      );
      expect(plan.rootName, '2026-11-05_samlytics-conference-2026');
      expect(plan.activityCount, 1);
      expect(
        pathsOf(plan),
        contains('activities/003_1100_session_catalogues/activity.json'),
      );
    });

    test('FR-EXP-01 audio only, photos only, text and metadata only', () async {
      final (id, _, _, _) = await conference();
      Future<List<String>> files(ExportContent c) async => pathsOf(
        await service.plan(ExportRequest(conferenceId: id, content: c)),
      ).where((x) => x != 'conference.json').toList();

      final audio = await files(ExportContent.audioOnly);
      expect(audio, everyElement(endsWith('.m4a')));
      expect(audio, hasLength(3));

      final photos = await files(ExportContent.photosOnly);
      expect(photos, [
        'activities/001_0930_keynote_data-mesh-in-practice/photos/2026-11-04T09-30-30Z_slide.jpg',
      ]);

      final text = await files(ExportContent.textOnly);
      expect(
        text.where((x) => x.endsWith('.m4a') || x.endsWith('.jpg')),
        isEmpty,
      );
      expect(text, contains(endsWith('activity.json')));
      expect(text, contains(endsWith('notes.md')));
    });
  });

  group('FR-EXP-10 private toggle', () {
    Future<String> exportedNotes(String notesMd) async {
      final c = await t.conference();
      final a = await t.activity(c.id, title: 'Talk');
      await t.activities.update(
        a.id,
        ActivitiesCompanion(notesMd: Value(notesMd)),
      );
      final out = await service.run(
        ExportRequest(conferenceId: c.id, content: ExportContent.textOnly),
        destinationParent: dest.path,
      );
      final notes = Directory(out.outputPath)
          .listSync(recursive: true)
          .whereType<File>()
          .singleWhere((f) => p.basename(f.path) == 'notes.md');
      return notes.readAsStringSync();
    }

    test('FR-EXP-10 a multi-paragraph private thought (new format) is left '
        'out whole', () async {
      final notes = await exportedNotes(
        [
          'Public before.',
          formatQuickThought(
            'Secret one.\n\nSecret two.\n\nSecret three.',
            isPrivate: true,
          ),
          'Public after.',
        ].join('\n\n'),
      );
      expect(notes, isNot(contains('Secret')));
      expect(notes, isNot(contains('private reflection')));
      expect(notes, contains('Public before.'));
      expect(notes, contains('Public after.'));
    });

    test('FR-EXP-10 a multi-paragraph private thought (old format) is left '
        'out, with what follows up to the next marker', () async {
      final notes = await exportedNotes(
        'Public before.\n\n'
        '**[Private reflection]** Secret one.\n\n'
        'Secret two.\n\n'
        '**[Quick thought]** Shareable.',
      );
      expect(notes, isNot(contains('Secret')));
      expect(notes, contains('Public before.'));
      expect(notes, contains('Shareable.'));
    });

    test('FR-EXP-10 private items stay out by default', () async {
      final (id, keynote, _, _) = await conference();
      final out = await service.run(
        ExportRequest(conferenceId: id, content: ExportContent.textOnly),
        destinationParent: dest.path,
      );
      final folder = p.join(
        out.outputPath,
        'activities',
        '001_0930_keynote_data-mesh-in-practice',
      );
      final notes = File(p.join(folder, 'notes.md')).readAsStringSync();
      expect(notes, contains('Public note.'));
      expect(notes, contains('Shareable.'));
      expect(notes, isNot(contains('Secret')));
      final csv = File(p.join(folder, 'bookmarks.csv')).readAsStringSync();
      expect(csv, contains('"Key point, really"'));
      expect(csv, isNot(contains('My own view')));
      final json = jsonDecode(
        File(p.join(out.outputPath, 'conference.json')).readAsStringSync(),
      ) as Map<String, Object?>;
      expect(json['privacy'], {
        'private_activities_excluded': 1,
        'private_notes_excluded': 2,
      });
      expect(
        Directory(p.join(out.outputPath, 'activities'))
            .listSync()
            .map((d) => p.basename(d.path)),
        isNot(contains(contains('reflection'))),
      );
      expect(keynote.isPrivate, isFalse);
    });

    test(
      'FR-EXP-10 one toggle includes private activities and notes',
      () async {
        final (id, _, _, _) = await conference();
        final plan = await service.plan(
          ExportRequest(conferenceId: id, includePrivate: true),
        );
        expect(plan.activityCount, 3);
        expect(plan.privateActivitiesExcluded, 0);
        expect(plan.privateNotesExcluded, 0);
        expect(
          pathsOf(plan),
          contains(
            'activities/002_1200_reflection_reflection-1-12-00/audio/segment-001.m4a',
          ),
        );
      },
    );

    test(
      'FR-EXP-10 only private activities chosen: refused, nothing written',
      () async {
        final (id, _, reflection, _) = await conference();
        await expectLater(
          service.run(
            ExportRequest(
              conferenceId: id,
              selection: SelectedActivities({reflection.id}),
            ),
            destinationParent: dest.path,
          ),
          throwsA(isA<ExportException>()),
        );
        expect(dest.listSync(), isEmpty);
      },
    );
  });

  group('FR-EXP-02 formats', () {
    test('FR-EXP-02 folder export verifies against checksums.sha256', () async {
      final (id, _, _, _) = await conference();
      final out = await service.run(
        ExportRequest(conferenceId: id),
        destinationParent: dest.path,
      );
      expect(
        p.basename(out.outputPath),
        '2026-11-04_samlytics-conference-2026',
      );
      expect(out.verification, VerificationLevel.checksum);
      expect(await verifyChecksums(Directory(out.outputPath)), isEmpty);
      final job = await t.exports.get(out.jobId);
      expect(job!.state, ExportJobState.completed);
      expect(job.scope['kind'], 'conference');
      expect(job.lastError, isNull);
    });

    test('FR-EXP-02 ZIP export holds the same tree under one folder', () async {
      final (id, _, _, _) = await conference();
      final out = await service.run(
        ExportRequest(conferenceId: id, format: ExportFormat.zip),
        destinationParent: dest.path,
      );
      expect(
        p.basename(out.outputPath),
        '2026-11-04_samlytics-conference-2026.zip',
      );
      final input = InputFileStream(out.outputPath);
      final archive = ZipDecoder().decodeStream(input);
      final names = archive.files.map((f) => f.name).toList();
      expect(
        names,
        everyElement(startsWith('2026-11-04_samlytics-conference-2026/')),
      );
      expect(
        names,
        contains('2026-11-04_samlytics-conference-2026/checksums.sha256'),
      );
      final sums = utf8.decode(
        archive
            .findFile('2026-11-04_samlytics-conference-2026/checksums.sha256')!
            .content,
      );
      expect(sums.trim().split('\n'), hasLength(names.length - 1));
      await input.close();
    });

    test('FR-EXP-02 a second export never overwrites the first', () async {
      final (id, _, _, _) = await conference();
      final a = await service.run(
        ExportRequest(conferenceId: id),
        destinationParent: dest.path,
      );
      final b = await service.run(
        ExportRequest(conferenceId: id),
        destinationParent: dest.path,
      );
      expect(
        p.basename(b.outputPath),
        '2026-11-04_samlytics-conference-2026-2',
      );
      expect(Directory(a.outputPath).existsSync(), isTrue);
    });
  });

  group('FR-EXP-03 audio options', () {
    test('FR-EXP-03 FR-EXP-06 activity.json describes the trimmed file '
        'that was written', () async {
      final c = await t.conference();
      final a = await t.activity(c.id, title: 'Talk');
      final s = await segment(a, DateTime.utc(2026, 11, 4, 9), mp4: true);
      await t.cuts.add(a.id, startOffsetMs: 0, endOffsetMs: 5000);
      final background = ExportService(
        conferences: t.conferences,
        activities: t.activities,
        media: t.media,
        cuts: t.cuts,
        jobs: t.exports,
        mediaRoot: () async => mediaRoot,
        tempRoot: () async => Directory(p.join(temp.path, 'cache')),
        reserveBytes: 0,
        clock: t.clock.call,
      );
      for (final (name, svc) in [
        ('inline', service),
        ('isolate', background),
      ]) {
        final out = await svc.run(
          ExportRequest(conferenceId: c.id, audioMode: ExportAudioMode.trimmed),
          destinationParent: p.join(dest.path, name),
        );
        final root = Directory(out.outputPath);
        expect(await verifyChecksums(root), isEmpty, reason: name);
        final files = root.listSync(recursive: true).whereType<File>().toList();
        final trimmed = files.singleWhere((f) => f.path.endsWith('.m4a'));
        final json = jsonDecode(
          files
              .singleWhere((f) => p.basename(f.path) == 'activity.json')
              .readAsStringSync(),
        ) as Map<String, Object?>;
        final seg = (json['segments'] as List).single as Map<String, Object?>;
        expect(seg['file'], 'audio/segment-001-trimmed.m4a');
        expect(seg['trimmed'], isTrue);
        expect(seg['bytes'], trimmed.lengthSync(), reason: name);
        expect(seg['sha256'], await hashFileSha256(trimmed), reason: name);
        final sums = File(p.join(root.path, checksumFileName))
            .readAsStringSync();
        final rel = p.posix.joinAll(
          p.split(p.relative(trimmed.path, from: root.path)),
        );
        expect(sums, contains('${seg['sha256']}  $rel\n'));
        expect(seg['duration_ms'] as int, inInclusiveRange(4900, 5100));
        expect(seg['source_duration_ms'], s.durationMs);
        expect(seg['source_bytes'], s.bytes);
        expect(seg['kept_ranges_ms'], [
          [5000, s.durationMs],
        ]);
      }
    });

    test('FR-EXP-06 activity.json of copied audio matches checksums', () async {
      final c = await t.conference();
      final a = await t.activity(c.id, title: 'Talk');
      await segment(a, DateTime.utc(2026, 11, 4, 9));
      final out = await service.run(
        ExportRequest(conferenceId: c.id),
        destinationParent: dest.path,
      );
      final files = Directory(out.outputPath)
          .listSync(recursive: true)
          .whereType<File>()
          .toList();
      final audio = files.singleWhere((f) => f.path.endsWith('.m4a'));
      final json = jsonDecode(
        files
            .singleWhere((f) => p.basename(f.path) == 'activity.json')
            .readAsStringSync(),
      ) as Map<String, Object?>;
      final seg = (json['segments'] as List).single as Map<String, Object?>;
      expect(seg['trimmed'], isFalse);
      expect(seg['sha256'], await hashFileSha256(audio));
      expect(seg.containsKey('source_sha256'), isFalse);
    });

    test('FR-EXP-03 every file cuts.json names is in the export, after a '
        'permanent trim and a split', () async {
      final c = await t.conference();
      t.clock.set(DateTime.utc(2026, 11, 4, 9));

      // Permanent trim: the stored files become segment-001-trim-1.m4a
      // and segment-001-trim-2.m4a, exported as segment-001/-002.m4a.
      final trimmedActivity = await t.activity(c.id, title: 'Trimmed');
      await segment(trimmedActivity, DateTime.utc(2026, 11, 4, 9), mp4: true);
      await t.cuts.add(
        trimmedActivity.id,
        startOffsetMs: 3000,
        endOffsetMs: 6000,
      );
      await PermanentTrimService(
        activities: t.activities,
        media: t.media,
        cuts: t.cuts,
        trimmer: const Mp4SampleTrimmer(),
        mediaRoot: () async => mediaRoot,
        newId: t.ids.call,
      ).apply(trimmedActivity.id);
      final stored = await t.media.segmentsFor(trimmedActivity.id);
      expect(stored.map((s) => p.posix.basename(s.filePath)), [
        'segment-001-trim-1.m4a',
        'segment-001-trim-2.m4a',
      ]);

      // Split inside the second segment: part 2's only row names the
      // first part's segment-002.m4a, exported there as segment-001.m4a.
      t.clock.set(DateTime.utc(2026, 11, 4, 10));
      final splitActivity = await t.activity(c.id, title: 'Two talks');
      await segment(splitActivity, DateTime.utc(2026, 11, 4, 10));
      await segment(splitActivity, DateTime.utc(2026, 11, 4, 10, 0, 20));
      await t.activities.split(splitActivity.id, splitOffsetMs: 25000);

      final out = await service.run(
        ExportRequest(
          conferenceId: c.id,
          audioMode: ExportAudioMode.originalWithCuts,
        ),
        destinationParent: dest.path,
      );
      final manifests = Directory(out.outputPath)
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => p.basename(f.path) == 'cuts.json')
          .toList();
      expect(manifests, hasLength(3));
      final named = <String>[];
      for (final manifest in manifests) {
        final json = jsonDecode(manifest.readAsStringSync()) as Map;
        for (final s
            in (json['segments'] as List).cast<Map<String, Object?>>()) {
          final name = s['file_name'] as String;
          named.add(name);
          expect(
            File(p.joinAll([manifest.parent.path, ...p.posix.split(name)]))
                .existsSync(),
            isTrue,
            reason: '${manifest.path} names $name',
          );
        }
      }
      expect(
        named,
        everyElement(matches(RegExp(r'^audio/segment-\d{3}\.m4a$'))),
      );
      expect(named.where((n) => n.contains('trim')), isEmpty);
    });

    test('FR-EXP-03 originals plus cuts.json', () async {
      final (id, keynote, _, _) = await conference();
      await t.cuts.add(keynote.id, startOffsetMs: 0, endOffsetMs: 2000);
      final plan = await service.plan(
        ExportRequest(
          conferenceId: id,
          audioMode: ExportAudioMode.originalWithCuts,
        ),
      );
      expect(
        pathsOf(plan),
        contains('activities/001_0930_keynote_data-mesh-in-practice/cuts.json'),
      );
      final cuts = plan.entries.firstWhere(
        (e) => e.relativePath.endsWith('cuts.json'),
      );
      final json = jsonDecode(
        utf8.decode((cuts.source as TextExportSource).bytes),
      );
      expect((json as Map)['cuts'], [
        {'start_ms': 0, 'end_ms': 2000},
      ]);
    });

    test(
      'FR-EXP-03 trimmed copies drop cut audio, originals untouched',
      () async {
        final c = await t.conference();
        final a = await t.activity(c.id, title: 'Talk');
        final s = await segment(a, DateTime.utc(2026, 11, 4, 9), mp4: true);
        final source = MediaPaths.resolve(mediaRoot, s.filePath);
        final before = await hashFileSha256(source);
        await t.cuts.add(a.id, startOffsetMs: 0, endOffsetMs: 5000);

        for (final format in ExportFormat.values) {
          final out = await service.run(
            ExportRequest(
              conferenceId: c.id,
              format: format,
              audioMode: ExportAudioMode.trimmed,
            ),
            destinationParent: p.join(dest.path, format.key),
          );
          expect(out.fileCount, greaterThan(0));
          if (format == ExportFormat.folder) {
            final trimmed = Directory(out.outputPath)
                .listSync(recursive: true)
                .whereType<File>()
                .singleWhere((f) => f.path.endsWith('.m4a'));
            expect(p.basename(trimmed.path), 'segment-001-trimmed.m4a');
            expect(trimmed.lengthSync(), lessThan(source.lengthSync() * 0.7));
            expect(await verifyChecksums(Directory(out.outputPath)), isEmpty);
          }
        }
        expect(await hashFileSha256(source), before);
        // The ZIP's scratch copies are gone.
        expect(
          Directory(p.join(temp.path, 'cache', 'exports-temp')).existsSync()
              ? Directory(p.join(temp.path, 'cache', 'exports-temp')).listSync()
              : <FileSystemEntity>[],
          isEmpty,
        );
      },
    );
  });

  group('FR-EXP-05 preflight', () {
    test('FR-EXP-05 declines when space is short and writes nothing', () async {
      final (id, keynote, _, _) = await conference();
      final segs = await t.media.segmentsFor(keynote.id);
      final source = MediaPaths.resolve(mediaRoot, segs.first.filePath);
      final before = await hashFileSha256(source);
      probe.availableBytes = 1000;

      final report = await service.preflight(
        ExportRequest(conferenceId: id),
        dest.path,
      );
      expect(report.insufficient, isTrue);
      expect(report.destination.shortfallBytes, greaterThan(0));

      await expectLater(
        service.run(
          ExportRequest(conferenceId: id),
          destinationParent: dest.path,
        ),
        throwsA(isA<InsufficientSpaceException>()),
      );
      expect(dest.listSync(), isEmpty);
      expect(await hashFileSha256(source), before);
      final job = (await t.exports.forConference(id)).single;
      expect(job.state, ExportJobState.failed);
      expect(job.lastError, 'insufficient_space');
    });

    test(
      'FR-EXP-05 unknown free space is reported, not treated as plenty',
      () async {
        final (id, _, _, _) = await conference();
        probe.availableBytes = null;
        final report = await service.preflight(
          ExportRequest(conferenceId: id),
          dest.path,
        );
        expect(report.unknown, isTrue);
        expect(report.insufficient, isFalse);
      },
    );

    test('FR-EXP-05 ZIP with trimmed copies also checks temp space', () async {
      final c = await t.conference();
      final a = await t.activity(c.id);
      await segment(a, DateTime.utc(2026, 11, 4, 9), mp4: true);
      await t.cuts.add(a.id, startOffsetMs: 0, endOffsetMs: 5000);
      final report = await service.preflight(
        ExportRequest(
          conferenceId: c.id,
          format: ExportFormat.zip,
          audioMode: ExportAudioMode.trimmed,
        ),
        dest.path,
      );
      expect(report.plan.tempBytes, greaterThan(0));
      expect(report.temp, isNotNull);
      expect(probe.queriedPaths, contains(p.join(temp.path, 'cache')));
    });

    test(
      'FR-EXP-05 a failure mid-export removes the partial copy only',
      () async {
        final (id, keynote, _, _) = await conference();
        final segs = await t.media.segmentsFor(keynote.id);
        // The second file disappears after planning, so the copy fails.
        final failing = ExportService(
          conferences: t.conferences,
          activities: t.activities,
          media: t.media,
          cuts: t.cuts,
          jobs: t.exports,
          mediaRoot: () async => mediaRoot,
          tempRoot: () async => Directory(p.join(temp.path, 'cache')),
          reserveBytes: 0,
          writer: (plan, {onProgress, cancel}) async {
            MediaPaths.resolve(
              mediaRoot,
              segs.last.filePath,
            ).renameSync(p.join(temp.path, 'moved.m4a'));
            return writeExport(plan, onProgress: onProgress);
          },
          clock: t.clock.call,
        );
        await expectLater(
          failing.run(
            ExportRequest(conferenceId: id),
            destinationParent: dest.path,
          ),
          throwsA(isA<FileSystemException>()),
        );
        expect(dest.listSync(), isEmpty);
        expect(
          MediaPaths.resolve(mediaRoot, segs.first.filePath).existsSync(),
          isTrue,
        );
        final job = (await t.exports.forConference(id)).single;
        expect(job.state, ExportJobState.failed);
        expect(job.lastError, 'file_system_error');
      },
    );

    test('FR-EXP-05 cancelling removes the partial export', () async {
      final (id, _, _, _) = await conference();
      final cancel = Future<void>.value();
      await expectLater(
        service.run(
          ExportRequest(conferenceId: id),
          destinationParent: dest.path,
          cancel: cancel,
        ),
        throwsA(isA<ExportCancelledException>()),
      );
      expect(dest.listSync(), isEmpty);
      final job = (await t.exports.forConference(id)).single;
      expect(job.state, ExportJobState.cancelled);
    });
  });

  group('ADR-040 one export at a time', () {
    test('FR-EXP-05 a second export while one runs is refused and writes '
        'nothing', () async {
      final (id, _, _, _) = await conference();
      final gate = Completer<void>();
      final started = Completer<void>();
      final slow = ExportService(
        conferences: t.conferences,
        activities: t.activities,
        media: t.media,
        cuts: t.cuts,
        jobs: t.exports,
        mediaRoot: () async => mediaRoot,
        tempRoot: () async => Directory(p.join(temp.path, 'cache')),
        reserveBytes: 0,
        writer: (plan, {onProgress, cancel}) async {
          if (!started.isCompleted) started.complete();
          await gate.future;
          return inlineWriter(plan, onProgress: onProgress, cancel: cancel);
        },
        clock: t.clock.call,
      );
      final first = slow.run(
        ExportRequest(conferenceId: id),
        destinationParent: dest.path,
      );
      await started.future;
      expect(slow.isRunning, isTrue);
      await expectLater(
        slow.run(
          ExportRequest(conferenceId: id),
          destinationParent: p.join(temp.path, 'other'),
        ),
        throwsA(isA<ExportException>()),
      );
      expect(Directory(p.join(temp.path, 'other')).existsSync(), isFalse);
      expect(await t.exports.forConference(id), hasLength(1));

      gate.complete();
      final out = await first;
      expect(slow.isRunning, isFalse);
      expect(Directory(out.outputPath).existsSync(), isTrue);
      // Free again once the first has finished.
      await slow.run(
        ExportRequest(conferenceId: id),
        destinationParent: p.join(temp.path, 'other'),
      );
    });
  });

  group('FR-EXP-06 checksums', () {
    test('FR-EXP-06 checksums.sha256 lists every exported file', () async {
      final (id, _, _, _) = await conference();
      final out = await service.run(
        ExportRequest(conferenceId: id),
        destinationParent: dest.path,
      );
      final root = Directory(out.outputPath);
      final onDisk =
          root
              .listSync(recursive: true)
              .whereType<File>()
              .map(
                (f) => p.posix.joinAll(
                  p.split(p.relative(f.path, from: root.path)),
                ),
              )
              .where((x) => x != checksumFileName)
              .toList()
            ..sort();
      final listed = File(
        p.join(root.path, checksumFileName),
      ).readAsLinesSync().map((l) => l.substring(66)).toList()..sort();
      expect(listed, onDisk);
      expect(out.fileCount, onDisk.length);
    });
  });

  group('FR-EXP-07 safe paths', () {
    test('FR-EXP-07 hostile names give safe, short paths', () async {
      final c = await t.conferences.create(
        name: 'CON. ',
        timezone: 'Europe/London',
        startDate: DateTime.utc(2026, 11, 4),
      );
      t.clock.set(DateTime.utc(2026, 11, 4, 9));
      final a = await t.activity(
        c.id,
        title: 'Ünïcode: <A|B> "quoted" ${'very long title ' * 10}...',
      );
      await segment(a, DateTime.utc(2026, 11, 4, 9));
      await photo(
        a,
        DateTime.utc(2026, 11, 4, 9, 1),
        label: 'NUL ${'x' * 200}.',
      );
      final plan = await service.plan(ExportRequest(conferenceId: c.id));
      expect(plan.rootName, '2026-11-04_con');
      for (final e in plan.entries) {
        final full = '${plan.rootName}/${e.relativePath}';
        expect(isSafeExportPath(full), isTrue, reason: full);
        expect(full.length, lessThan(exportPathLengthLimit));
        for (final part in full.split('/').take(full.split('/').length - 1)) {
          expect(part.length, lessThanOrEqualTo(maxExportFolderNameLength));
        }
      }
      expect(
        pathsOf(plan).firstWhere((x) => x.contains('/audio/')),
        startsWith(
          'activities/001_0900_session_unicode-a-b-quoted-very-long-title',
        ),
      );
    });
  });

  group('ADR-036 shared file_path and kept originals', () {
    test('FR-EXP-04 a file two rows share goes in once per activity', () async {
      final c = await t.conference();
      final a = await t.activity(c.id, title: 'Talk');
      final s = await segment(a, DateTime.utc(2026, 11, 4, 9));
      // A second row naming the same file in the same activity.
      final dup = await t.media.startSegment(
        activityId: a.id,
        filePath: s.filePath,
        requestedProfile: RecordingProfile.balanced,
        codec: 'aac_lc',
        container: 'm4a',
        channelCount: 1,
        sampleRateHz: 48000,
        requestedBitrateBps: 48000,
        startUtc: DateTime.utc(2026, 11, 4, 9),
      );
      await t.media.finaliseSegment(
        dup.id,
        endUtc: DateTime.utc(2026, 11, 4, 9, 0, 10),
        endReason: SegmentEndReason.userStop,
        durationMs: 10000,
      );
      final plan = await service.plan(ExportRequest(conferenceId: c.id));
      expect(pathsOf(plan).where((x) => x.endsWith('.m4a')), hasLength(1));
    });

    test(
      'FR-EXP-04 a split inside a segment exports the file in each part',
      () async {
        final c = await t.conference();
        final a = await t.activity(c.id, title: 'Two talks');
        await segment(a, DateTime.utc(2026, 11, 4, 9));
        await t.activities.split(a.id, splitOffsetMs: 4000);
        final plan = await service.plan(
          ExportRequest(conferenceId: c.id, content: ExportContent.audioOnly),
        );
        final audio = pathsOf(plan).where((x) => x.endsWith('.m4a')).toList();
        expect(audio, hasLength(2));
        expect(audio.map((x) => x.split('/')[1]).toSet(), hasLength(2));
        final sources = plan.entries
            .where((e) => e.relativePath.endsWith('.m4a'))
            .map((e) => (e.source as FileExportSource).path)
            .toSet();
        expect(sources, hasLength(1));
      },
    );

    test('ADR-037 kept originals are left out unless asked', () async {
      final c = await t.conference();
      final a = await t.activity(c.id);
      await segment(a, DateTime.utc(2026, 11, 4, 9));
      final kept = MediaPaths.resolve(
        mediaRoot,
        '${MediaPaths.originalsFolder(c.id, a.id)}/segment-001.m4a',
      );
      await kept.parent.create(recursive: true);
      await kept.writeAsBytes([1, 2, 3]);

      final without = await service.plan(ExportRequest(conferenceId: c.id));
      expect(pathsOf(without).where((x) => x.contains('originals')), isEmpty);
      final withKept = await service.plan(
        ExportRequest(conferenceId: c.id, includeKeptOriginals: true),
      );
      expect(
        pathsOf(withKept).where((x) => x.contains('/audio/originals/')),
        hasLength(1),
      );
    });

    test('FR-REC-08 damaged segments are listed but not exported', () async {
      final c = await t.conference();
      final a = await t.activity(c.id);
      await segment(a, DateTime.utc(2026, 11, 4, 9));
      await segment(
        a,
        DateTime.utc(2026, 11, 4, 9, 1),
        state: SegmentState.damaged,
      );
      final plan = await service.plan(ExportRequest(conferenceId: c.id));
      expect(plan.segmentsSkipped, 1);
      expect(pathsOf(plan).where((x) => x.endsWith('.m4a')), hasLength(1));
      final json = plan.entries.firstWhere(
        (e) => e.relativePath.endsWith('activity.json'),
      );
      final map = jsonDecode(
        (json.source as GeneratedTextExportSource).build(const {}),
      ) as Map;
      expect(
        ((map['segments'] as List).last as Map)['not_exported_reason'],
        'damaged',
      );
    });
  });

  group('extension points for P1-22', () {
    test('contributors add root and activity documents', () async {
      final (id, _, _, _) = await conference();
      final extended = ExportService(
        conferences: t.conferences,
        activities: t.activities,
        media: t.media,
        cuts: t.cuts,
        jobs: t.exports,
        mediaRoot: () async => mediaRoot,
        tempRoot: () async => temp,
        writer: inlineWriter,
        contributors: const [
          BasicConferenceJsonContributor(),
          _ReadmeContributor(),
        ],
      );
      final paths = pathsOf(
        await extended.plan(ExportRequest(conferenceId: id)),
      );
      expect(paths, contains('README_START_HERE.md'));
      expect(paths, contains('prompts/blog_draft.md'));
      expect(
        paths,
        contains(
          'activities/001_0930_keynote_data-mesh-in-practice/activity.md',
        ),
      );
    });
  });
}

class _ReadmeContributor extends ExportContributor {
  const _ReadmeContributor();

  @override
  List<ExportDocument> rootDocuments(ExportContext context) => const [
    ExportDocument('README_START_HERE.md', '# Read me\n'),
    ExportDocument('prompts/blog_draft.md', 'Draft\n'),
  ];

  @override
  List<ExportDocument> activityDocuments(
    ExportContext context,
    ExportedActivity activity,
  ) => [ExportDocument('activity.md', '# ${activity.activity.title}\n')];
}

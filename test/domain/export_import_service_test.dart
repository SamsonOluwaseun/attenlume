import 'dart:convert';
import 'dart:io';

import 'package:attenlume/data/filesystem/export_import_source.dart';
import 'package:attenlume/data/filesystem/export_writer.dart';
import 'package:attenlume/data/filesystem/folder_export.dart';
import 'package:attenlume/data/filesystem/media_paths.dart';
import 'package:attenlume/data/local_database/app_database.dart';
import 'package:attenlume/domain/models/activity.dart';
import 'package:attenlume/domain/models/enums.dart';
import 'package:attenlume/domain/models/media.dart';
import 'package:attenlume/domain/services/export_import_service.dart';
import 'package:attenlume/domain/services/export_service.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../fixtures/fake_free_space_probe.dart';
import '../fixtures/fixtures.dart';
import '../fixtures/mp4_fixture.dart';

Future<ExportWriteResult> _inlineWriter(
  ExportWritePlan plan, {
  void Function(ExportWriteProgress progress)? onProgress,
  Future<void>? cancel,
}) => writeExport(plan, onProgress: onProgress);

/// IDs for rows the import makes, distinct from the fixtures' IDs.
class _ImportIds {
  int _next = 1;
  String call() =>
      'cccccccc-0000-4000-8000-${(_next++).toRadixString(16).padLeft(12, '0')}';
}

void main() {
  late TestData t; // The device that exported.
  late TestData u; // A new device.
  late Directory temp;
  late Directory mediaRoot;
  late Directory newMediaRoot;
  late Directory dest;
  late ExportService exporter;

  setUp(() async {
    t = TestData();
    u = TestData();
    temp = await Directory.systemTemp.createTemp('export_import_test');
    mediaRoot = Directory(p.join(temp.path, 'old', 'media'))
      ..createSync(recursive: true);
    newMediaRoot = Directory(p.join(temp.path, 'new', 'media'))
      ..createSync(recursive: true);
    dest = Directory(p.join(temp.path, 'dest'))..createSync();
    exporter = ExportService(
      conferences: t.conferences,
      activities: t.activities,
      media: t.media,
      cuts: t.cuts,
      jobs: t.exports,
      mediaRoot: () async => mediaRoot,
      tempRoot: () async => Directory(p.join(temp.path, 'cache')),
      freeSpace: FakeFreeSpaceProbe(64 << 30),
      reserveBytes: 0,
      writer: _inlineWriter,
      clock: t.clock.call,
    );
  });

  tearDown(() async {
    await t.close();
    await u.close();
    await temp.delete(recursive: true);
  });

  ExportImportService importer(TestData d, Directory root) =>
      ExportImportService(
        db: d.db,
        activities: d.activities,
        mediaRoot: () async => root,
        freeSpace: FakeFreeSpaceProbe(64 << 30),
        reserveBytes: 0,
        clock: () => DateTime.utc(2026, 12, 1, 10),
        newId: _ImportIds().call,
      );

  Future<RecordingSegment> segment(
    Activity a,
    DateTime start, {
    bool mp4 = false,
  }) async {
    final s = await t.media.startSegment(
      activityId: a.id,
      filePath: 'pending.m4a',
      requestedProfile: RecordingProfile.enhanced,
      codec: 'aac_lc',
      container: 'm4a',
      channelCount: 1,
      sampleRateHz: 48000,
      requestedBitrateBps: 64000,
      inputRoute: 'built_in',
      startUtc: start,
    );
    final rel = MediaPaths.segment(a.conferenceId, a.id, s.sequence);
    final file = MediaPaths.resolve(mediaRoot, rel);
    await file.parent.create(recursive: true);
    if (mp4) {
      await writeMp4Fixture(file);
    } else {
      await file.writeAsBytes(
        List.generate(4000 + s.sequence, (i) => (i * 7 + s.sequence) % 251),
      );
    }
    return t.media.finaliseSegment(
      s.id,
      endUtc: start.add(const Duration(seconds: 10)),
      endReason: SegmentEndReason.userStop,
      filePath: rel,
      durationMs: mp4 ? 10027 : 10000,
      bytes: file.lengthSync(),
      observedBitrateBps: 63000,
    );
  }

  Future<Photo> photo(Activity a, DateTime at, {String? label}) async {
    final id = t.ids();
    final rel = MediaPaths.photo(a.conferenceId, a.id, id);
    final file = MediaPaths.resolve(mediaRoot, rel);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(List.filled(1500, 9));
    return t.media.addPhoto(
      id: id,
      activityId: a.id,
      filePath: rel,
      takenUtc: at,
      source: PhotoSource.inApp,
      label: label,
      caption: 'Architecture slide',
      width: 40,
      height: 30,
    );
  }

  final day1 = DateTime.utc(2026, 11, 4, 9, 30);

  /// Samlytics Conference 2026 with goals, a keynote (two recordings, a
  /// photo, two bookmarks, a cut, an interruption, notes and follow-up)
  /// and a private reflection.
  Future<(String, Activity, Activity)> sample() async {
    final c = await t.conferences.create(
      name: 'Samlytics Conference 2026',
      timezone: 'Europe/London',
      venue: 'Samlytics Data Services',
      startDate: DateTime.utc(2026, 11, 4),
      endDate: DateTime.utc(2026, 11, 5),
      roleType: RoleType.speaker,
      roleText: 'Head of data',
      requestedOutputs: const [RequestedOutput.blog],
    );
    await t.conferences.addGoal(c.id, 'Learn about data mesh', priority: 1);
    await t.conferences.addGoal(c.id, 'Meet Samlytics Data Services');
    t.clock.set(day1);
    final keynote = await t.activity(
      c.id,
      typeKey: 'keynote',
      title: 'Data Mesh in Practice',
    );
    await t.activities.update(
      keynote.id,
      ActivitiesCompanion(
        speakerNames: const Value(['Speaker One']),
        organisation: const Value('Samlytics Data Services'),
        room: const Value('Hall A'),
        notesMd: const Value('Public note.\n\nSecond paragraph.'),
        followUpText: const Value('Email the slides.'),
        actualStart: Value(day1),
        status: const Value(ActivityStatus.completed),
        recordingPermissionStatus: const Value(
          RecordingPermissionStatus.permitted,
        ),
      ),
    );
    await segment(keynote, day1);
    await segment(keynote, day1.add(const Duration(seconds: 20)));
    final gap = await t.media.startInterruption(
      keynote.id,
      InterruptionReason.call,
      startUtc: day1.add(const Duration(seconds: 10)),
    );
    await t.media.endInterruption(
      gap.id,
      autoResumed: true,
      endUtc: day1.add(const Duration(seconds: 20)),
    );
    await photo(keynote, day1.add(const Duration(seconds: 25)), label: 'Slide');
    await t.media.addBookmark(
      activityId: keynote.id,
      source: BookmarkSource.ui,
      atUtc: day1.add(const Duration(seconds: 5)),
      label: '=Key point',
      note: 'Has, a "comma"',
    );
    await t.media.addBookmark(
      activityId: keynote.id,
      source: BookmarkSource.hotkey,
      atUtc: day1.add(const Duration(seconds: 22)),
      label: 'Follow up',
    );
    await t.cuts.add(
      keynote.id,
      startOffsetMs: 2000,
      endOffsetMs: 4000,
      reason: 'Coffee',
    );

    t.clock.set(DateTime.utc(2026, 11, 4, 12));
    final reflection = await t.activity(c.id, typeKey: 'personal_reflection');
    await segment(reflection, DateTime.utc(2026, 11, 4, 12));
    return (c.id, keynote, reflection);
  }

  Future<String> export(
    String conferenceId, {
    ExportFormat format = ExportFormat.folder,
    ExportContent content = ExportContent.everything,
    ExportAudioMode audioMode = ExportAudioMode.originalWithCuts,
    bool includePrivate = true,
    String sub = 'out',
  }) async {
    final out = await exporter.run(
      ExportRequest(
        conferenceId: conferenceId,
        format: format,
        content: content,
        audioMode: audioMode,
        includePrivate: includePrivate,
      ),
      destinationParent: p.join(dest.path, sub),
    );
    return out.outputPath;
  }

  /// Replaces a file in a folder export and its line in checksums.sha256,
  /// as if an older version had written it.
  Future<void> rewrite(String root, String rel, String? content) async {
    final file = File(p.joinAll([root, ...p.posix.split(rel)]));
    final sums = File(p.join(root, checksumFileName));
    final lines = sums
        .readAsLinesSync()
        .where((l) => l.isNotEmpty && !l.endsWith('  $rel'))
        .toList();
    if (content == null) {
      file.deleteSync();
    } else {
      file.writeAsStringSync(content);
      lines.add('${await hashFileSha256(file)}  $rel');
    }
    sums.writeAsStringSync('${lines.join('\n')}\n');
  }

  Map<String, Object?> readJson(String root, String rel) =>
      jsonDecode(File(p.join(root, rel)).readAsStringSync())
          as Map<String, Object?>;

  /// Checks that everything in the sample came back on [d].
  Future<void> expectSample(
    TestData d,
    Directory root,
    ImportSummary summary, {
    required String conferenceId,
    required Activity keynote,
  }) async {
    final conf = (await d.conferences.get(summary.conferenceId))!;
    expect(conf.name, startsWith('Samlytics Conference 2026'));
    expect(conf.timezone, 'Europe/London');
    expect(conf.venue, 'Samlytics Data Services');
    expect(conf.startDate, DateTime.utc(2026, 11, 4));
    expect(conf.roleType, RoleType.speaker);
    expect(conf.requestedOutputs, [RequestedOutput.blog]);
    final goals = await d.conferences.goalsFor(conf.id);
    expect(goals.map((g) => (g.goalText, g.priority)), [
      ('Learn about data mesh', 1),
      ('Meet Samlytics Data Services', null),
    ]);

    final acts = await d.activities.listForConference(conf.id);
    expect(acts.map((a) => a.title), [
      'Data Mesh in Practice',
      isNot('Data Mesh in Practice'),
    ]);
    final k = acts.first;
    expect(k.speakerNames, ['Speaker One']);
    expect(k.room, 'Hall A');
    expect(k.notesMd, 'Public note.\n\nSecond paragraph.');
    expect(k.followUpText, 'Email the slides.');
    expect(k.recordingPermissionStatus, RecordingPermissionStatus.permitted);
    expect(k.isPrivate, isFalse);
    expect(acts.last.isPrivate, isTrue);
    final type = (await d.activities.types()).singleWhere(
      (x) => x.id == k.typeId,
    );
    expect(type.key, 'keynote');

    final originals = await t.media.segmentsFor(keynote.id);
    final segs = await d.media.segmentsFor(k.id);
    expect(segs, hasLength(2));
    for (var i = 0; i < 2; i++) {
      final file = MediaPaths.resolve(root, segs[i].filePath);
      expect(
        segs[i].filePath,
        MediaPaths.segment(conf.id, k.id, i + 1),
        reason: '9.5 layout',
      );
      expect(file.existsSync(), isTrue);
      final source = MediaPaths.resolve(mediaRoot, originals[i].filePath);
      expect(segs[i].bytes, source.lengthSync());
      expect(segs[i].sha256, await hashFileSha256(source));
      expect(await hashFileSha256(file), segs[i].sha256);
      expect(segs[i].startUtc, originals[i].startUtc);
      expect(segs[i].endUtc, originals[i].endUtc);
      expect(segs[i].requestedProfile, RecordingProfile.enhanced);
      expect(segs[i].observedBitrateBps, 63000);
      expect(segs[i].state, SegmentState.finalised);
    }
    final photos = await d.media.photosFor(k.id);
    expect(photos.single.label, 'Slide');
    expect(photos.single.caption, 'Architecture slide');
    expect(photos.single.offsetMs, 25000);
    expect(photos.single.width, 40);
    expect(MediaPaths.resolve(root, photos.single.filePath).lengthSync(), 1500);
    final bookmarks = await d.media.bookmarksFor(k.id);
    expect(bookmarks.map((b) => (b.label, b.note, b.offsetMs, b.source)), [
      ('=Key point', 'Has, a "comma"', 5000, BookmarkSource.ui),
      ('Follow up', null, 22000, BookmarkSource.hotkey),
    ]);
    final cuts = await d.cuts.activeFor(k.id);
    expect(cuts.map((c) => (c.startOffsetMs, c.endOffsetMs, c.reason)), [
      (2000, 4000, 'Coffee'),
    ]);
    final gaps = await d.media.interruptionsFor(k.id);
    expect(gaps.single.reason, InterruptionReason.call);
    expect(gaps.single.endUtc, day1.add(const Duration(seconds: 20)));
  }

  group('FR-EXP-11 round trip', () {
    test('FR-EXP-11 folder export comes back as the same conference', () async {
      final (id, keynote, _) = await sample();
      final out = await export(id);
      final service = importer(u, newMediaRoot);
      final prepared = await service.prepare(out);
      final preview = prepared.preview;
      expect(preview.canImport, isTrue);
      expect(preview.isZip, isFalse);
      expect(preview.conferenceId, id);
      expect(preview.conferenceName, 'Samlytics Conference 2026');
      expect(preview.schemaVersion, 2);
      expect(preview.alreadyExists, isFalse);
      expect(preview.activities, hasLength(2));
      expect(preview.activities.first.segments, 2);
      expect(preview.activities.first.photos, 1);
      expect(preview.activities.first.bookmarks, 2);
      expect(preview.activities.first.hasNotes, isTrue);
      expect(preview.activities.first.cuts, 1);
      expect(preview.check.checked, greaterThan(10));

      final summary = await service.commit(prepared);
      expect(summary.asCopy, isFalse);
      expect(summary.conferenceId, id);
      expect(summary.activities, 2);
      expect(summary.segments, 3);
      expect(summary.photos, 1);
      expect(summary.bookmarks, 2);
      expect(summary.notes, 1);
      expect(summary.cuts, 1);
      await expectSample(
        u,
        newMediaRoot,
        summary,
        conferenceId: id,
        keynote: keynote,
      );
      // Same IDs on a new device.
      expect((await u.activities.listForConference(id)).first.id, keynote.id);
      // The staged copies are gone; the export is untouched.
      expect(
        Directory(p.join(newMediaRoot.parent.path, 'imports-temp'))
            .listSync(recursive: true)
            .whereType<File>(),
        isEmpty,
      );
      expect(await verifyChecksums(Directory(out)), isEmpty);
    });

    test('FR-EXP-11 ZIP export comes back as the same conference', () async {
      final (id, keynote, _) = await sample();
      final out = await export(id, format: ExportFormat.zip);
      expect(out, endsWith('.zip'));
      final service = importer(u, newMediaRoot);
      final prepared = await service.prepare(out);
      expect(prepared.preview.isZip, isTrue);
      expect(prepared.preview.canImport, isTrue);
      final summary = await service.commit(prepared);
      await expectSample(
        u,
        newMediaRoot,
        summary,
        conferenceId: id,
        keynote: keynote,
      );
      expect(File(out).existsSync(), isTrue);
    });

    test(
      'FR-EXP-11 the picked parent folder of an export also works',
      () async {
        final (id, _, _) = await sample();
        final out = await export(id);
        final prepared = await importer(
          u,
          newMediaRoot,
        ).prepare(p.dirname(out));
        expect(prepared.preview.conferenceId, id);
      },
    );

    test(
      'FR-EXP-11 private items come back only if they were exported',
      () async {
        final (id, _, _) = await sample();
        final out = await export(id, includePrivate: false);
        final service = importer(u, newMediaRoot);
        final summary = await service.commit(await service.prepare(out));
        final acts = await u.activities.listForConference(summary.conferenceId);
        expect(acts.map((a) => a.title), ['Data Mesh in Practice']);
      },
    );
  });

  group('FR-EXP-11 checksums', () {
    test('FR-EXP-11 a file that does not match is refused and nothing is '
        'imported', () async {
      final (id, keynote, _) = await sample();
      final out = await export(id);
      final audio = Directory(out)
          .listSync(recursive: true)
          .whereType<File>()
          .firstWhere((f) => f.path.endsWith('segment-001.m4a'));
      final bytes = audio.readAsBytesSync();
      bytes[10] = bytes[10] ^ 0xff;
      audio.writeAsBytesSync(bytes);

      final service = importer(u, newMediaRoot);
      final prepared = await service.prepare(out);
      expect(prepared.preview.canImport, isFalse);
      expect(prepared.preview.check.mismatched, hasLength(1));
      expect(
        prepared.preview.check.mismatched.single,
        endsWith('segment-001.m4a'),
      );
      await expectLater(
        service.commit(prepared),
        throwsA(isA<ExportImportException>()),
      );
      await service.discard(prepared);
      expect(await u.conferences.getAll(includeArchived: true), isEmpty);
      expect(
        Directory(p.join(newMediaRoot.path, 'conferences')).existsSync(),
        isFalse,
      );
      expect(keynote.id, isNotEmpty);
    });

    test('FR-EXP-11 a missing listed file fails the check', () async {
      final (id, _, _) = await sample();
      final out = await export(id);
      File(p.join(out, 'timeline.csv')).deleteSync();
      final prepared = await importer(u, newMediaRoot).prepare(out);
      expect(prepared.preview.canImport, isFalse);
      expect(prepared.preview.check.missing, ['timeline.csv']);
    });

    test('FR-EXP-11 an export without checksums.sha256 or a half-written '
        'export is refused', () async {
      final (id, _, _) = await sample();
      final out = await export(id);
      final partial = '$out.partial';
      await Directory(out).rename(partial);
      await expectLater(
        importer(u, newMediaRoot).prepare(partial),
        throwsA(isA<ExportImportException>()),
      );
      await Directory(partial).rename(out);
      File(p.join(out, checksumFileName)).deleteSync();
      await expectLater(
        importer(u, newMediaRoot).prepare(out),
        throwsA(
          isA<ExportImportException>().having(
            (e) => e.message,
            'message',
            contains('checksums.sha256'),
          ),
        ),
      );
    });

    test('FR-EXP-11 unsafe paths are rejected', () {
      expect(isSafeRelativePath('activities/a/audio/x.m4a'), isTrue);
      expect(isSafeRelativePath('../x'), isFalse);
      expect(isSafeRelativePath('/x'), isFalse);
      expect(isSafeRelativePath('a\\..\\x'), isFalse);
      expect(isSafeRelativePath('C:/x'), isFalse);
      expect(isSafeRelativePath('a//b'), isFalse);
    });
  });

  group('FR-EXP-11 existing conference', () {
    test('FR-EXP-11 an existing conference is imported as a copy with new '
        'IDs and nothing existing changes', () async {
      final (id, keynote, _) = await sample();
      final out = await export(id);
      final segsBefore = await t.media.segmentsFor(keynote.id);
      final bookmarksBefore = await t.media.bookmarksFor(keynote.id);
      final filesBefore = {
        for (final f in mediaRoot.listSync(recursive: true).whereType<File>())
          f.path: f.lengthSync(),
      };

      final service = importer(t, mediaRoot);
      final prepared = await service.prepare(out);
      expect(prepared.preview.alreadyExists, isTrue);
      final summary = await service.commit(prepared);
      expect(summary.asCopy, isTrue);
      expect(summary.conferenceId, isNot(id));
      expect(
        summary.conferenceName,
        'Samlytics Conference 2026 (imported copy)',
      );

      final all = await t.conferences.getAll(includeArchived: true);
      expect(all, hasLength(2));
      final original = (await t.conferences.get(id))!;
      expect(original.name, 'Samlytics Conference 2026');
      expect(await t.activities.listForConference(id), hasLength(2));
      final segsAfter = await t.media.segmentsFor(keynote.id);
      expect(
        segsAfter.map((s) => (s.id, s.filePath, s.sha256)),
        segsBefore.map((s) => (s.id, s.filePath, s.sha256)),
      );
      expect(
        (await t.media.bookmarksFor(keynote.id)).map((b) => b.id),
        bookmarksBefore.map((b) => b.id),
      );
      for (final e in filesBefore.entries) {
        expect(File(e.key).lengthSync(), e.value, reason: e.key);
      }

      final copies = await t.activities.listForConference(summary.conferenceId);
      expect(copies, hasLength(2));
      expect(copies.map((a) => a.id), isNot(contains(keynote.id)));
      final copySegs = await t.media.segmentsFor(copies.first.id);
      expect(
        copySegs
            .map((s) => s.id)
            .toSet()
            .intersection(segsBefore.map((s) => s.id).toSet()),
        isEmpty,
      );
      expect(
        copySegs.first.filePath,
        startsWith('conferences/${summary.conferenceId}/'),
      );
      await expectSample(
        t,
        mediaRoot,
        summary,
        conferenceId: summary.conferenceId,
        keynote: keynote,
      );
    });

    test('FR-EXP-11 the user can ask for a copy of a new conference', () async {
      final (id, _, _) = await sample();
      final out = await export(id);
      final service = importer(u, newMediaRoot);
      final summary = await service.commit(
        await service.prepare(out),
        asCopy: true,
      );
      expect(summary.asCopy, isTrue);
      expect(summary.conferenceId, isNot(id));
    });

    test('FR-EXP-11 leftover files are never overwritten', () async {
      final (id, keynote, _) = await sample();
      final out = await export(id);
      // A file left behind under the same path (rows deleted, files kept).
      final leftover = MediaPaths.resolve(
        newMediaRoot,
        MediaPaths.segment(id, keynote.id, 1),
      );
      await leftover.parent.create(recursive: true);
      await leftover.writeAsString('older file');
      final service = importer(u, newMediaRoot);
      final summary = await service.commit(await service.prepare(out));
      expect(leftover.readAsStringSync(), 'older file');
      final segs = await u.media.segmentsFor(keynote.id);
      expect(segs.first.filePath, endsWith('segment-001-2.m4a'));
      expect(summary.segments, 3);
    });
  });

  group('FR-EXP-11 schema versions', () {
    test('FR-EXP-11 schema 1 conference.json (P1-21) imports', () async {
      final (id, keynote, _) = await sample();
      final out = await export(id);
      final c = readJson(out, 'conference.json');
      final v1 = <String, Object?>{
        'schema_version': 1,
        for (final k in [
          'id',
          'name',
          'venue',
          'start_date',
          'end_date',
          'timezone',
          'role_type',
          'role_text',
          'goals',
          'requested_outputs',
          'exported_at_utc',
          'scope',
          'privacy',
        ])
          k: c[k],
        'activities': [
          for (final a in c['activities']! as List)
            {
              'id': (a as Map)['id'],
              'title': a['title'],
              'folder': a['folder'],
            },
        ],
      };
      await rewrite(out, 'conference.json', jsonEncode(v1));
      for (final f in [
        'README_START_HERE.md',
        'participant_goals.md',
        'timeline.csv',
        'analysis_prompt.md',
      ]) {
        await rewrite(out, f, null);
      }
      final service = importer(u, newMediaRoot);
      final prepared = await service.prepare(out);
      expect(prepared.preview.schemaVersion, 1);
      final summary = await service.commit(prepared);
      await expectSample(
        u,
        newMediaRoot,
        summary,
        conferenceId: id,
        keynote: keynote,
      );
    });

    test('FR-EXP-11 an export from a newer app version is refused', () async {
      final (id, _, _) = await sample();
      final out = await export(id);
      final c = readJson(out, 'conference.json')..['schema_version'] = 99;
      await rewrite(out, 'conference.json', jsonEncode(c));
      await expectLater(
        importer(u, newMediaRoot).prepare(out),
        throwsA(
          isA<ExportImportException>().having(
            (e) => e.message,
            'message',
            contains('newer version'),
          ),
        ),
      );
    });
  });

  group('FR-EXP-11 media-only and text-only exports', () {
    test('FR-EXP-11 audio only (schema 2) imports recordings at their '
        'times, with bookmarks but no text', () async {
      final (id, keynote, _) = await sample();
      final out = await export(id, content: ExportContent.audioOnly);
      final service = importer(u, newMediaRoot);
      final prepared = await service.prepare(out);
      expect(prepared.preview.content, 'audio_only');
      final summary = await service.commit(prepared);
      expect(summary.photos, 0);
      expect(summary.notes, 0);
      final acts = await u.activities.listForConference(id);
      final k = acts.first;
      expect(k.id, keynote.id);
      expect(k.title, 'Data Mesh in Practice');
      expect(k.notesMd, isNull);
      expect(acts.last.isPrivate, isTrue);
      final type = (await u.activities.types()).singleWhere(
        (x) => x.id == k.typeId,
      );
      expect(type.key, 'keynote');
      final segs = await u.media.segmentsFor(k.id);
      final originals = await t.media.segmentsFor(keynote.id);
      expect(segs.map((s) => s.startUtc), originals.map((s) => s.startUtc));
      expect(segs.map((s) => s.endUtc), originals.map((s) => s.endUtc));
      expect(segs.map((s) => s.sha256), [
        for (final s in originals)
          await hashFileSha256(MediaPaths.resolve(mediaRoot, s.filePath)),
      ]);
      expect(segs.first.durationMs, 10000, reason: 'from end minus start');
      expect(await u.media.photosFor(k.id), isEmpty);
      final bookmarks = await u.media.bookmarksFor(k.id);
      expect(bookmarks.map((b) => (b.offsetMs, b.label)), [
        (5000, null),
        (22000, null),
      ]);
      // originals with cuts.json restore the cut.
      expect((await u.cuts.activeFor(k.id)).single.startOffsetMs, 2000);
    });

    test('FR-EXP-11 photos only imports photos at their times', () async {
      final (id, keynote, _) = await sample();
      final out = await export(id, content: ExportContent.photosOnly);
      final service = importer(u, newMediaRoot);
      final summary = await service.commit(await service.prepare(out));
      expect(summary.segments, 0);
      expect(summary.photos, 1);
      final ph = (await u.media.photosFor(keynote.id)).single;
      expect(ph.takenUtc, day1.add(const Duration(seconds: 25)));
      expect(ph.label, isNull, reason: 'no user text in a photos-only export');
      expect(ph.offsetMs, isNull, reason: 'no recordings (9.4 rule)');
      expect(await u.cuts.activeFor(keynote.id), isEmpty);
    });

    test(
      'FR-EXP-11 notes and details only imports notes and bookmarks',
      () async {
        final (id, keynote, _) = await sample();
        final out = await export(id, content: ExportContent.textOnly);
        final service = importer(u, newMediaRoot);
        final summary = await service.commit(await service.prepare(out));
        expect(summary.segments, 0);
        expect(summary.photos, 0);
        expect(summary.bookmarks, 2);
        final k = (await u.activities.listForConference(id)).first;
        expect(k.notesMd, 'Public note.\n\nSecond paragraph.');
        expect(k.followUpText, 'Email the slides.');
        final b = await u.media.bookmarksFor(keynote.id);
        expect(b.first.label, '=Key point');
        expect(b.first.offsetMs, isNull);
      },
    );

    test('FR-EXP-11 schema 1 audio only places recordings from the first '
        'day and says so', () async {
      final (id, keynote, _) = await sample();
      final out = await export(id, content: ExportContent.audioOnly);
      final c = readJson(out, 'conference.json');
      c['schema_version'] = 1;
      c['activities'] = [
        for (final a in c['activities']! as List)
          {'id': (a as Map)['id'], 'title': a['title'], 'folder': a['folder']},
      ];
      await rewrite(out, 'conference.json', jsonEncode(c));
      await rewrite(out, 'timeline.csv', null);
      final service = importer(u, newMediaRoot);
      final prepared = await service.prepare(out);
      expect(prepared.preview.warnings, isNotEmpty);
      final summary = await service.commit(prepared);
      expect(summary.segments, 3);
      final k = (await u.activities.listForConference(id))
          .firstWhere((a) => a.id == keynote.id);
      final type = (await u.activities.types()).singleWhere(
        (x) => x.id == k.typeId,
      );
      expect(type.key, 'keynote', reason: 'from the folder name');
      final segs = await u.media.segmentsFor(k.id);
      expect(segs.first.startUtc, DateTime.utc(2026, 11, 4));
      expect(segs.map((s) => s.sha256).whereType<String>(), hasLength(2));
    });
  });

  group('FR-EXP-11 crafted exports', () {
    test('FR-EXP-11 IDs that are not UUIDs are replaced and nothing is '
        'written outside the media root', () async {
      final (id, _, _) = await sample();
      final out = await export(id);
      final c = readJson(out, 'conference.json')..['id'] = '../../escape';
      final acts = c['activities']! as List;
      final folder = (acts.first as Map)['folder'] as String;
      (acts.first as Map)['id'] = '../escape-activity';
      await rewrite(out, 'conference.json', jsonEncode(c));
      final a = readJson(out, '$folder/activity.json');
      a['id'] = r'..\..\escape';
      ((a['segments']! as List).first as Map)['id'] = r'C:\escape';
      ((a['photos']! as List).first as Map)['id'] = '/tmp/escape-photo';
      ((a['bookmarks']! as List).first as Map)['id'] = 'D:escape';
      await rewrite(out, '$folder/activity.json', jsonEncode(a));

      final service = importer(u, newMediaRoot);
      final prepared = await service.prepare(out);
      expect(prepared.preview.alreadyExists, isTrue);
      expect(prepared.preview.warnings.join(), contains('not in the form'));
      final summary = await service.commit(prepared);
      expect(summary.asCopy, isTrue);
      expect(isImportableId(summary.conferenceId), isTrue);
      final imported = await u.activities.listForConference(
        summary.conferenceId,
      );
      expect(imported, hasLength(2));
      for (final act in imported) {
        expect(isImportableId(act.id), isTrue);
        for (final s in await u.media.segmentsFor(act.id)) {
          expect(isImportableId(s.id), isTrue);
          expect(
            s.filePath,
            startsWith('conferences/${summary.conferenceId}/'),
          );
        }
        for (final ph in await u.media.photosFor(act.id)) {
          expect(isImportableId(ph.id), isTrue);
        }
        for (final b in await u.media.bookmarksFor(act.id)) {
          expect(isImportableId(b.id), isTrue);
        }
      }
      // Every file the import wrote is inside the new media root.
      final newRoot = Directory(p.join(temp.path, 'new'));
      for (final f in newRoot.listSync(recursive: true).whereType<File>()) {
        expect(p.isWithin(newMediaRoot.path, f.path), isTrue, reason: f.path);
      }
      for (final e in temp.listSync()) {
        expect(
          ['old', 'new', 'dest', 'cache'],
          contains(p.basename(e.path)),
          reason: 'nothing written beside the test folders',
        );
      }
    });

    test(
      'FR-EXP-11 file names with .. or absolute paths are ignored',
      () async {
        final (id, keynote, _) = await sample();
        final out = await export(id);
        final c = readJson(out, 'conference.json');
        final folder =
            ((c['activities']! as List).first as Map)['folder'] as String;
        final a = readJson(out, '$folder/activity.json');
        ((a['segments']! as List).first as Map)['file'] =
            '../../conference.json';
        ((a['photos']! as List).first as Map)['file'] = '/etc/passwd';
        await rewrite(out, '$folder/activity.json', jsonEncode(a));
        final service = importer(u, newMediaRoot);
        final summary = await service.commit(await service.prepare(out));
        expect(await u.media.segmentsFor(keynote.id), hasLength(1));
        expect(await u.media.photosFor(keynote.id), isEmpty);
        expect(summary.segments, 2);
      },
    );

    test('FR-EXP-11 repeated IDs in one export import as a copy', () async {
      final (id, _, _) = await sample();
      final out = await export(id);
      final c = readJson(out, 'conference.json');
      final folder =
          ((c['activities']! as List).first as Map)['folder'] as String;
      final a = readJson(out, '$folder/activity.json');
      final bookmarks = a['bookmarks']! as List;
      (bookmarks[1] as Map)['id'] = (bookmarks[0] as Map)['id'];
      await rewrite(out, '$folder/activity.json', jsonEncode(a));
      final service = importer(u, newMediaRoot);
      final summary = await service.commit(await service.prepare(out));
      expect(summary.asCopy, isTrue);
      expect(summary.bookmarks, 2);
    });

    test('FR-EXP-11 destinations outside the media root are refused', () {
      final root = Directory(p.join(temp.path, 'media'));
      final inside = File(p.join(root.path, 'conferences', 'a', 'x.m4a'));
      expect(ensureInsideMediaRoot(root, inside), inside);
      for (final bad in [
        File(p.join(root.path, '..', 'x.m4a')),
        File(p.join(root.path, 'conferences', '..', '..', 'x.m4a')),
        File(p.join(temp.path, 'elsewhere', 'x.m4a')),
        File(root.path),
      ]) {
        expect(
          () => ensureInsideMediaRoot(root, bad),
          throwsA(isA<ExportImportException>()),
          reason: bad.path,
        );
      }
      expect(isImportableId('aaaaaaaa-0000-4000-8000-000000000001'), isTrue);
      for (final bad in [
        '../x',
        r'..\x',
        '/abs',
        r'C:\x',
        'C:x',
        '',
        'aaaaaaaa-0000-4000-8000-00000000000g',
        null,
      ]) {
        expect(isImportableId(bad), isFalse, reason: '$bad');
      }
    });

    test('FR-EXP-11 a failed import leaves no new activity type, rows or '
        'files', () async {
      final c = await t.conferences.create(
        name: 'Samlytics Conference 2026',
        timezone: 'Europe/London',
      );
      final type = await t.activities.createCustomType('Samlytics stand');
      final a = await t.activities.create(
        conferenceId: c.id,
        typeId: type.id,
        title: 'Stand visit',
      );
      await segment(a, day1);
      await t.media.addBookmark(
        activityId: a.id,
        source: BookmarkSource.ui,
        atUtc: day1.add(const Duration(seconds: 3)),
        label: 'Ask about pricing',
      );
      final out = await export(c.id);
      final typesBefore = (await u.activities.types()).length;
      await u.db.customStatement(
        'CREATE TRIGGER fail_bookmarks BEFORE INSERT ON bookmarks '
        'BEGIN SELECT RAISE(ABORT, "test failure"); END',
      );
      final service = importer(u, newMediaRoot);
      final prepared = await service.prepare(out);
      await expectLater(service.commit(prepared), throwsA(anything));
      expect(await u.activities.types(), hasLength(typesBefore));
      expect(await u.conferences.getAll(includeArchived: true), isEmpty);
      final conferences = Directory(p.join(newMediaRoot.path, 'conferences'));
      expect(
        conferences.existsSync()
            ? conferences.listSync(recursive: true).whereType<File>()
            : const <File>[],
        isEmpty,
      );
      // Once the problem is gone, the same import works and adds the type.
      await u.db.customStatement('DROP TRIGGER fail_bookmarks');
      await service.commit(await service.prepare(out));
      expect(
        (await u.activities.types()).where((x) => x.label == 'Samlytics stand'),
        hasLength(1),
      );
    });
  });

  group('FR-EXP-11 activity types', () {
    /// An export whose only activity has a custom type, exported under
    /// [key] and [label].
    Future<(String, Activity)> customExport(String key, String label) async {
      final c = await t.conferences.create(
        name: 'Samlytics Conference 2026',
        timezone: 'Europe/London',
      );
      final type = await t.activities.createCustomType(label);
      final a = await t.activities.create(
        conferenceId: c.id,
        typeId: type.id,
        title: 'Evening talk',
      );
      final out = await export(c.id);
      final conf = readJson(out, 'conference.json');
      final folder =
          ((conf['activities']! as List).first as Map)['folder'] as String;
      final json = readJson(out, '$folder/activity.json')..['type'] = key;
      await rewrite(out, '$folder/activity.json', jsonEncode(json));
      return (out, a);
    }

    Future<void> addLocalType(String key, String label) => u.db
        .into(u.db.activityTypes)
        .insert(
          ActivityTypesCompanion.insert(
            id: 'dddddddd-0000-4000-8000-000000000001',
            key: key,
            label: label,
            icon: 'tag',
            isBuiltin: false,
            sortOrder: 50,
            createdAt: DateTime.utc(2026, 10, 1),
            updatedAt: DateTime.utc(2026, 10, 1),
          ),
        );

    test('FR-EXP-11 a custom type with the same key but another label is '
        'not reused; a new type with the exported label is made', () async {
      final (out, a) = await customExport('workshop-2', 'Fireside chat');
      await addLocalType('workshop-2', 'Hackathon');
      final service = importer(u, newMediaRoot);
      await service.commit(await service.prepare(out));
      final imported = (await u.activities.listForConference(a.conferenceId))
          .single;
      final types = await u.activities.types();
      final used = types.singleWhere((x) => x.id == imported.typeId);
      expect(used.label, 'Fireside chat');
      expect(used.isBuiltin, isFalse);
      expect(used.key, isNot('workshop-2'));
      final hackathon = types.singleWhere((x) => x.key == 'workshop-2');
      expect(hackathon.label, 'Hackathon', reason: 'existing type unchanged');
    });

    test('FR-EXP-11 a local custom type with the same label is reused, '
        'whatever its key', () async {
      final (out, a) = await customExport(
        'custom_fireside-chat',
        'Fireside chat',
      );
      await addLocalType('custom_fireside-chat_3', ' fireside CHAT ');
      final before = (await u.activities.types()).length;
      final service = importer(u, newMediaRoot);
      await service.commit(await service.prepare(out));
      final imported = (await u.activities.listForConference(a.conferenceId))
          .single;
      expect(imported.typeId, 'dddddddd-0000-4000-8000-000000000001');
      expect(await u.activities.types(), hasLength(before));
    });

    test('FR-EXP-11 built-in types are matched by key', () async {
      final (id, keynote, _) = await sample();
      final out = await export(id);
      final service = importer(u, newMediaRoot);
      await service.commit(await service.prepare(out));
      final k = (await u.activities.listForConference(id)).first;
      expect(k.typeId, keynote.typeId);
    });
  });

  group('FR-EXP-11 trimmed copies', () {
    test('FR-EXP-11 a trimmed-copy export imports the trimmed files as the '
        'recordings and no cuts', () async {
      final c = await t.conferences.create(
        name: 'Samlytics Conference 2026',
        timezone: 'Europe/London',
      );
      final a = await t.activity(c.id, title: 'Talk');
      await segment(a, DateTime.utc(2026, 11, 4, 9), mp4: true);
      await t.cuts.add(a.id, startOffsetMs: 0, endOffsetMs: 5000);
      final out = await export(c.id, audioMode: ExportAudioMode.trimmed);
      final service = importer(u, newMediaRoot);
      final prepared = await service.prepare(out);
      expect(prepared.preview.audioMode, 'trimmed');
      expect(prepared.preview.warnings.join(), contains('trimmed copies'));
      final summary = await service.commit(prepared);
      expect(summary.cuts, 0);
      final seg = (await u.media.segmentsFor(a.id)).single;
      expect(seg.durationMs!, inInclusiveRange(4900, 5100));
      expect(
        seg.endUtc!.difference(seg.startUtc).inMilliseconds,
        seg.durationMs,
      );
      expect(await u.cuts.activeFor(a.id), isEmpty);
      expect(
        await hashFileSha256(MediaPaths.resolve(newMediaRoot, seg.filePath)),
        seg.sha256,
      );
    });
  });

  test('FR-EXP-11 notes.md and CSV parsing', () {
    expect(parseNotesMarkdown('# T\n\nA\n\nB\n'), ('A\n\nB', null));
    expect(parseNotesMarkdown('# T\n\nA\n\n## Follow-up\n\nCall back\n'), (
      'A',
      'Call back',
    ));
    expect(parseNotesMarkdown('# T\n\n## Follow-up\n\nOnly\n'), ('', 'Only'));
    expect(parseCsv('a,b\r\n"x, ""y""",z\r\n'), [
      ['a', 'b'],
      ['x, "y"', 'z'],
    ]);
  });
}

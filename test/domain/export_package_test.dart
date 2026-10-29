import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:attenlume/app/app_version.dart';
import 'package:attenlume/data/filesystem/export_writer.dart';
import 'package:attenlume/data/filesystem/folder_export.dart';
import 'package:attenlume/data/filesystem/media_paths.dart';
import 'package:attenlume/domain/models/activity.dart';
import 'package:attenlume/domain/models/enums.dart';
import 'package:attenlume/domain/services/export_package.dart';
import 'package:attenlume/domain/services/export_service.dart';
import 'package:attenlume/domain/services/private_notes.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../fixtures/fake_free_space_probe.dart';
import '../fixtures/fixtures.dart';

Future<ExportWriteResult> _inlineWriter(
  ExportWritePlan plan, {
  void Function(ExportWriteProgress progress)? onProgress,
  Future<void>? cancel,
}) => writeExport(plan, onProgress: onProgress, isCancelled: () => false);

const _keynoteFolder = 'activities/001_0930_keynote_data-mesh-in-practice';
const _gapsFolder = 'activities/001_0930_keynote_gaps';

void main() {
  late TestData t;
  late Directory temp;
  late Directory mediaRoot;
  late Directory dest;
  late ExportService service;

  setUp(() async {
    t = TestData();
    temp = await Directory.systemTemp.createTemp('export_package_test');
    mediaRoot = Directory(p.join(temp.path, 'media'))..createSync();
    dest = Directory(p.join(temp.path, 'dest'))..createSync();
    service = ExportService(
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
    await temp.delete(recursive: true);
  });

  Future<void> segment(Activity a, DateTime start, Duration length) async {
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
    await file.writeAsBytes(List.generate(3000, (i) => i % 251));
    await t.media.finaliseSegment(
      s.id,
      endUtc: start.add(length),
      endReason: SegmentEndReason.userStop,
      filePath: rel,
      durationMs: length.inMilliseconds,
      bytes: file.lengthSync(),
      observedBitrateBps: 47000,
    );
  }

  /// Samlytics Conference 2026 in [timezone]: a keynote at 09:30 UTC
  /// recorded in two parts around a call, with a photo, a bookmark, a
  /// private thought and notes holding a private reflection; and a
  /// private conversation.
  Future<(String, Activity, Activity)> conference({
    String timezone = 'Europe/London',
  }) async {
    final c = await t.conferences.create(
      name: 'Samlytics Conference 2026',
      timezone: timezone,
      startDate: DateTime.utc(2026, 11, 4),
      endDate: DateTime.utc(2026, 11, 5),
      roleType: RoleType.speaker,
      roleText: 'Head of data at Samlytics Data Services',
      requestedOutputs: [
        RequestedOutput.briefing,
        RequestedOutput.linkedinPost,
      ],
    );
    await t.conferences.addGoal(c.id, 'Find reusable data products');
    await t.conferences.addGoal(
      c.id,
      'Learn how teams run a data mesh',
      priority: 1,
    );
    final start = DateTime.utc(2026, 11, 4, 9, 30);
    t.clock.set(start);
    final keynote = await t.activities.create(
      conferenceId: c.id,
      typeId: builtinTypeId('keynote'),
      title: 'Data Mesh in Practice',
      speakerNames: ['Samlytics Data Services speaker'],
      contactName: 'Hidden Contact Name',
      contactDetails: 'hidden-contact@example.invalid',
      notesMd: [
        'Public note about domains.',
        formatQuickThought('Secret reflection words.', isPrivate: true),
      ].join('\n\n'),
    );
    await segment(keynote, start, const Duration(minutes: 10));
    final call = await t.media.startInterruption(
      keynote.id,
      InterruptionReason.call,
      startUtc: start.add(const Duration(minutes: 10)),
    );
    await t.media.endInterruption(
      call.id,
      autoResumed: false,
      endUtc: start.add(const Duration(minutes: 12)),
    );
    await segment(
      keynote,
      start.add(const Duration(minutes: 12)),
      const Duration(minutes: 5),
    );
    final photoId = t.ids();
    final photoRel = MediaPaths.photo(c.id, keynote.id, photoId);
    final photoFile = MediaPaths.resolve(mediaRoot, photoRel);
    await photoFile.parent.create(recursive: true);
    await photoFile.writeAsBytes(List.filled(800, 3));
    await t.media.addPhoto(
      id: photoId,
      activityId: keynote.id,
      filePath: photoRel,
      takenUtc: start.add(const Duration(seconds: 30)),
      source: PhotoSource.inApp,
      label: 'Slide',
      caption: 'Whiteboard sketch caption',
    );
    await t.media.addBookmark(
      activityId: keynote.id,
      source: BookmarkSource.ui,
      atUtc: start.add(const Duration(seconds: 5)),
      label: 'Key point',
      note: 'Bookmark note text',
    );
    await t.media.addBookmark(
      activityId: keynote.id,
      source: BookmarkSource.ui,
      atUtc: start.add(const Duration(seconds: 6)),
      label: privateThoughtLabel,
      note: 'My own view on pricing',
    );

    t.clock.set(DateTime.utc(2026, 11, 4, 13));
    final private = await t.activities.create(
      conferenceId: c.id,
      typeId: builtinTypeId('business_conversation'),
      title: 'Confidential supplier chat',
      isPrivate: true,
      notesMd: 'Supplier pricing details.',
    );
    await segment(
      private,
      DateTime.utc(2026, 11, 4, 13),
      const Duration(minutes: 3),
    );
    return (c.id, keynote, private);
  }

  Future<ExportOutcome> export(
    String id, {
    bool includePrivate = false,
    ExportFormat format = ExportFormat.folder,
    ExportContent content = ExportContent.everything,
  }) => service.run(
    ExportRequest(
      conferenceId: id,
      includePrivate: includePrivate,
      format: format,
      content: content,
    ),
    destinationParent: dest.path,
  );

  String read(ExportOutcome out, String rel) =>
      File(p.joinAll([out.outputPath, ...rel.split('/')])).readAsStringSync();

  /// Every generated text file in a folder export, by relative path.
  Map<String, String> generatedTexts(ExportOutcome out) {
    final root = Directory(out.outputPath);
    return {
      for (final f in root.listSync(recursive: true).whereType<File>())
        if (const ['.md', '.json', '.csv'].contains(p.extension(f.path)))
          p.posix.joinAll(p.split(p.relative(f.path, from: root.path))): f
              .readAsStringSync(),
    };
  }

  group('FR-EXP-09 README_START_HERE.md', () {
    test('FR-EXP-09 README explains contents, unzipping, ZIP size, AI tool '
        'limits and privacy', () async {
      final (id, _, _) = await conference();
      final plan = await service.plan(ExportRequest(conferenceId: id));
      expect(plan.entries.first.relativePath, readmeFileName);

      final out = await export(id);
      final readme = read(out, readmeFileName);
      expect(readme, startsWith('# Start here: Samlytics Conference 2026'));
      // What is inside.
      for (final name in [
        manifestFileName,
        participantGoalsFileName,
        timelineFileName,
        analysisPromptFileName,
        'prompts/',
        'activity.md',
        'notes.md',
        'audio/',
        'photos/',
        checksumFileName,
      ]) {
        expect(readme, contains(name), reason: name);
      }
      // How to unzip on each platform.
      expect(readme, contains('## How to unzip'));
      expect(readme, contains('Extract All'));
      expect(readme, contains('macOS'));
      expect(readme, contains('Files app'));
      // ZIP rarely shrinks compressed audio and photos.
      expect(readme, contains('ZIP rarely makes them smaller'));
      // AI tools differ and change their limits often.
      expect(
        readme,
        contains('AI tools differ in which file types and sizes they accept'),
      );
      expect(readme, contains('change these limits often'));
      // Privacy and consent.
      expect(readme, contains('## Privacy and consent'));
      expect(readme, contains('permission'));
      expect(
        readme,
        contains(
          'Private items were left out of this export: 1 private '
          'activity and 2 private thoughts or reflections.',
        ),
      );
      // UK English.
      expect(readme, isNot(contains('analyz')));
      expect(readme, isNot(contains('organiz')));
    });

    test('FR-EXP-09 an audio-only export still has the README, without '
        'notes files in its guide', () async {
      final (id, _, _) = await conference();
      final plan = await service.plan(
        ExportRequest(conferenceId: id, content: ExportContent.audioOnly),
      );
      final readme = plan.entries
          .firstWhere((e) => e.relativePath == readmeFileName)
          .source;
      final text = utf8.decode((readme as TextExportSource).bytes);
      expect(text, contains('audio/'));
      expect(text, isNot(contains('`notes.md`')));
      expect(text, isNot(contains('`photos/`')));
    });
  });

  group('BUILD_GUIDE 5.10 conference.json manifest', () {
    test('BUILD_GUIDE 5.10 manifest has the full fields and matches the '
        'activity folders', () async {
      final (id, keynote, _) = await conference();
      final out = await export(id);
      final json =
          jsonDecode(read(out, manifestFileName)) as Map<String, Object?>;
      expect(json['schema_version'], 2);
      expect(json['app'], {'name': 'Attenlume', 'version': appVersion});
      expect(json['id'], id);
      expect(json['title'], 'Samlytics Conference 2026');
      expect(json['name'], 'Samlytics Conference 2026');
      expect(json['start_date'], '2026-11-04');
      expect(json['end_date'], '2026-11-05');
      expect(json['timezone'], 'Europe/London');
      expect(json['role_type'], 'speaker');
      expect(json['role'], 'Speaker (Head of data at Samlytics Data Services)');
      expect(json['goals'], [
        {'text': 'Learn how teams run a data mesh', 'priority': 1},
        {'text': 'Find reusable data products', 'priority': null},
      ]);
      expect(json['requested_outputs'], ['briefing', 'linkedin_post']);
      expect(json['exported_at_utc'], '2026-11-04T13:00:00.000Z');
      expect(json['exported_at_local'], startsWith('2026-11-04T13:00:00'));
      expect((json['scope'] as Map)['include_private'], isFalse);
      expect(json['privacy'], {
        'private_activities_excluded': 1,
        'private_notes_excluded': 2,
      });
      expect(json['activity_ids'], [keynote.id]);
      final files = json['files'] as Map;
      expect(files['readme'], readmeFileName);
      expect(files['timeline'], timelineFileName);
      expect(files['analysis_prompt'], analysisPromptFileName);
      expect(files['prompts'], promptTemplateFileNames);
      expect(files['checksums'], checksumFileName);

      final activity = (json['activities'] as List).single as Map;
      expect(activity['id'], keynote.id);
      expect(activity['folder'], _keynoteFolder);
      expect(activity['type'], 'keynote');
      expect(activity['is_private'], isFalse);
      expect(activity['start_utc'], '2026-11-04T09:30:00.000Z');
      expect(activity['segments_exported'], 2);
      expect(activity['photos_exported'], 1);
      expect(activity['bookmark_count'], 1);
      expect(activity['interruption_count'], 1);
      final activityFiles = activity['files'] as Map;
      expect(activityFiles, {
        'activity_md': 'activity.md',
        'activity_json': 'activity.json',
        'notes': 'notes.md',
        'bookmarks': 'bookmarks.csv',
      });
      for (final f in activityFiles.values.cast<String>()) {
        expect(
          File(p.joinAll([out.outputPath, ..._keynoteFolder.split('/'), f]))
              .existsSync(),
          isTrue,
          reason: f,
        );
      }
      // participant_goals.md in plain English.
      final goals = read(out, participantGoalsFileName);
      expect(goals, contains('**Role:** Speaker (Head of data'));
      expect(goals, contains('1. Learn how teams run a data mesh'));
      expect(goals, contains('- Find reusable data products'));
      expect(goals, contains('- LinkedIn post'));
    });

    test('BUILD_GUIDE 5.10 app version matches pubspec.yaml', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final version = RegExp(
        r'^version:\s*(\S+)',
        multiLine: true,
      ).firstMatch(pubspec)!.group(1);
      expect(appVersion, version);
    });
  });

  group('BUILD_GUIDE 5.10 timeline.csv', () {
    test('BUILD_GUIDE 5.10 timeline has a row per segment, photo, bookmark, '
        'interruption and notes, in time order and the conference '
        'timezone', () async {
      // Tokyo is UTC+9 all year, so local times differ from UTC.
      final (id, _, _) = await conference(timezone: 'Asia/Tokyo');
      final out = await export(id);
      // Folder names use the local start time.
      const folder = 'activities/001_1830_keynote_data-mesh-in-practice';
      final lines = read(out, timelineFileName).split('\r\n')..removeLast();
      expect(lines.first, timelineCsvHeader);
      expect(
        lines.first,
        startsWith(
          'activity_id,activity_title,kind,file,utc_time,local_time,'
          'offset_seconds,label,profile,observed_bitrate_bps',
        ),
      );
      final rows = [for (final l in lines.skip(1)) l.split(',')];
      expect(rows.map((r) => r[2]), [
        'notes',
        'segment',
        'bookmark',
        'photo',
        'interruption',
        'segment',
      ]);
      final byKind = {for (final r in rows) r[2]: r};
      final bookmark = byKind['bookmark']!;
      expect(bookmark[1], 'Data Mesh in Practice');
      expect(bookmark[4], '2026-11-04T09:30:05.000Z');
      expect(bookmark[5], startsWith('2026-11-04T18:30:05'));
      expect(bookmark[5], endsWith('+0900'));
      expect(bookmark[6], '5.0');
      expect(bookmark[7], 'Key point');

      final photo = byKind['photo']!;
      expect(photo[3], startsWith('$folder/photos/'));
      expect(photo[6], '30.0');

      final interruption = byKind['interruption']!;
      expect(interruption[6], '600.0');
      expect(interruption[7], 'call');
      expect(interruption[10], '2026-11-04T09:42:00.000Z');
      expect(interruption[11], startsWith('2026-11-04T18:42:00'));

      final second = rows.lastWhere((r) => r[2] == 'segment');
      expect(second[3], '$folder/audio/segment-002.m4a');
      expect(second[6], '720.0');
      expect(second[8], 'balanced');
      expect(second[9], '47000');

      expect(byKind['notes']![3], '$folder/notes.md');
      // Every file it names is in the export.
      for (final r in rows.where((r) => r[3].isNotEmpty)) {
        expect(
          File(p.joinAll([out.outputPath, ...r[3].split('/')])).existsSync(),
          isTrue,
          reason: r[3],
        );
      }
    });
  });

  group('BUILD_GUIDE 5.10 timeline.csv audio positions', () {
    /// Two 10 s segments with a 10 s gap, a cut at 22 s to 25 s, and
    /// bookmarks at 27 s (in part 2), 23 s (in the cut) and 15 s (in the
    /// gap). Offsets count from the first segment, gaps included.
    Future<String> activityWithGap() async {
      final c = await t.conference();
      final start = DateTime.utc(2026, 11, 4, 9, 30);
      t.clock.set(start);
      final a = await t.activity(c.id, typeKey: 'keynote', title: 'Gaps');
      await segment(a, start, const Duration(seconds: 10));
      await segment(
        a,
        start.add(const Duration(seconds: 20)),
        const Duration(seconds: 10),
      );
      await t.cuts.add(a.id, startOffsetMs: 22000, endOffsetMs: 25000);
      for (final (s, label) in [
        (27, 'In part two'),
        (23, 'In removed part'),
        (15, 'In the gap'),
      ]) {
        await t.media.addBookmark(
          activityId: a.id,
          source: BookmarkSource.ui,
          atUtc: start.add(Duration(seconds: s)),
          label: label,
        );
      }
      return c.id;
    }

    Future<(Map<String, List<String>>, String)> timelineFor(
      String id,
      ExportAudioMode mode,
    ) async {
      final plan = await service.plan(
        ExportRequest(conferenceId: id, audioMode: mode),
      );
      String text(String path) => utf8.decode(
        (plan.entries.firstWhere((e) => e.relativePath == path).source
                as TextExportSource)
            .bytes,
      );
      final lines = text(timelineFileName).split('\r\n')..removeLast();
      expect(lines.first.split(',').skip(13), [
        'audio_file',
        'audio_position_seconds',
      ]);
      final rows = {
        for (final l in lines.skip(1))
          if (l.split(',') case final r when r[2] == 'bookmark') r[7]: r,
      };
      return (rows, text('$_gapsFolder/activity.md'));
    }

    test('BUILD_GUIDE 5.10 originals: audio_file and audio_position_seconds '
        'point inside the second file, and are empty in a gap', () async {
      final id = await activityWithGap();
      final (rows, md) = await timelineFor(id, ExportAudioMode.original);
      final two = rows['In part two']!;
      expect(two[6], '27.0');
      expect(two[13], '$_gapsFolder/audio/segment-002.m4a');
      expect(two[14], '7.0');
      // Cut audio is still in an original file.
      final removed = rows['In removed part']!;
      expect(removed[13], '$_gapsFolder/audio/segment-002.m4a');
      expect(removed[14], '3.0');
      final gap = rows['In the gap']!;
      expect(gap[6], '15.0');
      expect(gap[13], isEmpty);
      expect(gap[14], isEmpty);
      expect(
        md,
        contains('In part two [audio: `audio/segment-002.m4a` at 00:07]'),
      );
      expect(md, contains('In the gap\n'));
    });

    test('BUILD_GUIDE 5.10 trimmed copies: positions map through the kept '
        'ranges, and a moment in removed audio has no position', () async {
      final id = await activityWithGap();
      final (rows, md) = await timelineFor(id, ExportAudioMode.trimmed);
      final two = rows['In part two']!;
      expect(two[6], '27.0');
      expect(two[13], '$_gapsFolder/audio/segment-002-trimmed.m4a');
      // 2 s kept before the cut, then 2 s after it.
      expect(two[14], '4.0');
      final removed = rows['In removed part']!;
      expect(removed[6], '23.0');
      expect(removed[13], isEmpty);
      expect(removed[14], isEmpty);
      expect(rows['In the gap']![13], isEmpty);
      expect(
        md,
        contains(
          'In part two [audio: `audio/segment-002-trimmed.m4a` at 00:04]',
        ),
      );
      expect(md, contains('In removed part\n'));
    });

    test('BUILD_GUIDE 5.10 README and prompts say how to find a moment in '
        'the audio', () async {
      final id = await activityWithGap();
      final plan = await service.plan(ExportRequest(conferenceId: id));
      final readme = utf8.decode(
        (plan.entries.first.source as TextExportSource).bytes,
      );
      expect(
        readme,
        contains(
          'To hear a moment, open its `audio_file` and go to '
          '`audio_position_seconds`',
        ),
      );
      expect(readme, contains('so it is not a position in any one file'));
      expect(plan.analysisPrompt, contains('`audio_position_seconds`'));
      expect(plan.analysisPrompt, contains('not positions inside a file'));
    });
  });

  group('BUILD_GUIDE section 15 prompts', () {
    test('BUILD_GUIDE 15.1 analysis_prompt.md is filled with role, goals and '
        'outputs and is grounded', () async {
      final (id, _, _) = await conference();
      final out = await export(id);
      final prompt = read(out, analysisPromptFileName);
      expect(
        prompt,
        contains(
          'You are analysing a personal conference archive from Samlytics '
          'Conference 2026. The owner\'s role is Speaker (Head of data at '
          'Samlytics Data Services). Their key questions are:\n\n'
          '1. Learn how teams run a data mesh (priority 1)\n'
          '2. Find reusable data products\n\n'
          'They want these outputs: Briefing, LinkedIn post.',
        ),
      );
      expect(prompt, contains('Keep four things separate'));
      expect(prompt, contains('Do not invent quotations'));
      expect(prompt, contains('Bookmarked moments in `timeline.csv`'));
      expect(prompt, contains('Flag anything from private conversations'));
      // Grounding: cite files and timestamps, say when it is not there.
      expect(prompt, contains('Cite the file and timestamp'));
      expect(prompt, contains('not in the material'));
      expect(prompt, contains('Europe/London'));
      expect(prompt, contains('`$_keynoteFolder/`: "Data Mesh in Practice"'));
      expect(prompt, isNot(contains('{')));
      expect(prompt, isNot(contains('analyz')));
      // FR-EXP-08: what Copy AI prompt copies is the file as written.
      expect(out.analysisPrompt, prompt);
    });

    test(
      'BUILD_GUIDE 15.2 the four templates in prompts/ are filled in',
      () async {
        final (id, _, _) = await conference();
        final out = await export(id);
        final tasks = {
          'prompts/presentation_outline.md': '10 to 12 slide outline',
          'prompts/linkedin_post.md': '150 to 250 words',
          'prompts/blog_draft.md': '900 to 1,200 word blog post',
          'prompts/briefing_note.md': 'one-page briefing',
        };
        expect(promptTemplateFileNames, tasks.keys);
        for (final MapEntry(key: path, value: task) in tasks.entries) {
          final text = read(out, path);
          expect(text, contains(task), reason: path);
          expect(text, contains('Speaker (Head of data'), reason: path);
          expect(
            text,
            contains('Learn how teams run a data mesh'),
            reason: path,
          );
          expect(text, contains('Briefing, LinkedIn post'), reason: path);
          expect(text, contains('not in the material'), reason: path);
          expect(text, isNot(contains('{')), reason: path);
        }
      },
    );

    test(
      'BUILD_GUIDE 15.1 empty role, goals and outputs read naturally',
      () async {
        final c = await t.conference();
        final a = await t.activity(c.id, title: 'Talk');
        await segment(
          a,
          DateTime.utc(2026, 11, 4, 9),
          const Duration(minutes: 1),
        );
        final plan = await service.plan(ExportRequest(conferenceId: c.id));
        final prompt = plan.analysisPrompt!;
        expect(prompt, contains("The owner's role is not recorded."));
        expect(
          prompt,
          contains('None were recorded, so identify the main themes'),
        );
        expect(prompt, contains('They want these outputs: none were chosen'));
      },
    );
  });

  group('activity.md', () {
    test('BUILD_GUIDE 5.10 activity.md lists photos and bookmarks against '
        'mm:ss offsets', () async {
      final (id, _, _) = await conference();
      final out = await export(id);
      final md = read(out, '$_keynoteFolder/activity.md');
      expect(md, startsWith('# Data Mesh in Practice'));
      expect(md, contains('- Type: Keynote'));
      expect(md, contains('- Speakers: Samlytics Data Services speaker'));
      expect(md, contains('- 00:00 to 10:00: part 1, `audio/segment-001.m4a`'));
      expect(md, contains('- 12:00 to 17:00: part 2, `audio/segment-002.m4a`'));
      expect(md, contains('- 10:00 to 12:00: gap, nothing recorded.'));
      expect(md, contains('- 10:00 to 12:00: interruption (call)'));
      expect(md, contains('- 00:30 (2026-11-04 09:30): `photos/'));
      expect(md, contains('- 00:05 (2026-11-04 09:30): Key point'));
      expect(md, contains('See `notes.md`.'));
    });

    test('formatOffsetMmSs', () {
      expect(formatOffsetMmSs(0), '00:00');
      expect(formatOffsetMmSs(65999), '01:05');
      expect(formatOffsetMmSs(-5000), '-00:05');
      expect(formatOffsetMmSs(75 * 60000), '75:00');
    });
  });

  group('FR-EXP-10 privacy in generated files', () {
    test('FR-EXP-10 private activities, thoughts, reflections and contacts '
        'are in no generated file', () async {
      final (id, _, _) = await conference();
      final out = await export(id);
      final texts = generatedTexts(out);
      expect(
        texts.keys,
        containsAll([
          readmeFileName,
          manifestFileName,
          participantGoalsFileName,
          timelineFileName,
          analysisPromptFileName,
          ...promptTemplateFileNames,
          '$_keynoteFolder/activity.md',
        ]),
      );
      for (final MapEntry(key: path, value: text) in texts.entries) {
        for (final secret in [
          'Confidential supplier chat',
          'Supplier pricing',
          'Secret reflection',
          'My own view',
          privateThoughtLabel,
          'Hidden Contact Name',
          'hidden-contact@',
        ]) {
          expect(text, isNot(contains(secret)), reason: '$path: $secret');
        }
      }
      expect(out.analysisPrompt, isNot(contains('Confidential supplier chat')));
    });

    test('FR-EXP-10 with private items included, the prompts and README '
        'name the private activity as private', () async {
      final (id, _, _) = await conference();
      final out = await export(id, includePrivate: true);
      final texts = generatedTexts(out);
      expect(texts[timelineFileName], contains('Confidential supplier chat'));
      for (final path in [
        readmeFileName,
        analysisPromptFileName,
        ...promptTemplateFileNames,
      ]) {
        expect(
          texts[path],
          contains(
            'These activities are marked private: '
            '"Confidential supplier chat"',
          ),
          reason: path,
        );
      }
      expect(texts[analysisPromptFileName], contains('PRIVATE'));
      // Contacts stay out even then (ADR-040).
      for (final text in texts.values) {
        expect(text, isNot(contains('Hidden Contact Name')));
      }
    });
  });

  group('FR-EXP-01 FR-EXP-10 media-only exports hold no written text', () {
    const written = [
      'Key point',
      'Bookmark note text',
      'Whiteboard sketch caption',
      'Public note about domains',
      'Secret reflection',
      'My own view',
    ];

    test('FR-EXP-01 FR-EXP-10 everything export has the written text in the '
        'timeline', () async {
      final (id, _, _) = await conference();
      final timeline = read(await export(id), timelineFileName);
      expect(timeline, contains('Key point'));
      expect(timeline, contains('Bookmark note text'));
      expect(timeline, contains('Whiteboard sketch caption'));
    });

    for (final content in [ExportContent.audioOnly, ExportContent.photosOnly]) {
      test('FR-EXP-01 FR-EXP-10 a ${content.key} export has no bookmark, '
          'note or caption text in any generated file', () async {
        final (id, _, _) = await conference();
        final out = await export(id, content: content);
        final texts = generatedTexts(out);
        expect(
          texts.keys,
          containsAll([
            readmeFileName,
            manifestFileName,
            participantGoalsFileName,
            timelineFileName,
            analysisPromptFileName,
            ...promptTemplateFileNames,
          ]),
        );
        for (final MapEntry(key: path, value: text) in texts.entries) {
          for (final w in written) {
            expect(text, isNot(contains(w)), reason: '$path: $w');
          }
        }
        // Times and files stay: the bookmark row is there, without text.
        final rows = [
          for (final l in texts[timelineFileName]!.split('\r\n').skip(1))
            if (l.isNotEmpty) l.split(','),
        ];
        final bookmark = rows.singleWhere((r) => r[2] == 'bookmark');
        expect(bookmark[4], '2026-11-04T09:30:05.000Z');
        expect(bookmark[6], '5.0');
        expect(bookmark[7], isEmpty);
        expect(bookmark[12], isEmpty);
        expect(rows.where((r) => r[2] == 'notes'), isEmpty);
        final photo = rows.singleWhere((r) => r[2] == 'photo');
        expect(photo[7], isEmpty);
        expect(photo[12], isEmpty);
        expect(
          photo[3].isNotEmpty,
          content == ExportContent.photosOnly,
          reason: 'photo file only in a photos-only export',
        );
        // Goals and role are conference metadata and stay (ADR-046).
        expect(
          texts[analysisPromptFileName],
          contains('Learn how teams run a data mesh'),
        );
      });
    }
  });

  group('FR-EXP-06 checksums cover the generated files', () {
    test(
      'FR-EXP-06 checksums.sha256 lists and matches every new file',
      () async {
        final (id, _, _) = await conference();
        final out = await export(id);
        final sums = {
          for (final line in File(
            p.join(out.outputPath, checksumFileName),
          ).readAsLinesSync())
            line.substring(66): line.substring(0, 64),
        };
        for (final rel in [
          readmeFileName,
          manifestFileName,
          participantGoalsFileName,
          timelineFileName,
          analysisPromptFileName,
          ...promptTemplateFileNames,
          '$_keynoteFolder/activity.md',
        ]) {
          expect(sums.keys, contains(rel));
          final file = File(p.joinAll([out.outputPath, ...rel.split('/')]));
          expect(await hashFileSha256(file), sums[rel], reason: rel);
        }
      },
    );

    test('FR-EXP-06 FR-EXP-07 a ZIP holds the new files under safe paths and '
        'lists them in its checksums', () async {
      final (id, _, _) = await conference();
      final out = await export(id, format: ExportFormat.zip);
      expect(out.analysisPrompt, contains('Samlytics Conference 2026'));
      final input = InputFileStream(out.outputPath);
      addTearDown(input.close);
      final archive = ZipDecoder().decodeStream(input);
      const root = '2026-11-04_samlytics-conference-2026';
      final names = archive.files.map((f) => f.name).toSet();
      final sums = utf8.decode(
        archive.findFile('$root/$checksumFileName')!.content,
      );
      for (final rel in [
        readmeFileName,
        timelineFileName,
        analysisPromptFileName,
        ...promptTemplateFileNames,
        '$_keynoteFolder/activity.md',
      ]) {
        expect(names, contains('$root/$rel'));
        expect(sums, contains('  $rel\n'));
      }
    });
  });
}

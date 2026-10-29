/// The guide, manifest, timeline and AI prompts written into every export
/// (FR-EXP-08, FR-EXP-09, BUILD_GUIDE 5.10 and section 15, ADR-046)
/// [P1-22].
///
/// Everything here is built from the [ExportContext], which already leaves
/// out private activities, private thought bookmarks and private
/// reflections unless the user included private items (FR-EXP-10). Contact
/// names and details are never written (ADR-040).
library;

import 'dart:convert';

import '../../app/app_version.dart';
import '../../data/filesystem/folder_export.dart' show checksumFileName;
import '../models/conference.dart';
import '../models/enums.dart';
import '../models/media.dart';
import 'activity_title.dart';
import 'export_documents.dart';
import 'export_service.dart';
import 'review_timeline.dart';
import 'timeline_offset.dart';

const readmeFileName = 'README_START_HERE.md';
const manifestFileName = 'conference.json';
const participantGoalsFileName = 'participant_goals.md';
const timelineFileName = 'timeline.csv';
const analysisPromptFileName = 'analysis_prompt.md';
const activityMarkdownFileName = 'activity.md';

/// The extra templates (BUILD_GUIDE 15.2), relative to the export root.
const promptTemplateFileNames = [
  'prompts/presentation_outline.md',
  'prompts/linkedin_post.md',
  'prompts/blog_draft.md',
  'prompts/briefing_note.md',
];

/// Columns of `timeline.csv`: the build guide's ten, then the end of a
/// segment or interruption and a free-text note.
const timelineCsvHeader =
    'activity_id,activity_title,kind,file,utc_time,local_time,'
    'offset_seconds,label,profile,observed_bitrate_bps,'
    'end_utc_time,end_local_time,note';

/// Writes the full export package (ADR-046): `README_START_HERE.md`, the
/// full `conference.json`, `participant_goals.md`, `timeline.csv`,
/// `analysis_prompt.md`, the four templates in `prompts/`, and
/// `activity.md` in each activity folder.
class ExportPackageContributor extends ExportContributor {
  const ExportPackageContributor();

  @override
  List<ExportDocument> rootDocuments(ExportContext context) => [
    ExportDocument(readmeFileName, buildReadme(context)),
    ExportDocument(manifestFileName, buildManifestJson(context)),
    ExportDocument(participantGoalsFileName, buildParticipantGoals(context)),
    ExportDocument(timelineFileName, buildTimelineCsv(context)),
    ExportDocument(analysisPromptFileName, buildAnalysisPrompt(context)),
    for (final (path, text) in buildPromptTemplates(context))
      ExportDocument(path, text),
  ];

  @override
  List<ExportDocument> activityDocuments(
    ExportContext context,
    ExportedActivity activity,
  ) => [
    ExportDocument(
      activityMarkdownFileName,
      buildActivityMarkdown(context, activity),
    ),
  ];
}

// ---------------------------------------------------------------------------
// Shared wording

/// The owner's role in plain words, for prompts: "Speaker (Head of data)".
String describeRole(Conference conference) {
  final type = conference.roleType;
  final text = conference.roleText?.trim() ?? '';
  final label = type == null || type == RoleType.custom ? '' : type.label;
  if (label.isNotEmpty && text.isNotEmpty) return '$label ($text)';
  if (label.isNotEmpty) return label;
  if (text.isNotEmpty) return text;
  return 'not recorded';
}

String _goalLine(Goal g) => g.priority == null
    ? g.goalText.trim()
    : '${g.goalText.trim()} (priority ${g.priority})';

/// Goals as a numbered Markdown list, priority goals first.
String _goalsList(List<Goal> goals) {
  if (goals.isEmpty) {
    return 'None were recorded, so identify the main themes and what '
        'seems most useful to the owner instead.';
  }
  return [
    for (var i = 0; i < goals.length; i++) '${i + 1}. ${_goalLine(goals[i])}',
  ].join('\n');
}

String _outputsText(Conference conference) {
  final outputs = conference.requestedOutputs;
  if (outputs.isEmpty) {
    return 'none were chosen, so give a short summary of key takeaways and '
        'a follow-up list';
  }
  return outputs.map((o) => o.label).join(', ');
}

String _count(int n, String noun) => '$n $noun${n == 1 ? '' : 's'}';

String _two(int v) => v.toString().padLeft(2, '0');

String _isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${_two(d.month)}-${_two(d.day)}';

/// `2026-11-04 09:30` in the conference timezone.
String _localShort(DateTime utc, String timezone) {
  final t = toConferenceTime(utc, timezone);
  return '${_isoDate(t)} ${_two(t.hour)}:${_two(t.minute)}';
}

String _utcIso(DateTime? t) => t == null ? '' : t.toUtc().toIso8601String();

String _localIso(DateTime? t, String timezone) =>
    t == null ? '' : toConferenceTime(t, timezone).toIso8601String();

/// `mm:ss` from the first recording's start; minutes can pass 59.
String formatOffsetMmSs(int ms) {
  final negative = ms < 0;
  final seconds = ms.abs() ~/ 1000;
  return '${negative ? '-' : ''}${_two(seconds ~/ 60)}:${_two(seconds % 60)}';
}

String _dateRange(Conference c) {
  final start = c.startDate;
  final end = c.endDate;
  if (start == null) return 'dates not recorded';
  if (end == null || end == start) return _isoDate(start);
  return '${_isoDate(start)} to ${_isoDate(end)}';
}

/// When an activity started: its first segment, else actual or planned
/// start, else creation.
DateTime _activityStart(ExportedActivity a) {
  final first = _firstSegmentStart(a.segments);
  return first ??
      a.activity.actualStart ??
      a.activity.plannedStart ??
      a.activity.createdAt;
}

DateTime? _firstSegmentStart(List<RecordingSegment> segments) {
  DateTime? first;
  for (final s in segments) {
    if (first == null || s.startUtc.isBefore(first)) first = s.startUtc;
  }
  return first;
}

String _join(String folder, String? rel) =>
    rel == null ? '' : (folder.isEmpty ? rel : '$folder/$rel');

/// Plain-language privacy line for the README and prompts.
String _privacyLine(ExportContext context) {
  if (!context.request.includePrivate) {
    final parts = <String>[
      if (context.privateActivitiesExcluded > 0)
        '${context.privateActivitiesExcluded} private '
            '${context.privateActivitiesExcluded == 1 ? 'activity' : 'activities'}',
      if (context.privateNotesExcluded > 0)
        '${context.privateNotesExcluded} private '
            '${context.privateNotesExcluded == 1 ? 'thought or reflection' : 'thoughts or reflections'}',
    ];
    return parts.isEmpty
        ? 'Private items were not included in this export (there were none '
              'in what was chosen).'
        : 'Private items were left out of this export: ${parts.join(' and ')}.';
  }
  final private = [
    for (final a in context.activities)
      if (a.activity.isPrivate) a.activity.title,
  ];
  return private.isEmpty
      ? 'Private items were included in this export, so private thoughts and '
            'reflections may appear in the notes and bookmarks.'
      : 'Private items were included in this export. These activities are '
            'marked private: ${private.map((t) => '"$t"').join(', ')}. '
            'Private thoughts and reflections may also appear in the notes '
            'and bookmarks.';
}

// ---------------------------------------------------------------------------
// README_START_HERE.md (FR-EXP-09)

/// `README_START_HERE.md`: what the package is, what is inside, how to
/// unzip it, why a ZIP is not much smaller, how to use it with or without
/// an AI tool, and a privacy and consent note (FR-EXP-09, BUILD_GUIDE 5.10).
String buildReadme(ExportContext context) {
  final c = context.conference;
  final content = context.request.content;
  final activities = context.activities;
  final recordings = activities.fold<int>(
    0,
    (n, a) => n + a.files.segmentFiles.length,
  );
  final photos = activities.fold<int>(
    0,
    (n, a) => n + a.files.photoFiles.length,
  );
  final out = StringBuffer()
    ..writeln('# Start here: ${c.name}')
    ..writeln()
    ..writeln(
      'This folder is a personal conference archive exported from Attenlume '
      'on ${_localShort(context.exportedAtUtc, c.timezone)} '
      '(${c.timezone}). It holds '
      '${activities.length} ${activities.length == 1 ? 'activity' : 'activities'}, '
      '$recordings ${recordings == 1 ? 'recording' : 'recordings'} and '
      '$photos ${photos == 1 ? 'photo' : 'photos'}. Everything was made on '
      'your device; Attenlume did not upload anything.',
    )
    ..writeln()
    ..writeln('## What is inside')
    ..writeln()
    ..writeln('- `$readmeFileName`: this guide.')
    ..writeln(
      '- `$manifestFileName`: the conference, your role, goals and requested '
      'outputs, what this export holds and what was left out, for software '
      'and AI tools.',
    )
    ..writeln(
      '- `$participantGoalsFileName`: your role and goals in plain English.',
    )
    ..writeln(
      '- `$timelineFileName`: every recording, photo, bookmark, '
      'interruption and set of notes in time order, with times in the '
      'conference timezone and in UTC. Opens in any spreadsheet.',
    )
    ..writeln(
      '- `$analysisPromptFileName`: a ready-made prompt for an AI tool, '
      'filled in with your role, goals and outputs.',
    )
    ..writeln(
      '- `prompts/`: more prompts for a presentation outline, a LinkedIn '
      'post, a blog draft and a briefing note.',
    )
    ..writeln(
      '- `activities/`: one folder per activity, numbered in conference '
      'order with the start time, for example `001_0930_keynote_...`. Each '
      'can hold:',
    );
  if (content.text) {
    out
      ..writeln(
        '  - `activity.md`: the activity in readable form, with bookmarks '
        'and photos against `mm:ss` offsets from the start of the first '
        'recording.',
      )
      ..writeln(
        '  - `activity.json`: the same details for software, including '
        'recording quality.',
      )
      ..writeln('  - `notes.md`: your notes and follow-up.')
      ..writeln('  - `bookmarks.csv`: the moments you marked.');
  }
  if (content.audio) {
    out.writeln(
      '  - `audio/`: the recordings (`.m4a`, AAC audio). A long session can '
      'be in several parts, `segment-001`, `segment-002` and so on.',
    );
    if (context.request.effectiveAudioMode ==
        ExportAudioMode.originalWithCuts) {
      out.writeln(
        '  - `cuts.json`: the parts of each recording you marked to skip.',
      );
    }
  }
  if (content.photos) {
    out.writeln(
      '  - `photos/`: the photos, named by the UTC time they were taken.',
    );
  }
  out
    ..writeln(
      '- `$checksumFileName`: a SHA-256 checksum for every other file, so '
      'you can check nothing was damaged in copying.',
    )
    ..writeln()
    ..writeln('## How to unzip')
    ..writeln()
    ..writeln('If you received this as a ZIP file, extract it before use:')
    ..writeln()
    ..writeln(
      '- Windows: right-click the ZIP and choose Extract All. Extract it '
      'close to the top of a drive, for example `C:\\Exports`, because '
      'Windows limits how long a file path can be.',
    )
    ..writeln('- macOS: double-click the ZIP.')
    ..writeln('- Android: open the Files app, tap the ZIP and choose Extract.')
    ..writeln('- iPhone and iPad: open the Files app and tap the ZIP.')
    ..writeln('- Linux: `unzip <file>.zip`.')
    ..writeln()
    ..writeln(
      'Audio and photos are already compressed, so ZIP rarely makes them '
      'smaller: the ZIP is about the same size as the folder. It keeps the '
      'files together; it does not save space.',
    )
    ..writeln()
    ..writeln('## Using it with an AI tool')
    ..writeln()
    ..writeln(
      '1. Open `$analysisPromptFileName` (in Attenlume you can also use Copy '
      'AI prompt after exporting) and paste it into the AI tool.',
    )
    ..writeln(
      content.text
          ? '2. Add the files it should read. Start with the text files: '
                '`$timelineFileName`, `$participantGoalsFileName` and, for '
                'each activity, `activity.md` and `notes.md`. Then add photos '
                'and audio for the activities that matter most.'
          : '2. Add the files it should read. Start with '
                '`$timelineFileName` and `$participantGoalsFileName`, then '
                'the files for the activities that matter most.',
    )
    ..writeln(
      '3. Ask it to cite file names and timestamps, and check its claims '
      'against your recordings before you share anything.',
    )
    ..writeln()
    ..writeln(
      'AI tools differ in which file types and sizes they accept, and they '
      'change these limits often, so check the tool\'s own help pages. If '
      'a tool refuses a file or a ZIP, upload the files inside it instead, '
      'one activity at a time, or start with the text files only. Some '
      'tools cannot listen to audio; give them your notes or a transcript '
      'instead.',
    )
    ..writeln()
    ..writeln('## Using it without AI')
    ..writeln()
    ..writeln(
      '${content.text ? "Open each activity's `activity.md` for an overview, then " : 'Open '}'
      '`$timelineFileName` in a spreadsheet to find your bookmarked '
      'moments. The `offset_seconds` column is how far into the activity\'s '
      'recording each moment is, so you can jump straight to it in any '
      'audio player.',
    )
    ..writeln()
    ..writeln('## Checking the files')
    ..writeln()
    ..writeln(
      '`$checksumFileName` lists each file with its SHA-256 checksum. On '
      'macOS or Linux run `shasum -a 256 -c $checksumFileName` in this '
      'folder. On Windows, `Get-FileHash <file>` in PowerShell shows a '
      'file\'s checksum to compare.',
    )
    ..writeln()
    ..writeln('## Privacy and consent')
    ..writeln()
    ..writeln(
      'This archive can hold other people\'s voices and faces, your own '
      'reflections, and unpublished or confidential material. Before you '
      'share it or upload any of it to an AI service or the cloud, check '
      'you have permission from the people recorded and from the event, '
      'and that the service\'s terms suit the material. Anything you upload '
      'leaves your device.',
    )
    ..writeln()
    ..writeln(_privacyLine(context))
    ..writeln()
    ..writeln(
      'Contact names and contact details are never included in exports.',
    );
  return out.toString();
}

// ---------------------------------------------------------------------------
// conference.json, full manifest (BUILD_GUIDE 5.10)

const _json = JsonEncoder.withIndent('  ');

/// The full `conference.json` (BUILD_GUIDE 5.10): schema version,
/// conference id, title, dates, timezone, role, goals, requested outputs,
/// activity ids, privacy flags, app version and export time, plus the
/// package's files and each activity's folder and files. Keeps every key
/// of the P1-21 form.
String buildManifestJson(ExportContext context) {
  final c = context.conference;
  String? date(DateTime? d) => d == null ? null : _isoDate(d);
  final tz = c.timezone;
  final map = <String, Object?>{
    'schema_version': exportSchemaVersion,
    'app': {'name': 'Attenlume', 'version': appVersion},
    'id': c.id,
    'name': c.name,
    'title': c.name,
    'venue': c.venue,
    'start_date': date(c.startDate),
    'end_date': date(c.endDate),
    'timezone': tz,
    'role_type': c.roleType?.key,
    'role_text': c.roleText,
    'role': describeRole(c),
    'goals': [
      for (final g in context.goals)
        {'text': g.goalText, 'priority': g.priority},
    ],
    'requested_outputs': [for (final o in c.requestedOutputs) o.key],
    'exported_at_utc': context.exportedAtUtc.toUtc().toIso8601String(),
    'exported_at_local': _localIso(context.exportedAtUtc, tz),
    'scope': context.request.toScopeJson(),
    'privacy': {
      'private_activities_excluded': context.privateActivitiesExcluded,
      'private_notes_excluded': context.privateNotesExcluded,
    },
    'files': {
      'readme': readmeFileName,
      'participant_goals': participantGoalsFileName,
      'timeline': timelineFileName,
      'analysis_prompt': analysisPromptFileName,
      'prompts': promptTemplateFileNames,
      'checksums': checksumFileName,
    },
    'activity_ids': [for (final a in context.activities) a.activity.id],
    'activities': [
      for (final a in context.activities)
        {
          'id': a.activity.id,
          'title': a.activity.title,
          'folder': a.folder,
          'type': a.type.key,
          'type_label': a.type.label,
          'is_private': a.activity.isPrivate,
          'start_utc': _utcIso(_activityStart(a)),
          'start_local': _localIso(_activityStart(a), tz),
          'segment_count': a.segments.length,
          'segments_exported': a.files.segmentFiles.length,
          'photo_count': a.photos.length,
          'photos_exported': a.files.photoFiles.length,
          'bookmark_count': a.bookmarks.length,
          'interruption_count': a.interruptions.length,
          'files': {
            if (context.request.content.text)
              'activity_md': activityMarkdownFileName,
            'activity_json': ?a.activityJsonFile,
            'notes': ?a.notesFile,
            'bookmarks': ?a.bookmarksFile,
            'cuts': ?a.cutsFile,
          },
        },
    ],
  };
  return '${_json.convert(map)}\n';
}

// ---------------------------------------------------------------------------
// participant_goals.md

/// `participant_goals.md`: role, goals and wanted outputs in plain English.
String buildParticipantGoals(ExportContext context) {
  final c = context.conference;
  final priority = [
    for (final g in context.goals)
      if (g.priority != null) g,
  ];
  final other = [
    for (final g in context.goals)
      if (g.priority == null) g,
  ];
  final out = StringBuffer()
    ..writeln('# Participant goals: ${c.name}')
    ..writeln()
    ..writeln('**Role:** ${describeRole(c)}')
    ..writeln();
  if (context.goals.isEmpty) {
    out
      ..writeln('No goals were recorded for this conference.')
      ..writeln();
  }
  if (priority.isNotEmpty) {
    out
      ..writeln('## Priority goals')
      ..writeln();
    for (var i = 0; i < priority.length; i++) {
      out.writeln('${i + 1}. ${priority[i].goalText.trim()}');
    }
    out.writeln();
  }
  if (other.isNotEmpty) {
    out
      ..writeln('## Other goals')
      ..writeln();
    for (final g in other) {
      out.writeln('- ${g.goalText.trim()}');
    }
    out.writeln();
  }
  out
    ..writeln('## Outputs wanted')
    ..writeln();
  if (c.requestedOutputs.isEmpty) {
    out.writeln('None chosen.');
  } else {
    for (final o in c.requestedOutputs) {
      out.writeln('- ${o.label}');
    }
  }
  return out.toString();
}

// ---------------------------------------------------------------------------
// timeline.csv

class _Row {
  _Row({
    required this.order,
    required this.at,
    required this.kindRank,
    required this.fields,
  });

  final int order;
  final DateTime at;
  final int kindRank;
  final List<String> fields;
}

/// `timeline.csv` (BUILD_GUIDE 5.10): one row per segment, photo,
/// bookmark, interruption and notes file of every exported activity, in
/// time order. `local_time` is in the conference timezone; offsets follow
/// the 9.4 rule (seconds from the activity's first segment, negative
/// before it). RFC 4180 quoting, formula-safe text, CRLF line ends.
/// Without notes and details in the export, user-written text (bookmark
/// labels and notes, photo labels and captions) is left out.
String buildTimelineCsv(ExportContext context) {
  final tz = context.conference.timezone;
  // Audio-only and photos-only exports hold no user-written text: rows keep
  // their times, offsets and files, but bookmark labels and notes and photo
  // labels and captions stay out (FR-EXP-01, FR-EXP-10, ADR-046).
  final withText = context.request.content.text;
  final rows = <_Row>[];
  String offset(int? ms) => ms == null ? '' : (ms / 1000).toStringAsFixed(1);

  for (var i = 0; i < context.activities.length; i++) {
    final a = context.activities[i];
    final first = _firstSegmentStart(a.segments);
    int? offsetOf(DateTime t) =>
        timelineOffsetMs(eventUtc: t, firstSegmentStartUtc: first);

    void add(
      DateTime at,
      int rank, {
      required String kind,
      String file = '',
      int? offsetMs,
      String? label,
      String profile = '',
      int? bitrate,
      DateTime? end,
      String? note,
    }) {
      rows.add(
        _Row(
          order: i,
          at: at,
          kindRank: rank,
          fields: [
            a.activity.id,
            csvField(a.activity.title),
            kind,
            csvField(file),
            _utcIso(at),
            _localIso(at, tz),
            offset(offsetMs),
            csvField(label),
            profile,
            bitrate?.toString() ?? '',
            _utcIso(end),
            _localIso(end, tz),
            csvField(note),
          ],
        ),
      );
    }

    if (a.notesFile != null) {
      add(
        _activityStart(a),
        0,
        kind: 'notes',
        file: _join(a.folder, a.notesFile),
        label: 'Notes',
      );
    }
    for (final s in a.segments) {
      final keep = a.files.trimmedKeepRanges[s.id];
      add(
        s.startUtc,
        1,
        kind: 'segment',
        file: _join(a.folder, a.files.segmentFiles[s.id]),
        offsetMs: offsetOf(s.startUtc),
        label: 'Recording part ${s.sequence}',
        profile: s.requestedProfile.key,
        bitrate: s.observedBitrateBps,
        end: s.endUtc,
        note:
            a.files.segmentNotes[s.id] ??
            (keep == null ? null : 'trimmed copy'),
      );
    }
    for (final gap in a.interruptions) {
      add(
        gap.startUtc,
        2,
        kind: 'interruption',
        offsetMs: offsetOf(gap.startUtc),
        label: gap.reason.key,
        end: gap.endUtc,
        note: gap.autoResumed ? 'resumed automatically' : null,
      );
    }
    for (final ph in a.photos) {
      add(
        ph.takenUtc,
        3,
        kind: 'photo',
        file: _join(a.folder, a.files.photoFiles[ph.id]),
        offsetMs: ph.offsetMs ?? offsetOf(ph.takenUtc),
        label: withText ? ph.label : null,
        note: withText ? ph.caption : null,
      );
    }
    for (final b in a.bookmarks) {
      add(
        b.atUtc,
        4,
        kind: 'bookmark',
        offsetMs: b.offsetMs ?? offsetOf(b.atUtc),
        label: withText ? b.label : null,
        note: withText ? b.note : null,
      );
    }
  }

  rows.sort((x, y) {
    final byTime = x.at.compareTo(y.at);
    if (byTime != 0) return byTime;
    final byActivity = x.order.compareTo(y.order);
    if (byActivity != 0) return byActivity;
    return x.kindRank.compareTo(y.kindRank);
  });
  final out = StringBuffer('$timelineCsvHeader\r\n');
  for (final r in rows) {
    out
      ..write(r.fields.join(','))
      ..write('\r\n');
  }
  return out.toString();
}

// ---------------------------------------------------------------------------
// analysis_prompt.md and prompts/ (BUILD_GUIDE section 15)

String _groundRules(ExportContext context) {
  final tz = context.conference.timezone;
  return [
    '## Ground rules',
    '',
    '- Use only the material in this archive and anything the owner gives '
        'you. If something is not in the material, say "not in the '
        'material" rather than guessing.',
    '- Cite the file and timestamp for every key point, for example '
        '`activities/001_0930_.../audio/segment-001.m4a at 12:34`, or the '
        'matching row of `$timelineFileName`.',
    '- Offsets (`mm:ss` in `activity.md`, `offset_seconds` in '
        '`$timelineFileName`) count from the start of each activity\'s first '
        'recording. Wall-clock times are in the conference timezone, $tz.',
    '- If you cannot open or transcribe a file, name it and ask for an '
        'accessible version, such as the notes or a transcript.',
    '- Do not invent quotations, speakers, outcomes or statistics.',
    '- ${_privacyLine(context)} Flag anything that came from a private '
        'conversation before suggesting it is used publicly.',
  ].join('\n');
}

String _contents(ExportContext context) {
  final c = context.conference;
  final tz = c.timezone;
  final out = StringBuffer()
    ..writeln('## What is in this archive')
    ..writeln()
    ..writeln(
      '- Conference: ${c.name}, ${_dateRange(c)}'
      '${c.venue?.trim().isNotEmpty ?? false ? ', ${c.venue!.trim()}' : ''}. '
      'Timezone: $tz.',
    )
    ..writeln(
      '- `$timelineFileName`: every recording, photo, bookmark and '
      'interruption in time order. Bookmarks are moments the owner marked '
      'as important.',
    )
    ..writeln('- `$participantGoalsFileName`: the owner\'s role and goals.');
  if (context.request.content.text) {
    out.writeln(
      '- In each activity folder: `activity.md` (overview with offsets), '
      '`notes.md` (the owner\'s notes and reflections) and '
      '`bookmarks.csv`.',
    );
  }
  out
    ..writeln()
    ..writeln('Activities:')
    ..writeln();
  if (context.activities.isEmpty) out.writeln('- None.');
  for (final a in context.activities) {
    final act = a.activity;
    final details = <String>[
      a.type.label,
      'starts ${_localShort(_activityStart(a), tz)}',
      if (act.speakerNames.isNotEmpty)
        'speakers: ${act.speakerNames.join(', ')}',
      if (act.organisation?.trim().isNotEmpty ?? false)
        'organisation: ${act.organisation!.trim()}',
      _count(a.files.segmentFiles.length, 'recording file'),
      _count(a.files.photoFiles.length, 'photo'),
      _count(a.bookmarks.length, 'bookmark'),
      if (a.notesFile != null) 'notes',
      if (act.isPrivate) 'PRIVATE',
    ];
    out.writeln('- `${a.folder}/`: "${act.title}" (${details.join(', ')}).');
  }
  return out.toString().trimRight();
}

String _intro(ExportContext context) {
  final c = context.conference;
  return 'You are analysing a personal conference archive from ${c.name}. '
      'The owner\'s role is ${describeRole(c)}. Their key questions are:\n\n'
      '${_goalsList(context.goals)}\n\n'
      'They want these outputs: ${_outputsText(c)}.';
}

/// `analysis_prompt.md` (BUILD_GUIDE 15.1), filled in with the
/// conference's role, goals and outputs, plus grounding rules and a list
/// of what the archive holds. Also what "Copy AI prompt" copies
/// (FR-EXP-08).
String buildAnalysisPrompt(ExportContext context) {
  final c = context.conference;
  return [
    '# Analysis prompt: ${c.name}',
    '',
    _intro(context),
    '',
    'Organise the evidence by activity and timestamp. Use the session '
        'notes, recordings or transcripts, photographs and the owner\'s '
        'reflections that you can actually open. If a file cannot be opened '
        'or transcribed, say which one and ask for an accessible version.',
    '',
    'Keep four things separate: (a) what a speaker demonstrably said, (b) '
        'the owner\'s own observations, (c) your inferences, (d) suggested '
        'next steps. Do not invent quotations, speakers, outcomes or '
        'statistics. Link every key takeaway to a filename and timestamp '
        'where available. Bookmarked moments in `$timelineFileName` were '
        'marked as important by the owner, so give them extra attention.',
    '',
    'For each activity, summarise the key points as they relate to the '
        'owner\'s goals. Then give overall takeaways, open questions and '
        'follow-up opportunities. Flag anything from private conversations '
        'before suggesting it is used publicly.',
    '',
    _groundRules(context),
    '',
    _contents(context),
    '',
  ].join('\n');
}

/// The four templates in `prompts/` (BUILD_GUIDE 15.2), each filled in
/// with the role, goals and outputs, as (path, text).
List<(String, String)> buildPromptTemplates(ExportContext context) {
  final c = context.conference;
  final role = describeRole(c);
  String template(String title, String task) => [
    '# $title: ${c.name}',
    '',
    _intro(context),
    '',
    '## Task',
    '',
    task,
    '',
    _groundRules(context),
    '',
    _contents(context),
    '',
  ].join('\n');

  return [
    (
      promptTemplateFileNames[0],
      template(
        'Presentation outline',
        'Build a 10 to 12 slide outline for the owner\'s audience (the '
            'owner\'s role is $role). One idea per slide. For each slide give '
            'the supporting evidence references (file and timestamp) and, '
            'where relevant, a suggested photo from the archive by its file '
            'name in `photos/`.',
      ),
    ),
    (
      promptTemplateFileNames[1],
      template(
        'LinkedIn post',
        'Draft a LinkedIn post of 150 to 250 words in the owner\'s voice, '
            'built around two or three takeaways tied to the goals above. No '
            'invented claims, no confidential content and nothing from '
            'private conversations. After the draft, list the files and '
            'timestamps each takeaway rests on.',
      ),
    ),
    (
      promptTemplateFileNames[2],
      template(
        'Blog draft',
        'Draft a 900 to 1,200 word blog post with a clear argument and '
            'sections linked to activities. End with a sources list of the '
            'activity titles and speakers used, and cite files and '
            'timestamps for each claim.',
      ),
    ),
    (
      promptTemplateFileNames[3],
      template(
        'Briefing note',
        'Write a one-page briefing for the owner\'s colleagues: context, key '
            'findings, implications for the organisation and recommended '
            'actions. Cite files and timestamps for each finding.',
      ),
    ),
  ];
}

// ---------------------------------------------------------------------------
// activity.md

/// `activity.md` (BUILD_GUIDE 5.10): the activity in readable form, with
/// recordings, gaps, interruptions, photos, bookmarks and cuts against
/// `mm:ss` offsets from the first recording's start.
String buildActivityMarkdown(ExportContext context, ExportedActivity item) {
  final tz = context.conference.timezone;
  final a = item.activity;
  final timeline = ReviewTimeline.build(segments: item.segments);
  final first = _firstSegmentStart(item.segments);
  int? offsetOf(DateTime t) =>
      timelineOffsetMs(eventUtc: t, firstSegmentStartUtc: first);
  String at(int? ms) => ms == null ? '--:--' : formatOffsetMmSs(ms);

  final out = StringBuffer()
    ..writeln('# ${a.title}')
    ..writeln()
    ..writeln('- Type: ${item.type.label}');
  if (a.speakerNames.isNotEmpty) {
    out.writeln('- Speakers: ${a.speakerNames.join(', ')}');
  }
  if (a.organisation?.trim().isNotEmpty ?? false) {
    out.writeln('- Organisation: ${a.organisation!.trim()}');
  }
  if (a.room?.trim().isNotEmpty ?? false) {
    out.writeln('- Room: ${a.room!.trim()}');
  }
  final start = _activityStart(item);
  out.writeln(
    '- Started: ${_localShort(start, tz)} ($tz), ${_utcIso(start)} UTC',
  );
  if (a.actualEnd case final end?) {
    out.writeln('- Ended: ${_localShort(end, tz)} ($tz), ${_utcIso(end)} UTC');
  }
  if (a.tags.isNotEmpty) out.writeln('- Tags: ${a.tags.join(', ')}');
  out.writeln('- Recording permission: ${a.recordingPermissionStatus.key}');
  if (a.isPrivate) {
    out.writeln(
      '- Private: yes. Do not use anything from this activity publicly '
      'without the owner\'s agreement.',
    );
  }
  out
    ..writeln()
    ..writeln(
      'Offsets (`mm:ss`) count from the start of the first recording. '
      'Times are in $tz.',
    );

  out
    ..writeln()
    ..writeln('## Recordings')
    ..writeln();
  if (timeline.segments.isEmpty) out.writeln('None.');
  for (final ts in timeline.segments) {
    final s = ts.segment;
    final file = item.files.segmentFiles[s.id];
    final why = item.files.segmentNotes[s.id];
    final keep = item.files.trimmedKeepRanges[s.id];
    out.writeln(
      '- ${at(ts.startMs)} to ${at(ts.endMs)}: part ${s.sequence}, '
      '${file == null ? 'not in this export${why == null ? '' : ' ($why)'}' : '`$file`'}'
      '${keep == null ? '' : ', trimmed copy'}, '
      'started ${_localShort(s.startUtc, tz)}, ${s.requestedProfile.key} profile.',
    );
  }

  final gaps = timeline.gaps;
  if (gaps.isNotEmpty || item.interruptions.isNotEmpty) {
    out
      ..writeln()
      ..writeln('## Gaps and interruptions')
      ..writeln();
    for (final g in gaps) {
      out.writeln(
        '- ${at(g.startMs)} to ${at(g.endMs)}: gap, nothing recorded.',
      );
    }
    for (final i in item.interruptions) {
      final end = i.endUtc == null ? null : offsetOf(i.endUtc!);
      out.writeln(
        '- ${at(offsetOf(i.startUtc))}'
        '${end == null ? '' : ' to ${at(end)}'}: interruption '
        '(${i.reason.key}), ${i.autoResumed ? 'resumed automatically' : 'resumed or stopped by the owner'}.',
      );
    }
  }

  if (item.photos.isNotEmpty) {
    out
      ..writeln()
      ..writeln('## Photos')
      ..writeln();
    for (final ph in item.photos) {
      final file = item.files.photoFiles[ph.id];
      final words = [
        if (ph.label?.trim().isNotEmpty ?? false) ph.label!.trim(),
        if (ph.caption?.trim().isNotEmpty ?? false) ph.caption!.trim(),
      ].join(': ');
      out.writeln(
        '- ${at(ph.offsetMs ?? offsetOf(ph.takenUtc))} '
        '(${_localShort(ph.takenUtc, tz)}): '
        '${file == null ? 'not in this export' : '`$file`'}'
        '${words.isEmpty ? '' : ', $words'}',
      );
    }
  }

  if (item.bookmarks.isNotEmpty) {
    out
      ..writeln()
      ..writeln('## Bookmarks')
      ..writeln();
    for (final b in item.bookmarks) {
      final words = [
        if (b.label?.trim().isNotEmpty ?? false) b.label!.trim(),
        if (b.note?.trim().isNotEmpty ?? false) b.note!.trim(),
      ].join(': ');
      out.writeln(
        '- ${at(b.offsetMs ?? offsetOf(b.atUtc))} '
        '(${_localShort(b.atUtc, tz)})'
        '${words.isEmpty ? '' : ': $words'}',
      );
    }
  }

  if (item.cuts.isNotEmpty) {
    out
      ..writeln()
      ..writeln('## Parts marked to skip')
      ..writeln();
    for (final cut in item.cuts) {
      out.writeln(
        '- ${at(cut.startOffsetMs)} to ${at(cut.endOffsetMs)}'
        '${cut.reason?.trim().isNotEmpty ?? false ? ': ${cut.reason!.trim()}' : ''}',
      );
    }
  }

  out
    ..writeln()
    ..writeln('## Notes')
    ..writeln()
    ..writeln(
      item.notesFile == null
          ? 'No notes were written for this activity.'
          : 'See `${item.notesFile}`.',
    );
  return out.toString();
}

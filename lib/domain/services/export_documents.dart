/// Basic per-activity and conference documents written into an export
/// (FR-EXP-01, ADR-040) [P1-21]. The full manifest, `activity.md`,
/// `timeline.csv`, README and prompts are in `export_package.dart` (P1-22,
/// ADR-046) and plug in through `ExportContributor`.
library;

import 'dart:convert';

import '../../data/filesystem/folder_export.dart';
import '../models/activity.dart';
import '../models/conference.dart';
import '../models/media.dart';
import 'activity_title.dart';
import 'cut_range_math.dart';
import 'private_notes.dart';

/// Version of the JSON in an export. 2 since P1-22 added the full
/// `conference.json` manifest (ADR-046); `activity.json` is unchanged.
const exportSchemaVersion = 2;

const _json = JsonEncoder.withIndent('  ');

bool isPrivateThought(Bookmark b) => b.label == privateThoughtLabel;

String _utc(DateTime? t) => t == null ? '' : t.toUtc().toIso8601String();

String _local(DateTime? t, String timezone) =>
    t == null ? '' : toConferenceTime(t, timezone).toIso8601String();

/// `notes.md`: the notes as written plus the follow-up text.
String buildNotesMarkdown(Activity activity, {required String notes}) {
  final out = StringBuffer('# ${activity.title}\n\n');
  if (notes.trim().isNotEmpty) out.write('${notes.trim()}\n');
  final followUp = activity.followUpText?.trim() ?? '';
  if (followUp.isNotEmpty) {
    out.write('\n## Follow-up\n\n$followUp\n');
  }
  return out.toString();
}

/// `bookmarks.csv`: one row per bookmark, RFC 4180 quoting.
String buildBookmarksCsv(List<Bookmark> bookmarks, String timezone) {
  final out = StringBuffer(
    'offset_seconds,utc_time,local_time,label,note,source\r\n',
  );
  for (final b in bookmarks) {
    out
      ..write(b.offsetMs == null ? '' : (b.offsetMs! / 1000).toStringAsFixed(1))
      ..write(',')
      ..write(_utc(b.atUtc))
      ..write(',')
      ..write(_local(b.atUtc, timezone))
      ..write(',')
      ..write(csvField(b.label))
      ..write(',')
      ..write(csvField(b.note))
      ..write(',')
      ..write(b.source.key)
      ..write('\r\n');
  }
  return out.toString();
}

/// One CSV field, quoted when it holds a comma, quote or line break. A
/// leading `=`, `+`, `-` or `@` is prefixed with `'` so spreadsheets do
/// not run it as a formula.
String csvField(String? value) {
  var v = value ?? '';
  if (v.isNotEmpty && '=+-@'.contains(v[0])) v = "'$v";
  if (v.contains(RegExp('[",\r\n]'))) {
    return '"${v.replaceAll('"', '""')}"';
  }
  return v;
}

/// Where each of an activity's segments and photos went in the export.
class ActivityExportFiles {
  const ActivityExportFiles({
    this.folder = '',
    this.segmentFiles = const {},
    this.segmentNotes = const {},
    this.photoFiles = const {},
    this.trimmedKeepRanges = const {},
  });

  /// The activity folder, relative to the export root.
  final String folder;

  /// Segment id to its path in the activity folder.
  final Map<String, String> segmentFiles;

  /// Segment id to why it has no file (damaged, still recording, missing,
  /// cut out, or the same file as another segment).
  final Map<String, String> segmentNotes;

  /// Photo id to its path in the activity folder.
  final Map<String, String> photoFiles;

  /// Segment id to the ranges (ms from the segment start) its trimmed
  /// copy keeps. Only segments exported as trimmed copies.
  final Map<String, List<TimeRange>> trimmedKeepRanges;
}

/// `activity.json`: the activity's details, segments with their quality
/// fields, photos, bookmarks, cut ranges and interruptions (BUILD_GUIDE
/// section 10 file contents, basic form). Contact name and details are
/// left out (ADR-040).
///
/// [written] holds the files already written, by path from the export
/// root. For an exported segment `bytes` and `sha256` come from the file
/// actually written, so they match `checksums.sha256`; a trimmed copy
/// also gets its own `duration_ms`, with the recording's values under
/// `source_*` (FR-EXP-03, FR-EXP-06).
String buildActivityJson({
  required Activity activity,
  required ActivityType type,
  required String timezone,
  required String audioMode,
  required List<RecordingSegment> segments,
  required List<Photo> photos,
  required List<Bookmark> bookmarks,
  required List<CutRange> cuts,
  required List<Interruption> interruptions,
  required ActivityExportFiles files,
  Map<String, ExportedFile> written = const {},
}) {
  ExportedFile? outputOf(String segmentId) {
    final rel = files.segmentFiles[segmentId];
    if (rel == null) return null;
    return written[files.folder.isEmpty ? rel : '${files.folder}/$rel'];
  }

  final map = <String, Object?>{
    'schema_version': exportSchemaVersion,
    'id': activity.id,
    'type': type.key,
    'type_label': type.label,
    'title': activity.title,
    'speakers': activity.speakerNames,
    'organisation': activity.organisation,
    'room': activity.room,
    'tags': activity.tags,
    'status': activity.status.key,
    'recording_permission_status': activity.recordingPermissionStatus.key,
    'is_private': activity.isPrivate,
    'timezone': timezone,
    'planned_start_utc': activity.plannedStart?.toUtc().toIso8601String(),
    'actual_start_utc': activity.actualStart?.toUtc().toIso8601String(),
    'actual_end_utc': activity.actualEnd?.toUtc().toIso8601String(),
    'actual_start_local': activity.actualStart == null
        ? null
        : _local(activity.actualStart, timezone),
    'audio_mode': audioMode,
    'segments': [
      for (final s in segments)
        if ((outputOf(s.id), files.trimmedKeepRanges[s.id]) case (
          final out,
          final keep,
        ))
          {
            'id': s.id,
            'sequence': s.sequence,
            'file': files.segmentFiles[s.id],
            if (files.segmentNotes[s.id] != null)
              'not_exported_reason': files.segmentNotes[s.id],
            'trimmed': keep != null,
            'state': s.state.key,
            'start_utc': _utc(s.startUtc),
            'end_utc': s.endUtc == null ? null : _utc(s.endUtc),
            'duration_ms': keep == null
                ? s.durationMs
                : out?.durationMs ??
                      keep.fold<int>(0, (n, r) => n + r.durationMs),
            'bytes': out?.bytes ?? (keep == null ? s.bytes : null),
            'sha256': out?.sha256 ?? (keep == null ? s.sha256 : null),
            if (keep != null) ...{
              'kept_ranges_ms': [
                for (final r in keep) [r.startMs, r.endMs],
              ],
              'source_duration_ms': s.durationMs,
              'source_bytes': s.bytes,
              'source_sha256': s.sha256,
            },
            'codec': s.codec,
            'container': s.container,
            'channel_count': s.channelCount,
            'sample_rate_hz': s.sampleRateHz,
            'profile': s.requestedProfile.key,
            'requested_bitrate_bps': s.requestedBitrateBps,
            'observed_bitrate_bps': s.observedBitrateBps,
            'input_route': s.inputRoute,
            'end_reason': s.endReason?.key,
          },
    ],
    'photos': [
      for (final ph in photos)
        {
          'id': ph.id,
          'file': files.photoFiles[ph.id],
          'taken_utc': _utc(ph.takenUtc),
          'offset_ms': ph.offsetMs,
          'caption': ph.caption,
          'label': ph.label,
          'source': ph.source.key,
          'width': ph.width,
          'height': ph.height,
        },
    ],
    'bookmarks': [
      for (final b in bookmarks)
        {
          'id': b.id,
          'at_utc': _utc(b.atUtc),
          'offset_ms': b.offsetMs,
          'label': b.label,
          'note': b.note,
          'source': b.source.key,
        },
    ],
    'cut_ranges': [
      for (final c in cuts)
        {
          'start_offset_ms': c.startOffsetMs,
          'end_offset_ms': c.endOffsetMs,
          'reason': c.reason,
        },
    ],
    'interruptions': [
      for (final i in interruptions)
        {
          'reason': i.reason.key,
          'start_utc': _utc(i.startUtc),
          'end_utc': i.endUtc == null ? null : _utc(i.endUtc),
          'auto_resumed': i.autoResumed,
        },
    ],
  };
  return '${_json.convert(map)}\n';
}

/// `conference.json`, basic form: the conference, goals and what this
/// export holds. P1-22 replaces it with the full manifest.
String buildConferenceJson({
  required Conference conference,
  required List<Goal> goals,
  required DateTime exportedAtUtc,
  required Map<String, Object?> scope,
  required List<Map<String, Object?>> activities,
  required int privateActivitiesExcluded,
  required int privateNotesExcluded,
}) {
  String? date(DateTime? d) => d?.toIso8601String().substring(0, 10);
  final map = <String, Object?>{
    'schema_version': exportSchemaVersion,
    'id': conference.id,
    'name': conference.name,
    'venue': conference.venue,
    'start_date': date(conference.startDate),
    'end_date': date(conference.endDate),
    'timezone': conference.timezone,
    'role_type': conference.roleType?.key,
    'role_text': conference.roleText,
    'goals': [
      for (final g in goals) {'text': g.goalText, 'priority': g.priority},
    ],
    'requested_outputs': [for (final o in conference.requestedOutputs) o.key],
    'exported_at_utc': exportedAtUtc.toUtc().toIso8601String(),
    'scope': scope,
    'privacy': {
      'private_activities_excluded': privateActivitiesExcluded,
      'private_notes_excluded': privateNotesExcluded,
    },
    'activities': activities,
  };
  return '${_json.convert(map)}\n';
}

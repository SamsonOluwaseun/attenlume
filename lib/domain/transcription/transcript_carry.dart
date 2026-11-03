import '../services/cut_range_math.dart';
import '../services/export_package.dart' show positionInKeptAudio;
import 'transcript.dart';

/// What happened to saved transcripts during a permanent trim or a split
/// (FR-TRN-08, ADR-081) [P2-09b]. The trim or split itself has already
/// succeeded when this is reported.
class TranscriptCarryReport {
  const TranscriptCarryReport({
    this.carried = 0,
    this.notCarried = 0,
    this.unchecked = false,
  });

  static const none = TranscriptCarryReport();

  /// Saved transcripts moved to the new recordings or activity.
  final int carried;

  /// Saved transcripts that could not be moved. Each is kept unchanged
  /// under its old recording; nothing was deleted.
  final int notCarried;

  /// The saved transcripts could not be read at all, so it is not known
  /// whether any needed moving. Any that exist are unchanged.
  final bool unchecked;

  bool get hasProblem => notCarried > 0 || unchecked;
}

/// The lines of [source] (a transcript of one recording) that a trimmed
/// piece holding only [keep] of that recording still contains, with times
/// counted from the piece's start, saved as [activityId]/[segmentId]
/// (ADR-081).
///
/// A line is kept only when it starts inside [keep] and ends by its end: a
/// line that touches removed audio is dropped whole, as in trimmed exports
/// (ADR-077 item 5), so cut speech never reappears as text. The mapping is
/// the export's [positionInKeptAudio]. Machine text and the user's
/// corrections both carry across. Null when no line is left.
TranscriptDocument? transcriptForTrimmedPiece(
  TranscriptDocument source, {
  required String activityId,
  required String segmentId,
  required TimeRange keep,
  required Duration segmentOffset,
}) {
  final kept = <(int, TranscriptSpan)>[];
  for (var i = 0; i < source.machineSpans.length; i++) {
    final span = source.machineSpans[i];
    final start = span.start.inMilliseconds;
    final end = span.end.inMilliseconds;
    final position = positionInKeptAudio([keep], start);
    if (position == null || end > position.$2.endMs) continue;
    kept.add((
      i,
      TranscriptSpan(
        start: Duration(milliseconds: position.$1),
        end: Duration(milliseconds: position.$1 + end - start),
        text: span.text,
      ),
    ));
  }
  return _rebuild(source, activityId, segmentId, segmentOffset, kept);
}

/// The lines of [source] that belong to one side of a split, saved as
/// [activityId]/[segmentId] (ADR-081).
///
/// A split writes no audio (ADR-036): both sides name the same file, so
/// times do not change. A line goes to the side that holds the middle of
/// its audio: from [fromMs] (inclusive) to [toMs] (exclusive), in ms from
/// the recording's start; null bounds are open. A whole recording that
/// moves to the new activity passes neither. Null when no line is left.
TranscriptDocument? transcriptForSplitPart(
  TranscriptDocument source, {
  required String activityId,
  required String segmentId,
  required Duration segmentOffset,
  int? fromMs,
  int? toMs,
}) {
  final kept = <(int, TranscriptSpan)>[];
  for (var i = 0; i < source.machineSpans.length; i++) {
    final span = source.machineSpans[i];
    final middle = (span.start.inMilliseconds + span.end.inMilliseconds) ~/ 2;
    if (fromMs != null && middle < fromMs) continue;
    if (toMs != null && middle >= toMs) continue;
    kept.add((i, span));
  }
  return _rebuild(source, activityId, segmentId, segmentOffset, kept);
}

/// [source] unchanged except for where its recording now sits: its
/// activity (a recording that moved whole in a split) and its place on that
/// activity's timeline.
TranscriptDocument transcriptPlacedAt(
  TranscriptDocument source, {
  String? activityId,
  required Duration segmentOffset,
}) => TranscriptDocument(
  activityId: activityId ?? source.activityId,
  segmentId: source.segmentId,
  machineSpans: source.machineSpans,
  corrections: source.corrections,
  createdAt: source.createdAt,
  segmentOffset: segmentOffset.isNegative ? Duration.zero : segmentOffset,
  modelId: source.modelId,
);

TranscriptDocument? _rebuild(
  TranscriptDocument source,
  String activityId,
  String segmentId,
  Duration segmentOffset,
  List<(int, TranscriptSpan)> kept,
) {
  if (kept.isEmpty) return null;
  final corrections = <int, String>{};
  for (var k = 0; k < kept.length; k++) {
    final correction = source.corrections[kept[k].$1];
    if (correction != null) corrections[k] = correction;
  }
  return TranscriptDocument(
    activityId: activityId,
    segmentId: segmentId,
    machineSpans: [for (final (_, span) in kept) span],
    corrections: corrections,
    createdAt: source.createdAt,
    segmentOffset: segmentOffset.isNegative ? Duration.zero : segmentOffset,
    modelId: source.modelId,
  );
}

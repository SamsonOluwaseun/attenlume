import '../../data/repositories/media_asset_repository.dart';
import '../../data/transcription/transcript_store.dart';
import '../models/media.dart';
import '../transcription/transcript.dart';
import '../transcription/transcript_carry.dart';
import 'cut_range_math.dart';

export '../transcription/transcript_carry.dart' show TranscriptCarryReport;

/// An activity's saved transcripts, read before a permanent trim or split
/// changes its recordings (ADR-081).
class TranscriptSnapshot {
  const TranscriptSnapshot._(this.activityId, this.ready, this.unreadable)
    : failed = false;

  const TranscriptSnapshot._failed(this.activityId)
    : ready = const {},
      unreadable = const {},
      failed = true;

  final String activityId;

  /// Readable transcripts by segment ID.
  final Map<String, TranscriptDocument> ready;

  /// Segment IDs whose transcript exists but cannot be read safely.
  final Set<String> unreadable;

  /// The store could not be listed at all.
  final bool failed;

  bool get isEmpty => !failed && ready.isEmpty && unreadable.isEmpty;
}

/// Carries saved transcripts across "Apply trims permanently" and "Split
/// activity" (FR-TRN-08, ADR-081) [P2-09b].
///
/// Transcripts are files keyed by activity and recording segment, outside
/// the database, so they are read before the operation and moved after its
/// transaction commits. Nothing here ever throws or undoes the trim or
/// split: a transcript that cannot be moved stays where it was, unchanged,
/// and the [TranscriptCarryReport] says so. The line maths are in
/// `transcript_carry.dart`.
class TranscriptCarrier {
  TranscriptCarrier({required this.store, required this.media});

  final Future<TranscriptStore> Function() store;
  final MediaAssetRepository media;

  /// Reads [activityId]'s saved transcripts. Never throws.
  Future<TranscriptSnapshot> read(String activityId) async {
    try {
      final results = await (await store()).inspectDocuments(
        activityId: activityId,
      );
      final ready = <String, TranscriptDocument>{};
      final unreadable = <String>{};
      for (final MapEntry(:key, :value) in results.entries) {
        final segmentId = key.substring(key.indexOf('/') + 1);
        if (value.state == TranscriptLoadState.ready) {
          ready[segmentId] = value.document!;
        } else {
          unreadable.add(segmentId);
        }
      }
      return TranscriptSnapshot._(activityId, ready, unreadable);
    } on Object {
      return TranscriptSnapshot._failed(activityId);
    }
  }

  /// After a permanent trim replaced recordings: each piece is (old segment
  /// ID, new segment ID, the part of the old recording it holds, in ms
  /// from its start). Lines in removed audio are dropped and the rest are
  /// timed from their piece's start. Transcripts of recordings the trim did
  /// not touch only get their new place on the timeline. Never throws.
  Future<TranscriptCarryReport> afterTrim(
    TranscriptSnapshot before, {
    required List<(String, String, TimeRange)> pieces,
  }) async {
    if (before.failed) return const TranscriptCarryReport(unchecked: true);
    final replaced = {for (final (from, _, _) in pieces) from};
    final affected = replaced.where(before.ready.containsKey).toSet();
    final unreadable = replaced.where(before.unreadable.contains).length;
    if (before.ready.isEmpty) {
      return TranscriptCarryReport(notCarried: unreadable);
    }
    try {
      final activityId = before.activityId;
      final offsets = await _offsets(activityId);
      final documents = <TranscriptDocument>[];
      for (final (from, to, keep) in pieces) {
        final source = before.ready[from];
        final offset = offsets[to];
        if (source == null) continue;
        if (offset == null) throw StateError('Trimmed recording not found');
        final carried = transcriptForTrimmedPiece(
          source,
          activityId: activityId,
          segmentId: to,
          keep: keep,
          segmentOffset: offset,
        );
        if (carried != null) documents.add(carried);
      }
      // Recordings the trim did not touch keep their text; only their
      // place moves when the first recording now starts later.
      final moved = <String>[];
      for (final MapEntry(key: id, value: doc) in before.ready.entries) {
        final offset = offsets[id];
        if (replaced.contains(id) ||
            offset == null ||
            offset == doc.segmentOffset) {
          continue;
        }
        documents.add(transcriptPlacedAt(doc, segmentOffset: offset));
        moved.add(id);
      }
      await (await store()).carry(
        documents: documents,
        retire: [
          for (final id in affected) (activityId, id),
          for (final id in moved) (activityId, id),
        ],
      );
      return TranscriptCarryReport(
        carried: affected.length,
        notCarried: unreadable,
      );
    } on Object {
      return TranscriptCarryReport(notCarried: affected.length + unreadable);
    }
  }

  /// After a split of `before.activityId`: [moves] maps each segment that
  /// moved to [part2Id] to its ID there (the same ID), and the segment the
  /// split fell inside to its new shared copy, split at [sharedSplitMs] ms
  /// from its start. Lines go to the side that holds their audio. Never
  /// throws.
  Future<TranscriptCarryReport> afterSplit(
    TranscriptSnapshot before, {
    required String part2Id,
    required Map<String, String> moves,
    int? sharedSplitMs,
  }) async {
    if (before.failed) return const TranscriptCarryReport(unchecked: true);
    final activityId = before.activityId;
    final affected = moves.keys.where(before.ready.containsKey).toSet();
    final unreadable = moves.keys.where(before.unreadable.contains).length;
    if (affected.isEmpty) return TranscriptCarryReport(notCarried: unreadable);
    try {
      final part1 = await _offsets(activityId);
      final part2 = await _offsets(part2Id);
      final documents = <TranscriptDocument>[];
      for (final from in affected) {
        final source = before.ready[from]!;
        final to = moves[from]!;
        final offset2 = part2[to];
        if (offset2 == null) throw StateError('Moved recording not found');
        if (from == to) {
          documents.add(
            transcriptPlacedAt(
              source,
              activityId: part2Id,
              segmentOffset: offset2,
            ),
          );
          continue;
        }
        final at = sharedSplitMs;
        final offset1 = part1[from];
        if (at == null || offset1 == null) {
          throw StateError('Split point not known');
        }
        final first = transcriptForSplitPart(
          source,
          activityId: activityId,
          segmentId: from,
          segmentOffset: offset1,
          toMs: at,
        );
        final second = transcriptForSplitPart(
          source,
          activityId: part2Id,
          segmentId: to,
          segmentOffset: offset2,
          fromMs: at,
        );
        if (first != null) documents.add(first);
        if (second != null) documents.add(second);
      }
      await (await store()).carry(
        documents: documents,
        retire: [for (final id in affected) (activityId, id)],
      );
      return TranscriptCarryReport(
        carried: affected.length,
        notCarried: unreadable,
      );
    } on Object {
      return TranscriptCarryReport(notCarried: affected.length + unreadable);
    }
  }

  /// Each segment's place on [activityId]'s timeline (BUILD_GUIDE 9.4).
  Future<Map<String, Duration>> _offsets(String activityId) async {
    final List<RecordingSegment> segments = await media.segmentsFor(activityId);
    if (segments.isEmpty) return const {};
    final first = segments
        .map((s) => s.startUtc)
        .reduce((a, b) => a.isBefore(b) ? a : b);
    return {for (final s in segments) s.id: s.startUtc.difference(first)};
  }
}

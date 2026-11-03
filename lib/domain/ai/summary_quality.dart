import '../transcription/transcript.dart';
import 'session_material.dart';
import 'session_summary.dart';

/// One scored test session for the summary quality bar (ADR-076 item 4):
/// a model is listed or replaced only when it passes every case.
class SummaryQualityCase {
  const SummaryQualityCase({
    required this.id,
    required this.title,
    required this.speech,
    required this.expectedFacts,
    required this.forbidden,
    this.bookmarks = const [],
    this.notesMd,
  });

  final String id;
  final String title;

  /// Seconds from the start, and what was said.
  final List<(int, String)> speech;
  final List<MaterialBookmark> bookmarks;
  final String? notesMd;

  /// Facts a good summary covers. Each fact is a list of alternative
  /// phrases; the fact counts as covered when any of them appears.
  final List<List<String>> expectedFacts;

  /// Plausible claims that are not in the session. Any of them in the
  /// summary means the model invented something.
  final List<String> forbidden;

  SessionMaterial material() => SessionMaterial.build(
    title: title,
    transcripts: [
      TranscriptDocument(
        activityId: id,
        segmentId: '${id}_s1',
        createdAt: DateTime.utc(2026, 11, 3),
        machineSpans: [
          for (final (i, (at, text)) in speech.indexed)
            TranscriptSpan(
              start: Duration(seconds: at),
              end: Duration(
                seconds: i + 1 < speech.length ? speech[i + 1].$1 : at + 10,
              ),
              text: text,
            ),
        ],
      ),
    ],
    bookmarks: bookmarks,
    notesMd: notesMd,
  );
}

class SummaryQualityScore {
  const SummaryQualityScore({
    required this.coverage,
    required this.inventions,
    required this.leftOutShare,
    required this.points,
  });

  /// Share of expected facts covered, 0 to 1.
  final double coverage;

  /// Forbidden claims found.
  final List<String> inventions;

  /// Share of the model's items that cited no real moment, 0 to 1.
  final double leftOutShare;
  final int points;

  /// The bar: most facts, nothing invented, few untraceable items, and
  /// enough key points to be useful.
  bool get passes =>
      coverage >= 0.6 &&
      inventions.isEmpty &&
      leftOutShare <= 0.2 &&
      points >= 3;

  @override
  String toString() =>
      'coverage ${(coverage * 100).round()}%, inventions $inventions, '
      'left out ${(leftOutShare * 100).round()}%, $points points';
}

SummaryQualityScore scoreSummary(
  SessionSummary summary,
  SummaryQualityCase test,
) {
  final text = [
    summary.summary,
    for (final p in summary.points) p.text,
    for (final f in summary.followUps) f.text,
    ...summary.questions,
  ].join('\n').toLowerCase();
  final covered = test.expectedFacts
      .where((alternatives) => alternatives.any(text.contains))
      .length;
  final items = summary.points.length + summary.followUps.length;
  return SummaryQualityScore(
    coverage: test.expectedFacts.isEmpty
        ? 1
        : covered / test.expectedFacts.length,
    inventions: [
      for (final f in test.forbidden)
        if (text.contains(f.toLowerCase())) f,
    ],
    leftOutShare: items + summary.leftOut == 0
        ? 0
        : summary.leftOut / (items + summary.leftOut),
    points: summary.points.length,
  );
}

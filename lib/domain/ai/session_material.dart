import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';

import '../models/media.dart';
import '../transcription/transcript.dart';

/// What a line of session material is (P3-02, ADR-076 item 5).
enum MaterialKind { speech, bookmark, note }

/// One line a summary may draw on. [at] is the place on the activity
/// timeline (milliseconds from the first recording's start, the same base
/// as the review player), or null for the session notes.
class MaterialLine {
  const MaterialLine({required this.kind, required this.text, this.at});

  final MaterialKind kind;
  final String text;
  final Duration? at;

  /// How the line appears to the model.
  String render() {
    final time = at == null ? '' : '[${formatSummaryTime(at!)}] ';
    return switch (kind) {
      MaterialKind.speech => '$time$text',
      MaterialKind.bookmark => '${time}BOOKMARK: $text',
      MaterialKind.note => 'NOTE: $text',
    };
  }

  /// A rough token count: about four characters per token for English,
  /// plus the line break and timestamp.
  int get estimatedTokens => estimateTokens(render()) + 1;
}

/// A bookmark placed on the review timeline (its offset already resolved).
typedef MaterialBookmark = ({int offsetMs, String? label, String? note});

/// Everything one session's summary is grounded in: the saved transcript
/// (with the user's corrections), bookmarks and notes, nothing else
/// (ADR-076 item 5). Speech inside an active cut is left out.
class SessionMaterial {
  SessionMaterial._(this.title, this.lines);

  factory SessionMaterial.build({
    required String title,
    required List<TranscriptDocument> transcripts,
    List<MaterialBookmark> bookmarks = const [],
    String? notesMd,
    List<CutRange> cuts = const [],
  }) {
    bool cut(Duration at) => cuts.any(
      (c) =>
          !c.isDeleted &&
          at.inMilliseconds >= c.startOffsetMs &&
          at.inMilliseconds < c.endOffsetMs,
    );
    final timed = <MaterialLine>[];
    for (final document in transcripts) {
      for (var i = 0; i < document.machineSpans.length; i++) {
        final span = document.machineSpans[i];
        final start = span.start + document.segmentOffset;
        final middle = start + (span.end - span.start) ~/ 2;
        final text = _clean(document.textAt(i));
        if (text.isEmpty || cut(middle)) continue;
        timed.add(
          MaterialLine(kind: MaterialKind.speech, text: text, at: start),
        );
      }
    }
    for (final bookmark in bookmarks) {
      final at = Duration(milliseconds: bookmark.offsetMs);
      if (bookmark.offsetMs < 0 || cut(at)) continue;
      final text = _clean(
        [
          bookmark.label,
          bookmark.note,
        ].whereType<String>().where((s) => s.trim().isNotEmpty).join(' - '),
      );
      timed.add(
        MaterialLine(
          kind: MaterialKind.bookmark,
          text: text.isEmpty ? 'marked moment' : text,
          at: at,
        ),
      );
    }
    // Stable order: by time, speech before a bookmark at the same moment.
    timed.sort((a, b) {
      final byTime = a.at!.compareTo(b.at!);
      return byTime != 0 ? byTime : a.kind.index.compareTo(b.kind.index);
    });
    final notes = [
      for (final line in const LineSplitter().convert(notesMd ?? ''))
        if (_clean(line.replaceFirst(RegExp(r'^\s*([-*+]|#+)\s*'), ''))
            case final text when text.isNotEmpty)
          MaterialLine(kind: MaterialKind.note, text: text),
    ];
    return SessionMaterial._(
      _clean(title),
      List.unmodifiable([...notes, ...timed]),
    );
  }

  final String title;

  /// Notes first, then timed lines in order.
  final List<MaterialLine> lines;

  bool get hasSpeech => lines.any((l) => l.kind == MaterialKind.speech);

  /// Every timestamp a summary item may cite.
  List<Duration> get timestamps => [for (final line in lines) ?line.at];

  /// Changes whenever anything a summary is built from changes, so a saved
  /// summary can say it is out of date.
  String get fingerprint => sha256
      .convert(
        utf8.encode([title, for (final l in lines) l.render()].join('\n')),
      )
      .toString();

  /// Splits the lines into consecutive chunks of at most [budgetTokens]
  /// each (ADR-076 item 5: long transcripts are summarised in chunks). A
  /// single line longer than the budget is cut to fit.
  List<List<MaterialLine>> chunks(int budgetTokens) {
    if (budgetTokens < 32) throw ArgumentError.value(budgetTokens, 'budget');
    final result = <List<MaterialLine>>[];
    var current = <MaterialLine>[];
    var used = 0;
    for (var line in lines) {
      if (line.estimatedTokens > budgetTokens) {
        line = MaterialLine(
          kind: line.kind,
          at: line.at,
          text: line.text.substring(
            0,
            math.min(line.text.length, (budgetTokens - 16) * 4),
          ),
        );
      }
      if (used + line.estimatedTokens > budgetTokens && current.isNotEmpty) {
        result.add(current);
        current = [];
        used = 0;
      }
      current.add(line);
      used += line.estimatedTokens;
    }
    if (current.isNotEmpty) result.add(current);
    return result;
  }
}

/// About four characters per token for English text.
int estimateTokens(String text) => (text.length / 4).ceil();

/// `12:34` under an hour, `1:02:03` from an hour.
String formatSummaryTime(Duration value) {
  final s = value.inSeconds;
  String two(int n) => '$n'.padLeft(2, '0');
  return s >= 3600
      ? '${s ~/ 3600}:${two(s ~/ 60 % 60)}:${two(s % 60)}'
      : '${two(s ~/ 60)}:${two(s % 60)}';
}

/// Reads `12:34`, `1:02:03` or `12:34.500`; null when it is not a time.
Duration? parseSummaryTime(String value) {
  final m = RegExp(r'^(?:(\d{1,2}):)?(\d{1,3}):(\d{2})(?:\.\d+)?$')
      .firstMatch(value.trim());
  if (m == null) return null;
  final minutes = int.parse(m[2]!);
  final seconds = int.parse(m[3]!);
  if (seconds > 59 || (m[1] != null && minutes > 59)) return null;
  return Duration(
    hours: int.parse(m[1] ?? '0'),
    minutes: minutes,
    seconds: seconds,
  );
}

/// One line, no control characters, no runs of spaces.
String _clean(String text) => text
    .replaceAll(RegExp(r'[\u0000-\u001F\u007F]'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

import 'dart:collection';

/// File-safe keys for activity and recording segment records (FR-TRN-08).
String validateTranscriptId(String value) {
  if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$').hasMatch(value) ||
      RegExp(
        r'^(CON|PRN|AUX|NUL|COM[0-9]|LPT[0-9])$',
        caseSensitive: false,
      ).hasMatch(value)) {
    throw ArgumentError.value(
      value,
      'identifier',
      'Invalid transcript identifier',
    );
  }
  return value;
}

/// One final machine-produced span, relative to its source recording segment.
class TranscriptSpan {
  TranscriptSpan({required this.start, required this.end, required this.text}) {
    if (start.isNegative ||
        end < start ||
        text.trim().isEmpty ||
        text.contains('\u0000')) {
      throw ArgumentError('Invalid transcript span');
    }
  }

  final Duration start;
  final Duration end;
  final String text;

  Map<String, Object> toJson() => {
    'startMs': start.inMilliseconds,
    'endMs': end.inMilliseconds,
    'text': text,
  };

  factory TranscriptSpan.fromJson(Map<String, dynamic> json) {
    if (json['startMs'] is! int ||
        json['endMs'] is! int ||
        json['text'] is! String) {
      throw const FormatException('Invalid span fields');
    }
    return TranscriptSpan(
      start: Duration(milliseconds: json['startMs'] as int),
      end: Duration(milliseconds: json['endMs'] as int),
      text: json['text'] as String,
    );
  }
}

/// Immutable machine output and separately keyed corrections (FR-TRN-08).
///
/// A document belongs to exactly one recording segment. [segmentOffset] places
/// its timestamps on the activity timeline without collapsing recording gaps.
class TranscriptDocument {
  TranscriptDocument({
    required String activityId,
    required String segmentId,
    required List<TranscriptSpan> machineSpans,
    required DateTime createdAt,
    Map<int, String> corrections = const {},
    this.segmentOffset = Duration.zero,
    this.modelId,
  }) : activityId = validateTranscriptId(activityId),
       segmentId = validateTranscriptId(segmentId),
       createdAt = createdAt.toUtc(),
       machineSpans = List.unmodifiable(machineSpans),
       corrections = UnmodifiableMapView(Map<int, String>.of(corrections)) {
    if (segmentOffset.isNegative || machineSpans.length > 100000) {
      throw ArgumentError('Invalid transcript timeline');
    }
    var previous = Duration.zero;
    for (final span in machineSpans) {
      if (span.start < previous) {
        throw ArgumentError('Spans must be ordered by start');
      }
      previous = span.start;
    }
    for (final entry in corrections.entries) {
      if (entry.key < 0 ||
          entry.key >= machineSpans.length ||
          entry.value.contains('\u0000')) {
        throw ArgumentError('Invalid transcript correction');
      }
    }
  }

  final String activityId;
  final String segmentId;
  final List<TranscriptSpan> machineSpans;
  final Map<int, String> corrections;
  final DateTime createdAt;
  final Duration segmentOffset;
  final String? modelId;

  String textAt(int index, {bool useCorrections = true}) => useCorrections
      ? corrections[index] ?? machineSpans[index].text
      : machineSpans[index].text;

  TranscriptDocument withCorrections(Map<int, String> values) =>
      TranscriptDocument(
        activityId: activityId,
        segmentId: segmentId,
        machineSpans: machineSpans,
        createdAt: createdAt,
        segmentOffset: segmentOffset,
        modelId: modelId,
        corrections: values,
      );

  Map<String, Object?> toJson() => {
    'version': 1,
    'activityId': activityId,
    'segmentId': segmentId,
    'createdAt': createdAt.toIso8601String(),
    'segmentOffsetMs': segmentOffset.inMilliseconds,
    'modelId': modelId,
    'machineSpans': machineSpans.map((span) => span.toJson()).toList(),
    'corrections': {for (final e in corrections.entries) '${e.key}': e.value},
  };

  factory TranscriptDocument.fromJson(Map<String, dynamic> json) {
    if (json['version'] != 1 ||
        json['activityId'] is! String ||
        json['segmentId'] is! String ||
        json['createdAt'] is! String ||
        json['segmentOffsetMs'] is! int ||
        json['machineSpans'] is! List ||
        json['corrections'] is! Map ||
        (json['modelId'] != null && json['modelId'] is! String)) {
      throw const FormatException(
        'Invalid transcript document fields or version',
      );
    }
    final corrections = <int, String>{};
    for (final entry in (json['corrections'] as Map).entries) {
      if (entry.key is! String ||
          !RegExp(r'^(0|[1-9][0-9]*)$').hasMatch(entry.key as String) ||
          entry.value is! String) {
        throw const FormatException('Invalid correction fields');
      }
      corrections[int.parse(entry.key as String)] = entry.value as String;
    }
    final spans = <TranscriptSpan>[];
    for (final span in json['machineSpans'] as List) {
      if (span is! Map<String, dynamic>) {
        throw const FormatException('Invalid machine span');
      }
      spans.add(TranscriptSpan.fromJson(span));
    }
    return TranscriptDocument(
      activityId: json['activityId'] as String,
      segmentId: json['segmentId'] as String,
      machineSpans: spans,
      corrections: corrections,
      createdAt: DateTime.parse(json['createdAt'] as String),
      segmentOffset: Duration(milliseconds: json['segmentOffsetMs'] as int),
      modelId: json['modelId'] as String?,
    );
  }
}

/// Plain text suitable for UTF-8 transcript.txt, copy or an explicit share.
String renderTranscriptText(
  TranscriptDocument document, {
  bool useCorrections = true,
}) =>
    '${[for (var i = 0; i < document.machineSpans.length; i++) document.textAt(i, useCorrections: useCorrections)].join('\n')}\n';

/// Timestamped transcript.md; times retain the segment's activity offset.
String renderTranscriptMarkdown(
  TranscriptDocument document, {
  bool useCorrections = true,
}) {
  final lines = <String>[
    '# Transcript',
    '',
    'Machine-generated text; may contain errors.',
    '',
  ];
  for (var i = 0; i < document.machineSpans.length; i++) {
    final span = document.machineSpans[i];
    final text = escapeTranscriptMarkdown(
      document.textAt(i, useCorrections: useCorrections),
    );
    lines.add(
      '- **[${_timestamp(span.start + document.segmentOffset)} - ${_timestamp(span.end + document.segmentOffset)}]** $text',
    );
  }
  return '${lines.join('\n')}\n';
}

/// Transcript text made safe inside a Markdown list item: Markdown
/// characters are escaped and line breaks stay inside the item. Shared by
/// copy/share and the export's `transcript.md` (FR-TRN-08).
String escapeTranscriptMarkdown(String text) => text
    .replaceAllMapped(RegExp(r'[\\`*_{}\[\]<>#!|]'), (m) => '\\${m[0]}')
    .replaceAll('\r\n', '\n')
    .replaceAll('\r', '\n')
    .replaceAll('\n', '  \n  ');

String _timestamp(Duration value) {
  String pad(int n, [int width = 2]) => '$n'.padLeft(width, '0');
  final ms = value.inMilliseconds;
  return '${pad(ms ~/ 3600000)}:${pad(ms ~/ 60000 % 60)}:${pad(ms ~/ 1000 % 60)}.${pad(ms % 1000, 3)}';
}

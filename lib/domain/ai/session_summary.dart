import '../transcription/transcript.dart' show validateTranscriptId;

/// A key point or follow-up, linked to the moment in the recording that
/// supports it (ADR-076 item 5).
class SummaryItem {
  SummaryItem({required this.text, required this.at}) {
    if (text.trim().isEmpty || at.isNegative) {
      throw ArgumentError('Invalid summary item');
    }
  }

  final String text;
  final Duration at;

  Map<String, Object> toJson() => {'text': text, 'atMs': at.inMilliseconds};

  factory SummaryItem.fromJson(Object? json) {
    if (json is! Map<String, dynamic> ||
        json['text'] is! String ||
        json['atMs'] is! int) {
      throw const FormatException('Invalid summary item');
    }
    return SummaryItem(
      text: json['text'] as String,
      at: Duration(milliseconds: json['atMs'] as int),
    );
  }
}

/// A machine-generated summary of one session (P3-02). Kept as its own file
/// beside the transcripts; never changes the recording or the transcript.
class SessionSummary {
  SessionSummary({
    required String activityId,
    required this.modelId,
    required DateTime createdAt,
    required this.materialFingerprint,
    required this.summary,
    required List<SummaryItem> points,
    List<SummaryItem> followUps = const [],
    List<String> questions = const [],
    this.chunkCount = 1,
    this.leftOut = 0,
  }) : activityId = validateTranscriptId(activityId),
       createdAt = createdAt.toUtc(),
       points = List.unmodifiable(points),
       followUps = List.unmodifiable(followUps),
       questions = List.unmodifiable(questions);

  final String activityId;

  /// The model that wrote it, shown beside the "machine-generated" label.
  final String modelId;
  final DateTime createdAt;

  /// [SessionMaterial.fingerprint] when it was made; a different value now
  /// means the transcript, bookmarks or notes changed since.
  final String materialFingerprint;
  final String summary;
  final List<SummaryItem> points;
  final List<SummaryItem> followUps;
  final List<String> questions;

  /// How many parts a long session was summarised in.
  final int chunkCount;

  /// Items the model wrote that could not be traced to a moment in the
  /// session and were therefore dropped.
  final int leftOut;

  Map<String, Object?> toJson() => {
    'version': 1,
    'activityId': activityId,
    'modelId': modelId,
    'createdAt': createdAt.toIso8601String(),
    'materialFingerprint': materialFingerprint,
    'summary': summary,
    'points': [for (final p in points) p.toJson()],
    'followUps': [for (final f in followUps) f.toJson()],
    'questions': questions,
    'chunkCount': chunkCount,
    'leftOut': leftOut,
  };

  factory SessionSummary.fromJson(Map<String, dynamic> json) {
    if (json['version'] != 1 ||
        json['activityId'] is! String ||
        json['modelId'] is! String ||
        json['createdAt'] is! String ||
        json['materialFingerprint'] is! String ||
        json['summary'] is! String ||
        json['points'] is! List ||
        json['followUps'] is! List ||
        json['questions'] is! List ||
        json['chunkCount'] is! int ||
        json['leftOut'] is! int ||
        (json['questions'] as List).any((q) => q is! String)) {
      throw const FormatException('Invalid summary fields or version');
    }
    return SessionSummary(
      activityId: json['activityId'] as String,
      modelId: json['modelId'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      materialFingerprint: json['materialFingerprint'] as String,
      summary: json['summary'] as String,
      points: [for (final p in json['points'] as List) SummaryItem.fromJson(p)],
      followUps: [
        for (final f in json['followUps'] as List) SummaryItem.fromJson(f),
      ],
      questions: List<String>.from(json['questions'] as List),
      chunkCount: json['chunkCount'] as int,
      leftOut: json['leftOut'] as int,
    );
  }
}

import 'dart:convert';

import 'package:attenlume/domain/transcription/transcript.dart';
import 'package:flutter_test/flutter_test.dart';

TranscriptDocument sampleDocument({Map<int, String> corrections = const {}}) =>
    TranscriptDocument(
      activityId: 'activity-1',
      segmentId: 'segment-1',
      createdAt: DateTime.utc(2026, 10, 31),
      segmentOffset: const Duration(minutes: 2),
      modelId: 'test-model',
      corrections: corrections,
      machineSpans: [
        TranscriptSpan(
          start: Duration.zero,
          end: const Duration(seconds: 1, milliseconds: 250),
          text: 'Caf\u00e9: Samlytics Conference 2026',
        ),
        TranscriptSpan(
          start: const Duration(seconds: 4),
          end: const Duration(seconds: 5),
          text: 'Second thought',
        ),
      ],
    );

void main() {
  test('FR-TRN-08 machine text remains immutable and corrections render separately', () {
    final original = sampleDocument();
    final corrected = original.withCorrections({0: 'A corrected thought'});
    expect(original.machineSpans[0].text, contains('Caf\u00e9'));
    expect(corrected.machineSpans[0].text, original.machineSpans[0].text);
    expect(
      renderTranscriptText(corrected),
      'A corrected thought\nSecond thought\n',
    );
    expect(
      renderTranscriptText(corrected, useCorrections: false),
      renderTranscriptText(original),
    );
    expect(corrected.machineSpans.clear, throwsUnsupportedError);
    expect(() => corrected.corrections[1] = 'change', throwsUnsupportedError);
    expect(
      utf8.decode(utf8.encode(renderTranscriptText(original))),
      contains('Caf\u00e9'),
    );
  });

  test('FR-TRN-08 timestamped markdown retains segment offset, silence gaps and escapes text', () {
    final corrected = sampleDocument().withCorrections({
      0: '**edited**\n<unsafe>',
    });
    final markdown = renderTranscriptMarkdown(corrected);
    expect(markdown, contains('[00:02:00.000 - 00:02:01.250]'));
    expect(markdown, contains('[00:02:04.000 - 00:02:05.000]'));
    expect(markdown, contains(r'\*\*edited\*\*'));
    expect(markdown, contains(r'\<unsafe\>'));
    expect(markdown, contains('Machine-generated text; may contain errors.'));
  });

  test(
    'FR-TRN-08 JSON round trip retains original and correction metadata',
    () {
      final document = sampleDocument(corrections: {1: ''});
      final restored = TranscriptDocument.fromJson(
        jsonDecode(jsonEncode(document.toJson())) as Map<String, dynamic>,
      );
      expect(restored.toJson(), document.toJson());
      expect(renderTranscriptText(restored), endsWith('\n\n'));
    },
  );

  test(
    'FR-TRN-08 unsafe IDs and invalid timing/correction data are rejected',
    () {
      for (final id in [
        '',
        '../activity',
        '/absolute',
        'a/b',
        r'a\b',
        'CON',
        'nul',
        '.',
        'a.json',
        'a\nvalue',
      ]) {
        expect(() => validateTranscriptId(id), throwsArgumentError, reason: id);
      }
      expect(
        () => TranscriptSpan(
          start: const Duration(seconds: -1),
          end: Duration.zero,
          text: 'word',
        ),
        throwsArgumentError,
      );
      expect(
        () => TranscriptSpan(
          start: const Duration(seconds: 2),
          end: Duration.zero,
          text: 'word',
        ),
        throwsArgumentError,
      );
      expect(
        () =>
            TranscriptSpan(start: Duration.zero, end: Duration.zero, text: ' '),
        throwsArgumentError,
      );
      expect(
        () => sampleDocument().withCorrections({2: 'not a span'}),
        throwsArgumentError,
      );
      expect(
        () => TranscriptDocument.fromJson({'version': 2}),
        throwsFormatException,
      );
      final invalid = sampleDocument().toJson()
        ..['corrections'] = {'01': 'alias'};
      expect(() => TranscriptDocument.fromJson(invalid), throwsFormatException);
    },
  );
}

import 'dart:async';
import 'dart:io';

import 'package:attenlume/data/local_database/database_provider.dart';
import 'package:attenlume/data/repositories/cut_range_repository.dart';
import 'package:attenlume/data/repositories/repository_providers.dart';
import 'package:attenlume/domain/models/media.dart';
import 'package:attenlume/features/capture/recording_providers.dart';
import 'package:attenlume/features/transcription/transcription_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../fixtures/fixtures.dart';

class _DelayedCuts extends CutRangeRepository {
  _DelayedCuts(super.db);
  final entered = Completer<void>();
  final gate = Completer<void>();
  @override
  Future<List<CutRange>> activeFor(String activityId) async {
    entered.complete();
    await gate.future;
    return super.activeFor(activityId);
  }
}

void main() {
  test('FR-TRN-01 P1-54 activity audio lookup survives read-only future across async file/database work', () async {
    final data = TestData();
    final root = await Directory.systemTemp.createTemp(
      'transcription-sources-',
    );
    final cuts = _DelayedCuts(data.db);
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(data.db),
        cutRangeRepositoryProvider.overrideWithValue(cuts),
        mediaRootProvider.overrideWithValue(() async => root),
      ],
    );
    try {
      final conference = await data.conference();
      final activity = await data.activity(conference.id);
      final segment = await data.segment(
        activity.id,
        start: DateTime.utc(2026, 11, 1),
        length: const Duration(seconds: 5),
      );
      final audio = File(p.join(root.path, segment.filePath));
      await audio.writeAsBytes([0]);
      // Same access pattern as the button: no ref.watch/listen on this family.
      final result = container.read(
        transcriptionSourcesProvider(activity.id).future,
      );
      final assertion = expectLater(result, completion(hasLength(1)));
      await cuts.entered.future;
      await container.pump();
      cuts.gate.complete();
      await assertion;
      // P2-14: the session's own words travel with the audio.
      final hint = (await result).single.hint;
      expect(hint, startsWith('Samlytics Conference 2026.'));
      await container.pump();
      expect(
        container.exists(transcriptionSourcesProvider(activity.id)),
        isFalse,
      );
      expect(await audio.readAsBytes(), [0]);
    } finally {
      container.dispose();
      await data.close();
      await root.delete(recursive: true);
    }
  });
}

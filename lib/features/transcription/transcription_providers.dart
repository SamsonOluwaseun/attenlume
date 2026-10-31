import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../data/filesystem/app_data_directory.dart';
import '../../data/local_database/database_provider.dart';
import '../../data/repositories/repository_providers.dart';
import '../../data/transcription/transcript_store.dart';
import '../../domain/models/enums.dart';
import '../capture/recording_providers.dart';
import 'native_pilot.dart';
import 'transcription_controller.dart';

/// Lazy: ordinary startup does not construct model access or an engine.
final transcriptionControllerProvider = FutureProvider<TranscriptionController>(
  (ref) async {
    final root = await appDataDirectory();
    final db = ref.read(appDatabaseProvider);
    final native = await createNativePilot(root);
    final recorder = ref.read(recordingServiceProvider);
    final controller = TranscriptionController(
      models: native.models,
      store: TranscriptStore(root),
      createEngine: native.createEngine,
      enabled: await db.readSetting('transcription_available') == 'true',
      writeEnabled: (value) =>
          db.writeSetting('transcription_available', '$value'),
      recordingHeld: () => recorder.status.state.holdsActivity,
    );
    final subscription = recorder.statusStream.listen((status) {
      if (status.state.holdsActivity && controller.busy) {
        unawaited(controller.cancel());
      }
    });
    ref.onDispose(() {
      unawaited(subscription.cancel());
      unawaited(controller.cancel().whenComplete(controller.dispose));
    });
    await controller.refresh();
    return controller;
  },
);

final transcriptionSourcesProvider = FutureProvider.autoDispose
    .family<List<TranscriptionSource>, String>((ref, activityId) async {
      if ((await ref.read(cutRangeRepositoryProvider).activeFor(activityId))
          .isNotEmpty) {
        throw StateError(
          'Audio cuts are not supported by this transcription pilot.',
        );
      }
      final segments = await ref
          .read(mediaAssetRepositoryProvider)
          .segmentsFor(activityId);
      final saved =
          segments
              .where(
                (segment) =>
                    segment.state == SegmentState.finalised ||
                    segment.state == SegmentState.recovered,
              )
              .toList()
            ..sort((a, b) => a.startUtc.compareTo(b.startUtc));
      if (saved.isEmpty) return [];
      final firstStart = await ref
          .read(mediaAssetRepositoryProvider)
          .firstSegmentStart(activityId);
      final root = await ref.read(mediaRootProvider)();
      final resolvedRoot = await root.resolveSymbolicLinks();
      final sources = <TranscriptionSource>[];
      for (final segment in saved) {
        final resolved = await File(p.join(root.path, segment.filePath))
            .resolveSymbolicLinks();
        if (!p.isWithin(resolvedRoot, resolved)) {
          throw const FileSystemException('Audio path is outside app media');
        }
        sources.add(
          TranscriptionSource(
            activityId: activityId,
            segmentId: segment.id,
            audioPath: resolved,
            offset: segment.startUtc.difference(
              firstStart ?? saved.first.startUtc,
            ),
          ),
        );
      }
      return sources;
    });

final transcriptionEditsPresentProvider = FutureProvider.autoDispose
    .family<bool, String>((ref, activityId) async {
      return (await ref.read(cutRangeRepositoryProvider).activeFor(activityId))
          .isNotEmpty;
    });

import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../data/filesystem/app_data_directory.dart';
import '../../data/local_database/database_provider.dart';
import '../../data/repositories/repository_providers.dart';
import '../../data/transcription/transcript_store.dart';
import '../../domain/models/enums.dart';
import '../../domain/transcription/vocabulary_hint.dart';
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
  // Setup retries are explicit: avoid repeated native/storage initialisation.
  retry: (_, _) => null,
);

final transcriptionSourcesProvider = FutureProvider.autoDispose
    .family<List<TranscriptionSource>, String>((ref, activityId) async {
      // A button reads .future without a persistent listener. Keep this request
      // alive across database/file awaits; never use ref after an async gap.
      final request = ref.keepAlive();
      try {
        final cuts = ref.read(cutRangeRepositoryProvider);
        final media = ref.read(mediaAssetRepositoryProvider);
        final resolveRoot = ref.read(mediaRootProvider);
        final activities = ref.read(activityRepositoryProvider);
        final conferences = ref.read(conferenceRepositoryProvider);
        if ((await cuts.activeFor(activityId)).isNotEmpty) {
          throw StateError(
            'Audio cuts are not supported by this transcription pilot.',
          );
        }
        final segments = await media.segmentsFor(activityId);
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
        final firstStart = await media.firstSegmentStart(activityId);
        final activity = await activities.get(activityId);
        final conference = activity == null
            ? null
            : await conferences.get(activity.conferenceId);
        final hint = vocabularyHint(
          conferenceName: conference?.name,
          speakerNames: activity?.speakerNames ?? const [],
          organisation: activity?.organisation,
        );
        final root = await resolveRoot();
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
              hint: hint,
            ),
          );
        }
        return sources;
      } finally {
        request.close();
      }
    });

final transcriptionEditsPresentProvider = FutureProvider.autoDispose
    .family<bool, String>((ref, activityId) async {
      return (await ref.read(cutRangeRepositoryProvider).activeFor(activityId))
          .isNotEmpty;
    });

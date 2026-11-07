import 'dart:async';
import 'dart:io';

import 'package:attenlume/data/transcription/transcript_store.dart';
import 'package:attenlume/domain/transcription/transcript.dart';
import 'package:attenlume/domain/transcription/transcription_engine.dart';
import 'package:attenlume/features/transcription/transcription_controller.dart';
import 'package:flutter_test/flutter_test.dart';

class _Models implements PilotModelManager {
  bool installed = false;
  int downloads = 0;
  int removals = 0;
  Completer<void>? cancelGate;
  bool failCancel = false;
  @override
  String get name => 'English pilot';
  @override
  int get downloadBytes => 1024;
  @override
  String get directory => 'model';
  @override
  Future<bool> isInstalled() async => installed;
  @override
  Future<bool> hasFiles() async => installed;
  @override
  Future<void> install(void Function(double) onProgress) async {
    downloads++;
    onProgress(1);
    installed = true;
  }

  @override
  Future<void> cancelInstall() async {
    await cancelGate?.future;
    if (failCancel) throw StateError('Synthetic model cancellation failure');
  }

  @override
  Future<void> remove() async {
    removals++;
    installed = false;
  }
}

class _Engine implements TranscriptionEngine {
  Completer<List<TranscriptSpan>>? gate;
  int cancellations = 0;
  final hints = <String?>[];
  int disposals = 0;
  @override
  Future<List<TranscriptSpan>> transcribe({
    required String audioPath,
    required String modelDirectory,
    required void Function(double) onProgress,
    String? hint,
  }) async {
    hints.add(hint);
    onProgress(0.5);
    return gate?.future ??
        [
          TranscriptSpan(
            start: Duration.zero,
            end: const Duration(seconds: 1),
            text: 'Samlytics Data Services',
          ),
        ];
  }

  @override
  Future<void> cancel() async {
    cancellations++;
    if (gate != null && !gate!.isCompleted) {
      gate!.completeError(const TranscriptionCancelledException());
    }
  }

  @override
  Future<void> dispose() async {
    disposals++;
  }
}

class _GatedStore extends TranscriptStore {
  _GatedStore(super.root);
  final entered = Completer<void>();
  final gate = Completer<void>();
  final saveEntered = Completer<void>();
  final saveGate = Completer<void>();
  bool gateLoad = false;
  bool gateSave = false;

  @override
  Future<TranscriptLoadResult> load({
    required String activityId,
    required String segmentId,
  }) async {
    if (gateLoad) {
      gateLoad = false;
      entered.complete();
      await gate.future;
    }
    return super.load(activityId: activityId, segmentId: segmentId);
  }

  @override
  Future<TranscriptDocument> saveOriginal(TranscriptDocument document) async {
    if (gateSave) {
      gateSave = false;
      saveEntered.complete();
      await saveGate.future;
    }
    return super.saveOriginal(document);
  }
}

void main() {
  late Directory directory;
  late _Models models;
  late _Engine engine;
  late TranscriptionController controller;
  var held = false;
  var created = 0;
  const source = TranscriptionSource(
    activityId: 'activity',
    segmentId: 'segment',
    audioPath: 'original.m4a',
  );

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'attenlume-transcript-controller-',
    );
    models = _Models();
    engine = _Engine();
    held = false;
    created = 0;
    controller = TranscriptionController(
      models: models,
      store: TranscriptStore(directory),
      createEngine: () {
        created++;
        return engine;
      },
      writeEnabled: (_) async {},
      recordingHeld: () => held,
    );
  });
  tearDown(() async {
    await controller.cancel();
    controller.dispose();
    await directory.delete(recursive: true);
  });

  test('FR-TRN-01 opening or enabling never downloads a model or creates an engine', () async {
    await controller.refresh();
    expect(controller.enabled, isFalse);
    await controller.install();
    await controller.transcribe([source]);
    await controller.setEnabled(true);
    expect(models.downloads, 0);
    expect(created, 0);
  });

  test('FR-TRN-03 explicit install alone never starts inference', () async {
    await controller.setEnabled(true);
    await controller.install();
    expect(models.downloads, 1);
    expect(controller.installed, isTrue);
    expect(created, 0);
  });

  test(
    'P2-14 FR-TRN-10 each source passes its session words to the engine',
    () async {
      await controller.setEnabled(true);
      await controller.install();
      await controller.transcribe([
        const TranscriptionSource(
          activityId: 'activity',
          segmentId: 'segment',
          audioPath: 'original.m4a',
          hint: 'Samlytics Conference 2026.',
        ),
      ]);
      await controller.transcribe([
        const TranscriptionSource(
          activityId: 'activity',
          segmentId: 'second',
          audioPath: 'second.m4a',
        ),
      ]);
      expect(engine.hints, ['Samlytics Conference 2026.', null]);
    },
  );

  test('FR-TRN-04 active recording blocks after-recording work', () async {
    await controller.setEnabled(true);
    await controller.install();
    held = true;
    await controller.transcribe([source]);
    expect(created, 0);
    expect(controller.message, contains('Save the current recording'));
  });

  test(
    'FR-TRN-06 Off cancels worker and preserves completed saved text',
    () async {
      await controller.setEnabled(true);
      await controller.install();
      await controller.transcribe([source]);
      expect(engine.disposals, 1);
      engine.gate = Completer<List<TranscriptSpan>>();
      final job = controller.transcribe([
        const TranscriptionSource(
          activityId: 'activity',
          segmentId: 'second',
          audioPath: 'second.m4a',
        ),
      ]);
      while (created < 2) {
        await Future<void>.delayed(Duration.zero);
      }
      await controller.setEnabled(false);
      await job;
      expect(engine.cancellations, 1);
      expect(controller.busy, isFalse);
      final saved = await controller.store.load(
        activityId: 'activity',
        segmentId: 'segment',
      );
      expect(
        saved.document?.machineSpans.single.text,
        'Samlytics Data Services',
      );
    },
  );

  test(
    'FR-TRN-07 model removal keeps original text and separate corrections',
    () async {
      await controller.setEnabled(true);
      await controller.install();
      await controller.transcribe([source]);
      await controller.correct(controller.documents.single, 0, 'Reviewed text');
      await controller.removeModel();
      expect(controller.enabled, isFalse);
      expect(models.removals, 1);
      final saved = await controller.store.load(
        activityId: 'activity',
        segmentId: 'segment',
      );
      expect(
        saved.document?.machineSpans.single.text,
        'Samlytics Data Services',
      );
      expect(saved.document?.textAt(0), 'Reviewed text');
    },
  );

  test('FR-TRN-08 retry uses saved output without overwriting original or repeating inference', () async {
    await controller.setEnabled(true);
    await controller.install();
    await controller.transcribe([source]);
    await controller.transcribe([source]);
    expect(created, 1);
    expect(
      controller.documents.single.machineSpans.single.text,
      'Samlytics Data Services',
    );
  });
  void replaceController({
    TranscriptStore? store,
    Future<void> Function(bool)? write,
  }) {
    controller.dispose();
    controller = TranscriptionController(
      models: models,
      store: store ?? TranscriptStore(directory),
      createEngine: () {
        created++;
        return engine;
      },
      writeEnabled: write ?? (_) async {},
      recordingHeld: () => held,
      enabled: true,
    )..installed = true;
    models.installed = true;
  }

  test('FR-TRN-06 Off refuses work synchronously while its setting write is pending', () async {
    final writeGate = Completer<void>();
    replaceController(write: (_) => writeGate.future);
    final off = controller.setEnabled(false);
    expect(controller.enabled, isFalse);
    await controller.transcribe([source]);
    await controller.install();
    expect(created, 0);
    expect(models.downloads, 0);
    writeGate.complete();
    await off;
  });

  test('FR-TRN-06 rapid toggles persist in intent order and refuse jobs until settled', () async {
    final gate = Completer<void>();
    final writes = <bool>[];
    replaceController(
      write: (value) async {
        writes.add(value);
        if (!value) await gate.future;
      },
    );
    final off = controller.setEnabled(false);
    final on = controller.setEnabled(true);
    expect(controller.enabled, isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(writes, [false]);
    await controller.transcribe([source]);
    expect(created, 0);
    gate.complete();
    await Future.wait([off, on]);
    expect(writes, [false, true]);
    expect(controller.enabled, isTrue);
    await controller.transcribe([source]);
    expect(created, 1);
  });

  for (final stopByOff in [true, false]) {
    test(
      'FR-TRN-04 inference cannot start after ${stopByOff ? 'Off' : 'recording'} arrives during transcript disk read',
      () async {
        final store = _GatedStore(directory)..gateLoad = true;
        replaceController(store: store);
        final job = controller.transcribe([source]);
        await store.entered.future;
        final stop = stopByOff
            ? controller.setEnabled(false)
            : Future<void>.value();
        if (!stopByOff) held = true;
        store.gate.complete();
        await Future.wait([job, stop]);
        expect(created, 0);
        expect(controller.busy, isFalse);
        expect(controller.message, contains('Stopped'));
      },
    );
  }

  test('FR-TRN-06 engine cancellation is immediate even when model cancellation waits', () async {
    replaceController();
    engine.gate = Completer<List<TranscriptSpan>>();
    final job = controller.transcribe([source]);
    while (created == 0) {
      await Future<void>.delayed(Duration.zero);
    }
    final gate = models.cancelGate = Completer<void>();
    final stopped = controller.setEnabled(false);
    expect(engine.cancellations, 1);
    await controller.transcribe([source]);
    expect(created, 1);
    gate.complete();
    await Future.wait([job, stopped]);
    expect(engine.disposals, 1);
  });

  test(
    'FR-TRN-06 model cancellation failure still cancels/releases the engine',
    () async {
      replaceController();
      engine.gate = Completer<List<TranscriptSpan>>();
      final job = controller.transcribe([source]);
      while (created == 0) {
        await Future<void>.delayed(Duration.zero);
      }
      models.failCancel = true;
      await expectLater(controller.cancel(), throwsStateError);
      await job;
      expect(engine.cancellations, 1);
      expect(engine.disposals, 1);
      models.failCancel = false;
    },
  );

  test('FR-TRN-06 Off during a completed text write retains visible durable output', () async {
    final store = _GatedStore(directory)..gateSave = true;
    replaceController(store: store);
    final job = controller.transcribe([source]);
    await store.saveEntered.future;
    final stopped = controller.setEnabled(false);
    store.saveGate.complete();
    await Future.wait([job, stopped]);
    expect(controller.documents.single.segmentId, 'segment');
    expect(
      (await store.load(activityId: 'activity', segmentId: 'segment')).state,
      TranscriptLoadState.ready,
    );
    expect(controller.enabled, isFalse);
  });

  test('FR-TRN-08 history survives new jobs and reloads in activity timestamp order', () async {
    replaceController();
    TranscriptDocument doc(String id, int seconds) => TranscriptDocument(
      activityId: 'activity',
      segmentId: id,
      segmentOffset: Duration(seconds: seconds),
      createdAt: DateTime.utc(2026),
      machineSpans: [
        TranscriptSpan(
          start: Duration.zero,
          end: const Duration(seconds: 1),
          text: 'Saved text',
        ),
      ],
    );
    await controller.store.saveOriginal(doc('a-later', 20));
    await controller.store.saveOriginal(doc('z-earlier', 0));
    await controller.refresh();
    expect(controller.documents.map((d) => d.segmentId), [
      'z-earlier',
      'a-later',
    ]);
    await controller.transcribe([
      const TranscriptionSource(
        activityId: 'activity',
        segmentId: 'middle',
        audioPath: 'synthetic.m4a',
        offset: Duration(seconds: 10),
      ),
    ]);
    expect(controller.documents.map((d) => d.segmentId), [
      'z-earlier',
      'middle',
      'a-later',
    ]);
    await controller.refresh();
    expect(controller.documents.map((d) => d.segmentId), [
      'z-earlier',
      'middle',
      'a-later',
    ]);
  });

  test('FR-TRN-08 concurrent corrections merge latest saved maps instead of stale UI snapshots', () async {
    replaceController();
    final doc = TranscriptDocument(
      activityId: 'activity',
      segmentId: 'segment',
      createdAt: DateTime.utc(2026),
      machineSpans: [
        for (var i = 0; i < 2; i++)
          TranscriptSpan(
            start: Duration(seconds: i),
            end: Duration(seconds: i + 1),
            text: 'Machine $i',
          ),
      ],
    );
    await controller.store.saveOriginal(doc);
    await controller.refresh();
    final stale = controller.documents.single;
    await Future.wait([
      controller.correct(stale, 0, 'First edit'),
      controller.correct(stale, 1, 'Second edit'),
    ]);
    expect(controller.documents.single.corrections, {
      0: 'First edit',
      1: 'Second edit',
    });
    expect(
      (await controller.store.load(
        activityId: 'activity',
        segmentId: 'segment',
      )).document!.corrections,
      {0: 'First edit', 1: 'Second edit'},
    );
    expect(controller.documents.single.machineSpans.first.text, 'Machine 0');
  });
}

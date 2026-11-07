import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/transcription/transcript_store.dart';
import '../../domain/transcription/transcript.dart';
import '../../domain/transcription/transcription_engine.dart';
import '../../domain/transcription/vocabulary_hint.dart';

/// App-owned model management; none of these operations run on app startup.
abstract interface class PilotModelManager {
  String get name;
  int get downloadBytes;
  String get directory;
  Future<bool> isInstalled();

  /// True when any model file is on disk, even if the set is incomplete, so
  /// the user can always remove what was downloaded [P2-11].
  Future<bool> hasFiles();
  Future<void> install(void Function(double) onProgress);
  Future<void> cancelInstall();
  Future<void> remove();
}

class TranscriptionSource {
  const TranscriptionSource({
    required this.activityId,
    required this.segmentId,
    required this.audioPath,
    this.offset = Duration.zero,
    this.hint,
  });
  final String activityId;
  final String segmentId;
  final String audioPath;
  final Duration offset;

  /// Session words for Whisper's prompt (see vocabularyHint), or null.
  final String? hint;
}

/// Explicit user jobs only. No engine is created by construction or enabling.
class TranscriptionController extends ChangeNotifier {
  TranscriptionController({
    required this.models,
    required this.store,
    required this.createEngine,
    required this.writeEnabled,
    required this.recordingHeld,
    this.enabled = false,
  });

  final PilotModelManager models;
  final TranscriptStore store;
  final TranscriptionEngine Function() createEngine;
  final Future<void> Function(bool) writeEnabled;
  final bool Function() recordingHeld;
  bool enabled;
  bool installed = false;

  /// Some model files are present (possibly not all of them).
  bool hasModelFiles = false;
  bool busy = false;
  double progress = 0;
  String? message;
  List<TranscriptDocument> documents = [];
  TranscriptionEngine? _engine;
  Future<void>? _operation;
  Future<void> _settingsWrites = Future<void>.value();
  Future<void> _correctionWrites = Future<void>.value();
  int _pendingSettings = 0;
  int _pendingCorrections = 0;
  int _settingIntent = 0;
  int _stopping = 0;
  bool _cancelled = false;
  bool _removing = false;
  bool _disposed = false;

  bool get _canStart =>
      !_disposed &&
      !busy &&
      !_removing &&
      _pendingSettings == 0 &&
      _pendingCorrections == 0 &&
      _stopping == 0;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _checkActive({bool inference = false}) {
    if (_disposed ||
        _cancelled ||
        !enabled ||
        _pendingSettings > 0 ||
        _stopping > 0 ||
        (inference && recordingHeld())) {
      throw const TranscriptionCancelledException();
    }
  }

  void _upsert(Iterable<TranscriptDocument> updates) {
    final indexed = <String, TranscriptDocument>{
      for (final doc in [...documents, ...updates])
        '${doc.activityId}/${doc.segmentId}': doc,
    };
    final sorted = indexed.values.toList()
      ..sort((a, b) {
        final activity = a.activityId.compareTo(b.activityId);
        if (activity != 0) return activity;
        final offset = a.segmentOffset.compareTo(b.segmentOffset);
        return offset != 0 ? offset : a.segmentId.compareTo(b.segmentId);
      });
    documents = List.unmodifiable(sorted);
    _notify();
  }

  Future<void> refresh() async {
    final present = await models.isInstalled();
    final files = await models.hasFiles();
    final saved = await store.listDocuments();
    if (_disposed) return;
    installed = present;
    hasModelFiles = files;
    _upsert(saved);
  }

  /// Re-reads saved transcripts of [activityIds] after a permanent trim or
  /// split moved them to other recordings (ADR-081): ones no longer saved
  /// under those activities leave the list.
  Future<void> reloadActivities(Set<String> activityIds) async {
    final saved = [
      for (final id in activityIds)
        ...await store.listDocuments(activityId: id),
    ];
    if (_disposed) return;
    documents = List.unmodifiable(
      documents.where((d) => !activityIds.contains(d.activityId)),
    );
    _upsert(saved);
  }

  Future<void> setEnabled(bool value) async {
    if (_disposed) return;
    if (value && _removing) {
      message =
          'Wait until model removal finishes before enabling transcription.';
      _notify();
      return;
    }
    // The latest user intent applies synchronously, before any disk/native wait.
    enabled = value;
    final intent = ++_settingIntent;
    _pendingSettings++;
    final previous = _settingsWrites;
    final released = Completer<void>();
    _settingsWrites = released.future;
    final stopping = value ? Future<void>.value() : cancel();
    _notify();
    try {
      // Register both futures immediately, even when the prior write is gated.
      await Future.wait<void>([
        () async {
          await previous;
          await writeEnabled(value);
        }(),
        stopping,
      ]);
    } on Object {
      if (intent == _settingIntent) {
        enabled = false;
        await cancel();
      }
      rethrow;
    } finally {
      released.complete();
      _pendingSettings--;
      _notify();
    }
  }

  Future<void> install() async {
    if (!_canStart || !enabled) return;
    try {
      await _run(() async {
        _checkActive();
        await models.install(_progress);
        _checkActive();
        final present = await models.isInstalled();
        _checkActive();
        installed = present;
        message = 'Model installed. Choose a recording to transcribe.';
      });
    } finally {
      // A failed or cancelled second download can leave the first file.
      final files = await models.hasFiles();
      if (!_disposed) {
        hasModelFiles = files;
        _notify();
      }
    }
  }

  Future<void> removeModel() async {
    if (_disposed || _removing) return;
    _removing = true;
    _notify();
    try {
      await setEnabled(false);
      await models.remove();
      installed = false;
      hasModelFiles = false;
      message = 'Model removed. Saved transcripts and recordings are kept.';
    } finally {
      _removing = false;
      _notify();
    }
  }

  Future<void> transcribe(List<TranscriptionSource> sources) async {
    if (!_canStart) return;
    if (!enabled || !installed) {
      message = 'Enable transcription and install its model first.';
      _notify();
      return;
    }
    if (recordingHeld()) {
      message = 'Save the current recording before transcribing.';
      _notify();
      return;
    }
    if (sources.isEmpty) {
      message = 'No saved audio is available to transcribe.';
      _notify();
      return;
    }
    // Caller mutation cannot change an in-flight explicit request.
    final requested = List<TranscriptionSource>.of(sources);
    await _run(() async {
      for (var index = 0; index < requested.length; index++) {
        _checkActive(inference: true);
        final source = requested[index];
        final saved = await store.load(
          activityId: source.activityId,
          segmentId: source.segmentId,
        );
        // Off or capture can arrive while the disk read is pending.
        _checkActive(inference: true);
        if (saved.document != null) {
          _upsert([saved.document!]);
          continue;
        }
        if (saved.state != TranscriptLoadState.missing) {
          throw StateError('Saved transcript could not be read; it was kept.');
        }
        final engine = _engine = createEngine();
        try {
          final spans = await engine.transcribe(
            audioPath: source.audioPath,
            modelDirectory: models.directory,
            onProgress: (value) =>
                _progress((index + value) / requested.length),
          );
          _checkActive(inference: true);
          if (spans.isEmpty) {
            message = 'No speech was recognised in this recording.';
            continue;
          }
          final document = TranscriptDocument(
            activityId: source.activityId,
            segmentId: source.segmentId,
            machineSpans: spans,
            createdAt: DateTime.now().toUtc(),
            segmentOffset: source.offset,
            modelId: models.name,
          );
          var persisted = await store.saveOriginal(document);
          // Misheard session names are fixed as corrections, so the machine
          // text stays as heard and reverting a line restores it (FR-TRN-08).
          final names = {
            for (final (i, span) in spans.indexed)
              if (correctNames(span.text, source.hint) case final fixed
                  when fixed != span.text)
                i: fixed,
          };
          if (names.isNotEmpty && persisted.corrections.isEmpty) {
            persisted = await store.saveCorrections(
              activityId: source.activityId,
              segmentId: source.segmentId,
              corrections: names,
            );
          }
          // A completed atomic write remains visible even if Off arrived during it.
          _upsert([persisted]);
          _checkActive(inference: true);
        } finally {
          try {
            await engine.dispose();
          } finally {
            if (identical(_engine, engine)) _engine = null;
          }
        }
      }
      if (!_cancelled && documents.isNotEmpty) {
        message = 'Transcript saved. Review it for recognition errors.';
      }
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    busy = true;
    progress = 0;
    message = null;
    _cancelled = false;
    _notify();
    final operation = _operation = () async {
      try {
        await action();
      } on TranscriptionCancelledException {
        message = 'Stopped. Completed text and original audio are kept.';
      } on Object {
        message =
            'Transcription could not finish. Your audio and saved text '
            'are kept. Check model storage and try again.';
      } finally {
        busy = false;
        _notify();
      }
    }();
    await operation;
    if (identical(_operation, operation)) _operation = null;
  }

  void _progress(double value) {
    if (_cancelled || !value.isFinite || _disposed) return;
    progress = value.clamp(0, 1);
    _notify();
  }

  Future<void> cancel() async {
    _cancelled = true;
    _stopping++;
    final engine = _engine;
    final operation = _operation;
    try {
      // Do not let a slow/failing model cancellation delay engine cancellation.
      await Future.wait<void>([
        if (engine != null) Future<void>.sync(engine.cancel),
        Future<void>.sync(models.cancelInstall),
      ]);
    } finally {
      try {
        await operation;
      } finally {
        _stopping--;
        _notify();
      }
    }
  }

  Future<void> correct(
    TranscriptDocument document,
    int index,
    String text,
  ) async {
    if (_disposed || busy || _removing) return;
    final previous = _correctionWrites;
    final released = Completer<void>();
    _correctionWrites = released.future;
    _pendingCorrections++;
    try {
      await previous;
      // Read only after prior edits complete; the UI document may be stale.
      final loaded = await store.load(
        activityId: document.activityId,
        segmentId: document.segmentId,
      );
      if (loaded.document == null) {
        throw StateError('Original transcript is unavailable');
      }
      final values = {...loaded.document!.corrections, index: text};
      final saved = await store.saveCorrections(
        activityId: document.activityId,
        segmentId: document.segmentId,
        corrections: values,
      );
      _upsert([saved]);
    } finally {
      _pendingCorrections--;
      released.complete();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

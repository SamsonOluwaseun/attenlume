import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../storage/free_space_probe.dart';
import 'transcription_exceptions.dart';

/// Metadata for a verified Whisper GGML model.
class WhisperModelDescriptor {
  const WhisperModelDescriptor({
    required this.id,
    required this.name,
    required this.sizeBytes,
    required this.language,
    required this.sha256,
    required this.downloadUrl,
  });

  /// Official model identifier (matches whisper.cpp naming convention).
  final String id;

  /// Human-readable model description.
  final String name;

  /// Exact file size in bytes expected from official repository.
  final int sizeBytes;

  /// Supported language code ('en' for English-only, 'multilingual' for multi-language).
  final String language;

  /// SHA-256 hex checksum.
  final String sha256;

  /// Official download URL (e.g. Hugging Face whisper.cpp repository).
  final String downloadUrl;

  /// Parsed download URI.
  Uri get downloadUri => Uri.parse(downloadUrl);

  /// Expected file name on disk.
  String get fileName => 'ggml-$id.bin';

  /// Human-readable size string.
  String get sizeLabel {
    const mebibyte = 1024 * 1024;
    return '${(sizeBytes / mebibyte).toStringAsFixed(1)} MiB';
  }

  /// Package verified tiny English quantized model (~30.68 MiB).
  static const tinyEnQ5_1 = WhisperModelDescriptor(
    id: 'tiny.en-q5_1',
    name: 'Tiny English (quantized, ~31 MiB)',
    sizeBytes: 32166155,
    language: 'en',
    sha256: 'c77c5766f1cef09b6b7d47f21b546cbddd4157886b3b5d6d4f709e91e66c7c2b',
    downloadUrl: 'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.en-q5_1.bin',
  );

  /// Package verified tiny multilingual quantized model (~30.66 MiB).
  static const tinyQ5_1 = WhisperModelDescriptor(
    id: 'tiny-q5_1',
    name: 'Tiny Multilingual (quantized, ~31 MiB)',
    sizeBytes: 32152673,
    language: 'multilingual',
    sha256: '818710568da3ca15689e31a743197b520007872ff9576237bda97bd1b469c3d7',
    downloadUrl: 'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny-q5_1.bin',
  );

  /// Default model for speech transcription.
  static const defaultModel = tinyEnQ5_1;

  /// Verified catalog of offline models.
  static const List<WhisperModelDescriptor> verifiedCatalog = [
    tinyEnQ5_1,
    tinyQ5_1,
  ];
}

/// App-managed storage and explicit lifecycle manager for Whisper GGML models.
///
/// Models are never downloaded automatically. Explicit user request triggers
/// free-space preflight, atomic streamed download to `.part`, checksum verification,
/// and safe cancellation/retry without deleting recordings or user transcripts.
class WhisperModelStore {
  WhisperModelStore({
    required this.baseDirectory,
    FreeSpaceProbe? freeSpaceProbe,
    HttpClient Function()? httpClientFactory,
    this.safetyReserveBytes = 50 * 1024 * 1024,
  }) : _freeSpaceProbe = freeSpaceProbe ?? FreeSpaceProbe.forPlatform(),
       _httpClientFactory = httpClientFactory ?? HttpClient.new;
  final Directory baseDirectory;
  final FreeSpaceProbe _freeSpaceProbe;
  final HttpClient Function() _httpClientFactory;
  final int safetyReserveBytes;
  final Map<String, _InFlightDownload> _inFlight = {};
  final Set<String> _removing = {};
  Directory get modelDirectory => baseDirectory;

  void _validate(WhisperModelDescriptor descriptor) {
    if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$').hasMatch(descriptor.id) ||
        descriptor.id.contains('..') ||
        descriptor.id.endsWith('.') ||
        descriptor.sizeBytes <= 0 ||
        descriptor.sizeBytes > 128 * 1024 * 1024 ||
        !RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(descriptor.sha256) ||
        descriptor.downloadUri.scheme != 'https' ||
        descriptor.downloadUri.host.isEmpty ||
        descriptor.downloadUri.userInfo.isNotEmpty ||
        safetyReserveBytes < 0) {
      throw const WhisperStorageException('Unsafe model descriptor.');
    }
    var directory = baseDirectory.absolute;
    while (true) {
      final type = FileSystemEntity.typeSync(
        directory.path,
        followLinks: false,
      );
      if (type != FileSystemEntityType.notFound &&
          type != FileSystemEntityType.directory) {
        throw const WhisperStorageException(
          'Model storage must not contain directory links.',
        );
      }
      if (directory.parent.path == directory.path) break;
      directory = directory.parent;
    }
  }

  File _target(WhisperModelDescriptor descriptor) {
    _validate(descriptor);
    final file = File(
      '${baseDirectory.path}${Platform.pathSeparator}${descriptor.fileName}',
    );
    for (final candidate in [file, File('${file.path}.sha256')]) {
      final type = FileSystemEntity.typeSync(
        candidate.path,
        followLinks: false,
      );
      if (type != FileSystemEntityType.notFound &&
          type != FileSystemEntityType.file) {
        throw const WhisperStorageException(
          'Model asset must be a regular file, never a link.',
        );
      }
    }
    return file;
  }

  Future<String?> installedPath(WhisperModelDescriptor descriptor) async {
    final file = _target(descriptor);
    if (!file.existsSync() || file.lengthSync() != descriptor.sizeBytes) {
      return null;
    }
    // The marker is never evidence of model contents; hash actual bytes.
    final digest = await sha256.bind(file.openRead()).first;
    _target(descriptor);
    return digest.toString().toLowerCase() == descriptor.sha256.toLowerCase()
        ? file.path
        : null;
  }

  Future<String> install(
    WhisperModelDescriptor descriptor, {
    void Function(double)? onProgress,
  }) {
    _validate(descriptor);
    if (_removing.contains(descriptor.id)) {
      throw StateError('Model removal is still in progress.');
    }
    final current = _inFlight[descriptor.id];
    if (current != null) return current.future;
    final job = _InFlightDownload(descriptor);
    _inFlight[descriptor.id] =
        job; // Reserve before any asynchronous preflight.
    return job.future = _install(job, onProgress);
  }

  Future<String> _install(
    _InFlightDownload job,
    void Function(double)? onProgress,
  ) async {
    Directory? temporary;
    RandomAccessFile? output;
    try {
      baseDirectory.createSync(recursive: true);
      final existing = await installedPath(job.descriptor);
      _check(job);
      if (existing != null) {
        onProgress?.call(1);
        return existing;
      }
      final space = await _freeSpaceProbe.query(baseDirectory.path);
      _check(job);
      if (space == null ||
          space.availableBytes <
              job.descriptor.sizeBytes + safetyReserveBytes) {
        throw const WhisperStorageException(
          'Insufficient disk space or storage could not be verified.',
        );
      }
      final target = _target(job.descriptor);
      temporary = baseDirectory.createTempSync('.model-download-');
      final part = File('${temporary.path}${Platform.pathSeparator}model.part');
      final client = job.client = _httpClientFactory();
      client.connectionTimeout = const Duration(seconds: 30);
      final request = job.request = await client.getUrl(
        job.descriptor.downloadUri,
      );
      _check(job);
      final response = await request.close();
      _check(job);
      if (response.statusCode != HttpStatus.ok ||
          (response.contentLength >= 0 &&
              response.contentLength != job.descriptor.sizeBytes)) {
        throw const WhisperStorageException(
          'Model download response has an unexpected status or length.',
        );
      }
      Digest? digest;
      final sink = sha256.startChunkedConversion(
        ChunkedConversionSink<Digest>.withCallback((values) {
          digest = values.single;
        }),
      );
      output = await part.open(mode: FileMode.writeOnly);
      var received = 0;
      onProgress?.call(0);
      await for (final chunk in response.timeout(const Duration(seconds: 30))) {
        _check(job);
        received += chunk.length;
        if (received > job.descriptor.sizeBytes) {
          throw const WhisperStorageException(
            'Downloaded model exceeds its expected size.',
          );
        }
        sink.add(chunk);
        await output.writeFrom(chunk);
        _check(job);
        onProgress?.call(received / job.descriptor.sizeBytes);
      }
      sink.close();
      await output.flush();
      await output.close();
      output = null;
      _check(job);
      if (received != job.descriptor.sizeBytes ||
          digest.toString().toLowerCase() !=
              job.descriptor.sha256.toLowerCase()) {
        throw const WhisperStorageException(
          'Model size or SHA-256 verification failed.',
        );
      }
      _target(job.descriptor);
      part.renameSync(
        target.path,
      ); // Atomic replace; never delete the old model first.
      File('${target.path}.sha256')
          .writeAsStringSync(job.descriptor.sha256, flush: true);
      onProgress?.call(1);
      return target.path;
    } finally {
      job.client?.close(force: true);
      if (output != null) await output.close();
      if (temporary != null && temporary.existsSync()) {
        temporary.deleteSync(recursive: true);
      }
      if (identical(_inFlight[job.descriptor.id], job)) {
        _inFlight.remove(job.descriptor.id);
      }
    }
  }

  void _check(_InFlightDownload job) {
    if (job.cancelled) {
      throw const WhisperStorageException('Model installation cancelled.');
    }
  }

  Future<void> cancelInstall({String? modelId}) async {
    final targets = _inFlight.values
        .where((job) => modelId == null || job.descriptor.id == modelId)
        .toList();
    for (final job in targets) {
      job.cancelled = true;
      job.request?.abort();
      job.client?.close(force: true);
    }
    // Cancellation resolves only after writer/stream/temp cleanup has drained.
    await Future.wait(
      targets.map(
        (job) =>
            job.future.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
      ),
    );
  }

  Future<bool> remove(WhisperModelDescriptor descriptor) async {
    _validate(descriptor);
    if (!_removing.add(descriptor.id)) {
      throw StateError('Model removal is still in progress.');
    }
    try {
      await cancelInstall(modelId: descriptor.id);
      final file = _target(descriptor);
      var deleted = false;
      if (file.existsSync()) {
        file.deleteSync();
        deleted = true;
      }
      final marker = File('${file.path}.sha256');
      if (marker.existsSync()) marker.deleteSync();
      return deleted;
    } finally {
      _removing.remove(descriptor.id);
    }
  }

  Future<int> installedBytes(WhisperModelDescriptor descriptor) async {
    final file = _target(descriptor);
    return file.existsSync() ? file.lengthSync() : 0;
  }
}

class _InFlightDownload {
  _InFlightDownload(this.descriptor);
  final WhisperModelDescriptor descriptor;
  late Future<String> future;
  HttpClient? client;
  // The owning client force-aborts unfinished requests in _install finally.
  // ignore: close_sinks
  HttpClientRequest? request;
  bool cancelled = false;
}

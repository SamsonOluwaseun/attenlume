import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';

import 'free_space_probe.dart';

/// Base metadata for a verified downloadable model asset.
class VerifiedModelDescriptor {
  const VerifiedModelDescriptor({
    required this.id,
    required this.name,
    required this.sizeBytes,
    required this.sha256,
    required this.downloadUrl,
    required this.fileName,
    this.maxSizeBytes,
  });

  /// Unique model identifier (safe file naming slug).
  final String id;

  /// Human-readable model description.
  final String name;

  /// Exact file size in bytes expected from the repository.
  final int sizeBytes;

  /// SHA-256 hex checksum.
  final String sha256;

  /// Official HTTPS download URL.
  final String downloadUrl;

  /// Expected file name on disk.
  final String fileName;

  /// Optional upper bound on accepted model size.
  final int? maxSizeBytes;

  /// Parsed download URI.
  Uri get downloadUri => Uri.parse(downloadUrl);
}

/// Thrown when model storage, download or integrity verification fails.
class ModelStorageException implements Exception {
  const ModelStorageException(this.message);
  final String message;

  @override
  String toString() => 'ModelStorageException: $message';
}

/// Shared app-managed storage and lifecycle manager for verified models.
///
/// Features:
/// - Explicit opt-in download only (never downloads on app startup).
/// - Free-space preflight probe with safety reserve margin.
/// - Atomic download to a temporary `.part` file in an isolated directory.
/// - In-flight SHA-256 streaming verification.
/// - Clean cancellation draining and resource disposal.
/// - Rejection of directory and file links.
class VerifiedModelStore {
  VerifiedModelStore({
    required this.baseDirectory,
    FreeSpaceProbe? freeSpaceProbe,
    HttpClient Function()? httpClientFactory,
    this.safetyReserveBytes = 50 * 1024 * 1024,
    Exception Function(String message)? exceptionFactory,
  }) : _freeSpaceProbe = freeSpaceProbe ?? FreeSpaceProbe.forPlatform(),
       _httpClientFactory = httpClientFactory ?? HttpClient.new,
       _exceptionFactory = exceptionFactory ?? ModelStorageException.new;

  final Directory baseDirectory;
  final FreeSpaceProbe _freeSpaceProbe;
  final HttpClient Function() _httpClientFactory;
  final int safetyReserveBytes;
  final Exception Function(String message) _exceptionFactory;

  final Map<String, _InFlightDownload> _inFlight = {};
  final Set<String> _removing = {};

  Exception _createException(String message) => _exceptionFactory(message);

  void validate(VerifiedModelDescriptor descriptor) {
    final maxAllowed = descriptor.maxSizeBytes ?? (10 * 1024 * 1024 * 1024);
    if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$').hasMatch(descriptor.id) ||
        descriptor.id.contains('..') ||
        descriptor.id.endsWith('.') ||
        descriptor.sizeBytes <= 0 ||
        descriptor.sizeBytes > maxAllowed ||
        !RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(descriptor.sha256) ||
        descriptor.downloadUri.scheme != 'https' ||
        descriptor.downloadUri.host.isEmpty ||
        descriptor.downloadUri.userInfo.isNotEmpty ||
        safetyReserveBytes < 0) {
      throw _createException('Unsafe model descriptor.');
    }
    var directory = baseDirectory.absolute;
    while (true) {
      final type = FileSystemEntity.typeSync(
        directory.path,
        followLinks: false,
      );
      if (type != FileSystemEntityType.notFound &&
          type != FileSystemEntityType.directory) {
        throw _createException(
          'Model storage must not contain directory links.',
        );
      }
      if (directory.parent.path == directory.path) break;
      directory = directory.parent;
    }
  }

  File targetFile(VerifiedModelDescriptor descriptor) {
    validate(descriptor);
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
        throw _createException(
          'Model asset must be a regular file, never a link.',
        );
      }
    }
    return file;
  }

  /// Cheap installed check for Settings: trusts the download's checksum marker
  /// and checks exact length, without reading model contents.
  ///
  /// Call [verifyInstalledPath] before first loading a model when full integrity
  /// re-verification is required; this check cannot detect same-size tampering.
  Future<String?> installedPath(VerifiedModelDescriptor descriptor) async {
    final file = targetFile(descriptor);
    final marker = File('${file.path}.sha256');
    if (!file.existsSync() ||
        file.lengthSync() != descriptor.sizeBytes ||
        !marker.existsSync() ||
        marker.lengthSync() != 64) {
      return null;
    }
    return marker.readAsStringSync().toLowerCase() ==
            descriptor.sha256.toLowerCase()
        ? file.path
        : null;
  }

  /// Explicitly hashes the real bytes in a worker isolate using a file stream.
  /// Returns null and removes corrupt/partial model data and its marker on a
  /// size or checksum mismatch. No model contents are read on the UI isolate.
  Future<String?> verifyInstalledPath(
    VerifiedModelDescriptor descriptor,
  ) async {
    final file = targetFile(descriptor);
    if (!file.existsSync()) return null;
    final path = file.path;
    final expectedSize = descriptor.sizeBytes;
    final expectedHash = descriptor.sha256.toLowerCase();
    final valid = await Isolate.run(() async {
      final model = File(path);
      if (await model.length() != expectedSize) return false;
      final digest = await sha256.bind(model.openRead()).first;
      return digest.toString().toLowerCase() == expectedHash;
    });
    targetFile(descriptor);
    if (!valid) {
      await remove(descriptor);
      return null;
    }
    File('$path.sha256').writeAsStringSync(descriptor.sha256, flush: true);
    return path;
  }

  /// Explicitly downloads and verifies [descriptor], reporting progress in [0, 1].
  Future<String> install(
    VerifiedModelDescriptor descriptor, {
    void Function(double)? onProgress,
  }) {
    validate(descriptor);
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
        throw _createException(
          'Insufficient disk space or storage could not be verified.',
        );
      }
      final target = targetFile(job.descriptor);
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
        throw _createException(
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
          throw _createException('Downloaded model exceeds its expected size.');
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
        throw _createException('Model size or SHA-256 verification failed.');
      }
      targetFile(job.descriptor);
      part.renameSync(
        target.path,
      ); // Atomic replace; never delete the old model first.
      File('${target.path}.sha256')
          .writeAsStringSync(job.descriptor.sha256, flush: true);
      onProgress?.call(1);
      return target.path;
    } catch (e) {
      if (job.cancelled) {
        throw _createException('Model installation cancelled.');
      }
      rethrow;
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
      throw _createException('Model installation cancelled.');
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

  Future<bool> remove(VerifiedModelDescriptor descriptor) async {
    validate(descriptor);
    if (!_removing.add(descriptor.id)) {
      throw StateError('Model removal is still in progress.');
    }
    try {
      await cancelInstall(modelId: descriptor.id);
      final file = targetFile(descriptor);
      var deleted = false;
      if (file.existsSync()) {
        try {
          file.deleteSync();
        } on FileSystemException {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          if (file.existsSync()) file.deleteSync();
        }
        deleted = true;
      }
      final marker = File('${file.path}.sha256');
      if (marker.existsSync()) {
        try {
          marker.deleteSync();
        } on FileSystemException {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          if (marker.existsSync()) marker.deleteSync();
        }
      }
      return deleted;
    } finally {
      _removing.remove(descriptor.id);
    }
  }

  Future<int> installedBytes(VerifiedModelDescriptor descriptor) async {
    final file = targetFile(descriptor);
    return file.existsSync() ? file.lengthSync() : 0;
  }
}

class _InFlightDownload {
  _InFlightDownload(this.descriptor);
  final VerifiedModelDescriptor descriptor;
  late Future<String> future;
  HttpClient? client;
  // The owning client force-aborts unfinished requests in _install finally.
  // ignore: close_sinks
  HttpClientRequest? request;
  bool cancelled = false;
}

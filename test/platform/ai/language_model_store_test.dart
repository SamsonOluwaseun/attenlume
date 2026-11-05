import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:attenlume/platform/ai/language_model_store.dart';
import 'package:attenlume/platform/storage/free_space_probe.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeFreeSpaceProbe implements FreeSpaceProbe {
  _FakeFreeSpaceProbe(this.freeBytes);
  int freeBytes;

  @override
  Future<FreeSpace?> query(String path) async {
    return FreeSpace(availableBytes: freeBytes, totalBytes: freeBytes * 2);
  }
}

class _Response extends Stream<List<int>> implements HttpClientResponse {
  _Response(this.source, this.contentLength);
  final Stream<List<int>> source;
  @override
  final int contentLength;
  @override
  int get statusCode => HttpStatus.ok;
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => source.listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Request extends Fake implements HttpClientRequest {
  _Request(this.response, {this.abortStream});
  final _Response response;
  final StreamController<List<int>>? abortStream;
  @override
  Future<HttpClientResponse> close() async => response;
  @override
  void abort([Object? exception, StackTrace? stackTrace]) {
    if (abortStream != null && !abortStream!.isClosed) {
      abortStream!.addError(const HttpException('Synthetic cancellation'));
      unawaited(abortStream!.close());
    }
  }
}

class _Client extends Fake implements HttpClient {
  _Client(this.request);
  final _Request request;
  @override
  set connectionTimeout(Duration? value) {}
  @override
  Future<HttpClientRequest> getUrl(Uri url) async => request;
  @override
  void close({bool force = false}) {
    if (force) request.abort();
  }
}

void main() {
  late Directory tempDir;
  late LanguageModelDescriptor testDescriptor;
  late Uint8List testModelBytes;
  late String testSha256;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('ai_model_store_test_');
    testModelBytes = Uint8List.fromList(
      utf8.encode('mock-gemma-gguf-model-bytes-12345'),
    );
    testSha256 = sha256.convert(testModelBytes).toString();
    testDescriptor = LanguageModelDescriptor(
      id: 'test-llm',
      name: 'Test Language Model',
      sizeBytes: testModelBytes.length,
      sha256: testSha256,
      downloadUrl: 'https://example.com/models/test-llm.gguf',
      fileName: 'test-llm.gguf',
      licence: 'Apache 2.0',
      deviceNotice: 'Runs on this device. Nothing you record is sent anywhere.',
    );
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('P3-10 FR-AI-01: LanguageModelDescriptor', () {
    test('pinned Gemma 4 E2B IT has exact URL, size, SHA-256 and notice', () {
      const desc = LanguageModelDescriptor.gemma4E2B;
      expect(desc.id, 'gemma-4-E2B-it-Q4_0');
      expect(desc.name, 'Gemma 4 E2B, Fast');
      expect(desc.sizeBytes, 2841481184);
      expect(desc.sizeLabel, '2.65 GB');
      expect(
        desc.sha256,
        '8e30dff3ac4c8434c49a7036fa15564bdbb6044e42bf04550bf1a096ad7e6a52',
      );
      expect(
        desc.downloadUrl,
        'https://huggingface.co/ggml-org/gemma-4-E2B-it-GGUF/resolve/6938c58e698502037401a5f19f6905f2fb2f7dee/gemma-4-E2B-it-Q4_0.gguf',
      );
      expect(desc.fileName, 'gemma-4-E2B-it-Q4_0.gguf');
      expect(desc.licence, 'Apache 2.0');
      expect(
        desc.deviceNotice,
        'Runs on this device. Nothing you record is sent anywhere.',
      );
      expect(LanguageModelDescriptor.defaultModel, equals(desc));
    });
  });

  group('P3-10 FR-AI-01: LanguageModelStore operations', () {
    test('installedPath returns null when model not present', () async {
      final store = LanguageModelStore(baseDirectory: tempDir);
      final path = await store.installedPath(testDescriptor);
      expect(path, isNull);
    });

    test('installedPath returns null when size does not match', () async {
      final store = LanguageModelStore(baseDirectory: tempDir);
      final file = File(
        '${tempDir.path}${Platform.pathSeparator}${testDescriptor.fileName}',
      );
      file.writeAsBytesSync([1, 2, 3]); // Wrong size
      File('${file.path}.sha256').writeAsStringSync(testSha256);
      final path = await store.installedPath(testDescriptor);
      expect(path, isNull);
    });

    test(
      'FR-AI-01 installedPath returns path with expected marker and size',
      () async {
        final store = LanguageModelStore(baseDirectory: tempDir);
        final file = File(
          '${tempDir.path}${Platform.pathSeparator}${testDescriptor.fileName}',
        );
        file.writeAsBytesSync(testModelBytes);
        final marker = File('${file.path}.sha256');
        marker.writeAsStringSync(testSha256);

        final path = await store.installedPath(testDescriptor);
        expect(path, equals(file.path));
        expect(await store.verifyInstalledPath(testDescriptor), file.path);
      },
    );

    test('FR-AI-01 cheap check skips contents; full verification removes same-size corruption', () async {
      final store = LanguageModelStore(baseDirectory: tempDir);
      final file = File(
        '${tempDir.path}${Platform.pathSeparator}${testDescriptor.fileName}',
      );
      file.writeAsBytesSync(
        Uint8List(testModelBytes.length),
      ); // Same length, wrong content
      File('${file.path}.sha256').writeAsStringSync(testSha256);

      final path = await store.installedPath(testDescriptor);
      expect(path, file.path);
      expect(await store.verifyInstalledPath(testDescriptor), isNull);
      expect(file.existsSync(), isFalse);
      expect(File('${file.path}.sha256').existsSync(), isFalse);
      expect(await store.installedPath(testDescriptor), isNull);
    });

    test('FR-AI-01 cheap check requires the expected marker', () async {
      final store = LanguageModelStore(baseDirectory: tempDir);
      final file = store.targetFile(testDescriptor);
      file.writeAsBytesSync(testModelBytes);
      expect(await store.installedPath(testDescriptor), isNull);
      File('${file.path}.sha256').writeAsStringSync('0' * 64);
      expect(await store.installedPath(testDescriptor), isNull);
    });

    test(
      'FR-AI-01 full verification removes wrong-size partial files',
      () async {
        final store = LanguageModelStore(baseDirectory: tempDir);
        final file = store.targetFile(testDescriptor);
        file.writeAsBytesSync([1, 2, 3]);
        File('${file.path}.sha256').writeAsStringSync(testSha256);
        expect(await store.verifyInstalledPath(testDescriptor), isNull);
        expect(file.existsSync(), isFalse);
        expect(File('${file.path}.sha256').existsSync(), isFalse);
      },
    );

    test('preflight fails when free space is less than model size plus 1 GB warning margin', () async {
      // Less than model size + 1 GB
      final probe = _FakeFreeSpaceProbe(1024 * 1024);
      final store = LanguageModelStore(
        baseDirectory: tempDir,
        freeSpaceProbe: probe,
        safetyReserveBytes: 1024 * 1024 * 1024,
      );

      expect(
        () => store.install(testDescriptor),
        throwsA(
          isA<ModelStorageException>().having(
            (e) => e.message,
            'message',
            contains('Insufficient disk space'),
          ),
        ),
      );
    });

    test(
      'streamed download verifies hash and atomically renames to target',
      () async {
        _Client client(List<int> bytes) =>
            _Client(_Request(_Response(Stream.value(bytes), bytes.length)));
        final store = LanguageModelStore(
          baseDirectory: tempDir,
          freeSpaceProbe: _FakeFreeSpaceProbe(4 * 1024 * 1024 * 1024),
          httpClientFactory: () => client(testModelBytes),
        );

        final progressValues = <double>[];
        final installed = await store.install(
          testDescriptor,
          onProgress: progressValues.add,
        );

        expect(installed, contains(testDescriptor.fileName));
        expect(File(installed).existsSync(), isTrue);
        expect(await File(installed).readAsBytes(), testModelBytes);
        expect(File('$installed.sha256').existsSync(), isTrue);
        expect(await File('$installed.sha256').readAsString(), testSha256);
        expect(progressValues, contains(1.0));
      },
    );

    test('hash mismatch deletes the partial and reports it with ModelStorageException', () async {
      final badBytes = Uint8List(testModelBytes.length); // Mismatched SHA
      _Client client(List<int> bytes) =>
          _Client(_Request(_Response(Stream.value(bytes), bytes.length)));
      final store = LanguageModelStore(
        baseDirectory: tempDir,
        freeSpaceProbe: _FakeFreeSpaceProbe(4 * 1024 * 1024 * 1024),
        httpClientFactory: () => client(badBytes),
      );

      await expectLater(
        store.install(testDescriptor),
        throwsA(
          isA<ModelStorageException>().having(
            (e) => e.message,
            'message',
            contains('Model size or SHA-256 verification failed'),
          ),
        ),
      );

      // No partial downloads or orphaned directories remain
      expect(tempDir.listSync().whereType<Directory>(), isEmpty);
      expect(
        File(
          '${tempDir.path}${Platform.pathSeparator}${testDescriptor.fileName}',
        ).existsSync(),
        isFalse,
      );
    });

    test(
      'cancellation aborts stream, drains and deletes partial file',
      () async {
        // ignore: close_sinks
        final stream = StreamController<List<int>>();
        final started = Completer<void>();
        // ignore: close_sinks
        final request = _Request(
          _Response(stream.stream, testModelBytes.length),
          abortStream: stream,
        );
        final store = LanguageModelStore(
          baseDirectory: tempDir,
          freeSpaceProbe: _FakeFreeSpaceProbe(4 * 1024 * 1024 * 1024),
          httpClientFactory: () => _Client(request),
        );

        final job = store.install(
          testDescriptor,
          onProgress: (v) {
            if (v == 0 && !started.isCompleted) started.complete();
          },
        );

        final expected = expectLater(
          job,
          throwsA(
            isA<ModelStorageException>().having(
              (e) => e.message,
              'message',
              contains('cancelled'),
            ),
          ),
        );

        await started.future;
        stream.add(testModelBytes.sublist(0, 5));
        await store.cancelInstall();
        await expected;

        expect(tempDir.listSync(), isEmpty);
      },
    );

    test('delete removes model file and .sha256 marker without touching other files', () async {
      final store = LanguageModelStore(baseDirectory: tempDir);
      final modelFile = File(
        '${tempDir.path}${Platform.pathSeparator}${testDescriptor.fileName}',
      );
      modelFile.writeAsBytesSync(testModelBytes);
      final markerFile = File('${modelFile.path}.sha256');
      markerFile.writeAsStringSync(testSha256);

      // Other unrelated file
      final otherFile = File(
        '${tempDir.path}${Platform.pathSeparator}notes.txt',
      );
      otherFile.writeAsStringSync('Samlytics Conference 2026 notes');

      final deleted = await store.remove(testDescriptor);
      expect(deleted, isTrue);
      expect(modelFile.existsSync(), isFalse);
      expect(markerFile.existsSync(), isFalse);
      expect(otherFile.existsSync(), isTrue);
    });

    test('unsafe descriptor IDs are rejected before any file access', () async {
      final store = LanguageModelStore(baseDirectory: tempDir);
      for (final unsafeId in [
        '../../outside',
        r'..\outside',
        '/root',
        'invalid.',
        'a..b',
      ]) {
        final unsafeDesc = LanguageModelDescriptor(
          id: unsafeId,
          name: 'Unsafe',
          sizeBytes: 10,
          sha256: testSha256,
          downloadUrl: 'https://example.com/model.gguf',
          fileName: 'model.gguf',
          licence: 'Apache 2.0',
          deviceNotice: 'Notice',
        );

        await expectLater(
          store.installedPath(unsafeDesc),
          throwsA(isA<ModelStorageException>()),
        );
        await expectLater(
          store.remove(unsafeDesc),
          throwsA(isA<ModelStorageException>()),
        );
      }
    });
  });
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:attenlume/platform/storage/free_space_probe.dart';
import 'package:attenlume/platform/transcription/transcription_exceptions.dart';
import 'package:attenlume/platform/transcription/whisper_model_store.dart';
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

class _GateProbe implements FreeSpaceProbe {
  final entered = Completer<void>();
  final gate = Completer<FreeSpace?>();
  @override
  Future<FreeSpace?> query(String path) {
    entered.complete();
    return gate.future;
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
  late WhisperModelDescriptor testDescriptor;
  late Uint8List testModelBytes;
  late String testSha256;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('model_store_test_');
    testModelBytes = Uint8List.fromList(
      utf8.encode('mock-ggml-model-bytes-12345'),
    );
    testSha256 = sha256.convert(testModelBytes).toString();
    testDescriptor = WhisperModelDescriptor(
      id: 'test-model',
      name: 'Test Model (~31 MiB)',
      sizeBytes: testModelBytes.length,
      language: 'en',
      sha256: testSha256,
      downloadUrl: 'https://example.com/models/test-model.bin',
    );
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('WhisperModelDescriptor', () {
    test(
      'verified catalog has tiny English and Multilingual quantized models',
      () {
        expect(WhisperModelDescriptor.verifiedCatalog.length, 2);
        expect(WhisperModelDescriptor.tinyEnQ5_1.id, 'tiny.en-q5_1');
        expect(WhisperModelDescriptor.tinyEnQ5_1.sizeBytes, 32166155);
        expect(WhisperModelDescriptor.tinyEnQ5_1.language, 'en');
        expect(WhisperModelDescriptor.tinyEnQ5_1.sizeLabel, '30.7 MiB');

        expect(WhisperModelDescriptor.tinyQ5_1.id, 'tiny-q5_1');
        expect(WhisperModelDescriptor.tinyQ5_1.sizeBytes, 32152673);
        expect(WhisperModelDescriptor.tinyQ5_1.language, 'multilingual');
        expect(WhisperModelDescriptor.tinyQ5_1.sizeLabel, '30.7 MiB');
      },
    );
  });

  group('WhisperModelStore', () {
    test('installedPath returns null when model not present', () async {
      final store = WhisperModelStore(baseDirectory: tempDir);
      final path = await store.installedPath(testDescriptor);
      expect(path, isNull);
    });

    test('installedPath returns null when size does not match', () async {
      final store = WhisperModelStore(baseDirectory: tempDir);
      final file = File(
        '${tempDir.path}${Platform.pathSeparator}${testDescriptor.fileName}',
      );
      file.writeAsBytesSync([1, 2, 3]); // Wrong size
      final path = await store.installedPath(testDescriptor);
      expect(path, isNull);
    });

    test(
      'installedPath returns path when valid file and marker exist',
      () async {
        final store = WhisperModelStore(baseDirectory: tempDir);
        final file = File(
          '${tempDir.path}${Platform.pathSeparator}${testDescriptor.fileName}',
        );
        file.writeAsBytesSync(testModelBytes);
        final marker = File('${file.path}.sha256');
        marker.writeAsStringSync(testSha256);

        final path = await store.installedPath(testDescriptor);
        expect(path, equals(file.path));
      },
    );

    test('preflight fails with WhisperStorageException when free space is insufficient', () async {
      final probe = _FakeFreeSpaceProbe(1024); // Only 1 KB available
      final store = WhisperModelStore(
        baseDirectory: tempDir,
        freeSpaceProbe: probe,
        safetyReserveBytes: 50 * 1024 * 1024,
      );

      expect(
        () => store.install(testDescriptor),
        throwsA(
          isA<WhisperStorageException>().having(
            (e) => e.message,
            'message',
            contains('Insufficient disk space'),
          ),
        ),
      );
    });

    test(
      'remove deletes model and marker without touching other files',
      () async {
        final store = WhisperModelStore(baseDirectory: tempDir);
        final modelFile = File(
          '${tempDir.path}${Platform.pathSeparator}${testDescriptor.fileName}',
        );
        modelFile.writeAsBytesSync(testModelBytes);
        final markerFile = File('${modelFile.path}.sha256');
        markerFile.writeAsStringSync(testSha256);

        // Unrelated file
        final audioFile = File(
          '${tempDir.path}${Platform.pathSeparator}recording.m4a',
        );
        audioFile.writeAsStringSync('audio-data');

        final deleted = await store.remove(testDescriptor);
        expect(deleted, isTrue);
        expect(modelFile.existsSync(), isFalse);
        expect(markerFile.existsSync(), isFalse);
        expect(audioFile.existsSync(), isTrue); // Unrelated files preserved
      },
    );
  });
  test(
    'FR-TRN-07 same-size tampering cannot pass a forged cached marker',
    () async {
      final file = File('${tempDir.path}/${testDescriptor.fileName}');
      file.writeAsBytesSync(Uint8List(testModelBytes.length));
      File('${file.path}.sha256').writeAsStringSync(testSha256);
      expect(
        await WhisperModelStore(baseDirectory: tempDir)
            .installedPath(testDescriptor),
        isNull,
      );
    },
  );

  test(
    'FR-TRN-07 unsafe descriptor IDs are rejected before file access',
    () async {
      final store = WhisperModelStore(baseDirectory: tempDir);
      for (final id in [
        '../../outside',
        r'..\outside',
        '/absolute',
        'trailing.',
        'a..b',
      ]) {
        final invalid = WhisperModelDescriptor(
          id: id,
          name: 'Synthetic',
          sizeBytes: 1,
          language: 'en',
          sha256: testSha256,
          downloadUrl: 'https://example.com/model',
        );
        await expectLater(
          store.installedPath(invalid),
          throwsA(isA<WhisperStorageException>()),
        );
        await expectLater(
          store.remove(invalid),
          throwsA(isA<WhisperStorageException>()),
        );
      }
      expect(tempDir.listSync(), isEmpty);
    },
  );

  test(
    'FR-TRN-06 cancellation during preflight drains and prevents any request',
    () async {
      final probe = _GateProbe();
      var clients = 0;
      final store = WhisperModelStore(
        baseDirectory: tempDir,
        freeSpaceProbe: probe,
        httpClientFactory: () {
          clients++;
          throw StateError('No download should start');
        },
      );
      final job = store.install(testDescriptor);
      final expected = expectLater(
        job,
        throwsA(isA<WhisperStorageException>()),
      );
      await probe.entered.future;
      var finished = false;
      final cancelled = store.cancelInstall().then((_) => finished = true);
      await Future<void>.delayed(Duration.zero);
      expect(finished, isFalse);
      probe.gate.complete(
        const FreeSpace(availableBytes: 1 << 30, totalBytes: 1 << 30),
      );
      await cancelled;
      await expected;
      expect(clients, 0);
    },
  );

  test('FR-TRN-06 streamed cancellation aborts and cleans its writer before returning', () async {
    // Closed by fake request abort while the store drains cancellation.
    // ignore: close_sinks
    final stream = StreamController<List<int>>();
    final started = Completer<void>();
    // Request close/abort is exercised by the store under test.
    // ignore: close_sinks
    final request = _Request(
      _Response(stream.stream, testModelBytes.length),
      abortStream: stream,
    );
    final store = WhisperModelStore(
      baseDirectory: tempDir,
      freeSpaceProbe: _FakeFreeSpaceProbe(1 << 30),
      httpClientFactory: () => _Client(request),
    );
    final job = store.install(
      testDescriptor,
      onProgress: (value) {
        if (value == 0 && !started.isCompleted) started.complete();
      },
    );
    final expected = expectLater(job, throwsA(anything));
    await started.future;
    stream.add(testModelBytes.sublist(0, 3));
    await store.cancelInstall();
    await expected;
    expect(tempDir.listSync(), isEmpty);
  });

  test('FR-TRN-07 verified streamed install is atomic and mismatched hash is refused', () async {
    _Client client(List<int> bytes) =>
        _Client(_Request(_Response(Stream.value(bytes), bytes.length)));
    var bad = true;
    final store = WhisperModelStore(
      baseDirectory: tempDir,
      freeSpaceProbe: _FakeFreeSpaceProbe(1 << 30),
      httpClientFactory: () =>
          client(bad ? Uint8List(testModelBytes.length) : testModelBytes),
    );
    await expectLater(
      store.install(testDescriptor),
      throwsA(isA<WhisperStorageException>()),
    );
    expect(tempDir.listSync(), isEmpty);
    bad = false;
    final installed = await store.install(testDescriptor);
    expect(await File(installed).readAsBytes(), testModelBytes);
    expect(await store.installedPath(testDescriptor), installed);
    expect(tempDir.listSync().whereType<Directory>(), isEmpty);
  });
}

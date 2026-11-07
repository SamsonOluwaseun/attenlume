import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:attenlume/features/ai/language_model_providers.dart';
import 'package:attenlume/platform/ai/language_model_store.dart';
import 'package:attenlume/platform/storage/free_space_probe.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
  late Uint8List testModelBytes;
  late String testSha256;
  late LanguageModelDescriptor testDescriptor;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('ai_providers_test_');
    testModelBytes = Uint8List.fromList(
      utf8.encode('mock-gemma-bytes-for-provider-test'),
    );
    testSha256 = sha256.convert(testModelBytes).toString();
    testDescriptor = LanguageModelDescriptor(
      id: 'test-gemma',
      name: 'Gemma 4 E2B, Fast',
      sizeBytes: testModelBytes.length,
      sha256: testSha256,
      downloadUrl: 'https://example.com/gemma.gguf',
      fileName: 'test-gemma.gguf',
      licence: 'Apache 2.0',
      deviceNotice: 'Runs on this device. Nothing you record is sent anywhere.',
    );
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('P3-10 FR-AI-01: LanguageModelController', () {
    test('initial state is not installed when directory is empty', () async {
      final store = LanguageModelStore(baseDirectory: tempDir);
      final controller = LanguageModelController(
        store: store,
        freeSpaceProbe: _FakeFreeSpaceProbe(10 * 1024 * 1024 * 1024),
        descriptor: testDescriptor,
      );
      await controller.refresh();

      expect(controller.state.status, LanguageModelStatus.notInstalled);
      expect(controller.state.isInstalled, isFalse);
      expect(controller.state.isDownloading, isFalse);
      expect(controller.state.installedPath, isNull);
    });

    test(
      'refuses download with plain reason if space is insufficient',
      () async {
        final probe = _FakeFreeSpaceProbe(100); // Very little space
        final store = LanguageModelStore(
          baseDirectory: tempDir,
          freeSpaceProbe: probe,
        );
        final controller = LanguageModelController(
          store: store,
          freeSpaceProbe: probe,
          descriptor: testDescriptor,
        );
        await controller.refresh();

        final result = await controller.startDownload();
        expect(result, isFalse);
        expect(controller.state.status, LanguageModelStatus.error);
        expect(controller.state.errorMessage, contains('Not enough storage'));
        expect(
          controller.state.errorMessage,
          contains('2.65 GB plus 1 GB free space'),
        );
      },
    );

    test('successful download transitions to installed state', () async {
      _Client client(List<int> bytes) =>
          _Client(_Request(_Response(Stream.value(bytes), bytes.length)));
      final probe = _FakeFreeSpaceProbe(10 * 1024 * 1024 * 1024);
      final store = LanguageModelStore(
        baseDirectory: tempDir,
        freeSpaceProbe: probe,
        httpClientFactory: () => client(testModelBytes),
      );
      final controller = LanguageModelController(
        store: store,
        freeSpaceProbe: probe,
        descriptor: testDescriptor,
      );
      await controller.refresh();

      final result = await controller.startDownload();
      expect(result, isTrue);
      expect(controller.state.status, LanguageModelStatus.installed);
      expect(controller.state.isInstalled, isTrue);
      expect(controller.state.installedPath, isNotNull);
      expect(File(controller.state.installedPath!).existsSync(), isTrue);
    });

    test('hash mismatch records error and deletes partial', () async {
      final badBytes = Uint8List(testModelBytes.length);
      _Client client(List<int> bytes) =>
          _Client(_Request(_Response(Stream.value(bytes), bytes.length)));
      final probe = _FakeFreeSpaceProbe(10 * 1024 * 1024 * 1024);
      final store = LanguageModelStore(
        baseDirectory: tempDir,
        freeSpaceProbe: probe,
        httpClientFactory: () => client(badBytes),
      );
      final controller = LanguageModelController(
        store: store,
        freeSpaceProbe: probe,
        descriptor: testDescriptor,
      );
      await controller.refresh();

      final result = await controller.startDownload();
      expect(result, isFalse);
      expect(controller.state.status, LanguageModelStatus.error);
      expect(controller.state.errorMessage, contains('verification failed'));
      expect(tempDir.listSync().whereType<Directory>(), isEmpty);
    });

    test('cancel download cleans up and resets state', () async {
      // ignore: close_sinks
      final stream = StreamController<List<int>>();
      // ignore: close_sinks
      final request = _Request(
        _Response(stream.stream, testModelBytes.length),
        abortStream: stream,
      );
      final probe = _FakeFreeSpaceProbe(10 * 1024 * 1024 * 1024);
      final store = LanguageModelStore(
        baseDirectory: tempDir,
        freeSpaceProbe: probe,
        httpClientFactory: () => _Client(request),
      );
      final controller = LanguageModelController(
        store: store,
        freeSpaceProbe: probe,
        descriptor: testDescriptor,
      );
      await controller.refresh();

      final downloadFuture = controller.startDownload();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await controller.cancelDownload();
      await downloadFuture;

      expect(controller.state.status, LanguageModelStatus.notInstalled);
      expect(controller.state.isDownloading, isFalse);
      expect(tempDir.listSync(), isEmpty);
    });

    test('deleteModel removes model and resets state', () async {
      final probe = _FakeFreeSpaceProbe(10 * 1024 * 1024 * 1024);
      final store = LanguageModelStore(
        baseDirectory: tempDir,
        freeSpaceProbe: probe,
      );
      final targetFile = File('${tempDir.path}/${testDescriptor.fileName}');
      targetFile.writeAsBytesSync(testModelBytes);
      File('${targetFile.path}.sha256').writeAsStringSync(testSha256);

      final controller = LanguageModelController(
        store: store,
        freeSpaceProbe: probe,
        descriptor: testDescriptor,
      );
      await controller.refresh();
      expect(controller.state.isInstalled, isTrue);

      final deleted = await controller.deleteModel();
      expect(deleted, isTrue);
      expect(controller.state.status, LanguageModelStatus.notInstalled);
      expect(targetFile.existsSync(), isFalse);
    });
  });

  group('P3-10 FR-AI-01: Riverpod installedLanguageModelPathProvider', () {
    test('answers null when model is not installed', () async {
      final store = LanguageModelStore(baseDirectory: tempDir);
      final container = ProviderContainer(
        overrides: [
          languageModelStoreProvider.overrideWith((ref) async => store),
          activeLanguageModelDescriptorProvider.overrideWith(
            (ref) async => testDescriptor,
          ),
        ],
      );
      addTearDown(container.dispose);

      final path = await container.read(
        installedLanguageModelPathProvider.future,
      );
      expect(path, isNull);
    });

    test('answers verified path when model is installed', () async {
      final store = LanguageModelStore(baseDirectory: tempDir);
      final file = File(
        '${tempDir.path}${Platform.pathSeparator}${testDescriptor.fileName}',
      );
      file.writeAsBytesSync(testModelBytes);
      File('${file.path}.sha256').writeAsStringSync(testSha256);

      final container = ProviderContainer(
        overrides: [
          languageModelStoreProvider.overrideWith((ref) async => store),
          activeLanguageModelDescriptorProvider.overrideWith(
            (ref) async => testDescriptor,
          ),
        ],
      );
      addTearDown(container.dispose);

      final path = await container.read(
        installedLanguageModelPathProvider.future,
      );
      expect(path, equals(file.path));
    });
  });
}

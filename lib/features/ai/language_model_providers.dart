import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../data/filesystem/app_data_directory.dart';
import '../../platform/ai/language_model_store.dart';
import '../../platform/storage/free_space_probe.dart';
import '../capture/recording_providers.dart' show freeSpaceProbeProvider;

/// Storage directory for on-device language models (`<appData>/models`).
final languageModelDirectoryProvider = FutureProvider<Directory>((ref) async {
  final root = await appDataDirectory();
  final canonicalRoot = await root.resolveSymbolicLinks();
  final dir = Directory(p.join(canonicalRoot, 'models'));
  if (!dir.existsSync()) {
    dir.createSync(recursive: true);
  }
  return dir;
});

/// Asynchronous factory for [LanguageModelStore].
final languageModelStoreProvider = FutureProvider<LanguageModelStore>((
  ref,
) async {
  final dir = await ref.watch(languageModelDirectoryProvider.future);
  final freeSpace = ref.watch(freeSpaceProbeProvider);
  return LanguageModelStore(baseDirectory: dir, freeSpaceProbe: freeSpace);
});

/// The active language model descriptor (Phase 3, FR-AI-01).
/// Defaults to pinned [LanguageModelDescriptor.defaultModel] (Gemma 4 E2B).
final activeLanguageModelDescriptorProvider = Provider<LanguageModelDescriptor>(
  (ref) {
    return LanguageModelDescriptor.defaultModel;
  },
);

/// Answers the installed, verified on-device language model path, or null if
/// not downloaded or verification failed (P3-10, FR-AI-01).
///
/// For consumption by P3-02b (grounded summaries engine).
final installedLanguageModelPathProvider = FutureProvider<String?>((ref) async {
  try {
    final store = await ref.watch(languageModelStoreProvider.future);
    final descriptor = ref.watch(activeLanguageModelDescriptorProvider);
    return await store.installedPath(descriptor);
  } catch (_) {
    return null;
  }
});

/// Alias for [installedLanguageModelPathProvider].
final aiModelPathProvider = installedLanguageModelPathProvider;

enum LanguageModelStatus {
  notInstalled,
  checkingSpace,
  downloading,
  installed,
  error,
}

class LanguageModelState {
  const LanguageModelState({
    required this.status,
    this.progress = 0.0,
    this.installedPath,
    this.errorMessage,
  });

  final LanguageModelStatus status;
  final double progress;
  final String? installedPath;
  final String? errorMessage;

  bool get isDownloading => status == LanguageModelStatus.downloading;
  bool get isInstalled => status == LanguageModelStatus.installed;
  bool get isError => status == LanguageModelStatus.error;
}

class LanguageModelController extends ChangeNotifier {
  LanguageModelController({
    required this.store,
    required this.freeSpaceProbe,
    this.descriptor = LanguageModelDescriptor.defaultModel,
    this.onStateChanged,
  }) {
    unawaited(refresh());
  }

  final LanguageModelStore store;
  final FreeSpaceProbe freeSpaceProbe;
  final LanguageModelDescriptor descriptor;
  final VoidCallback? onStateChanged;

  LanguageModelState _state = const LanguageModelState(
    status: LanguageModelStatus.notInstalled,
  );

  LanguageModelState get state => _state;

  void _setState(LanguageModelState next) {
    _state = next;
    notifyListeners();
    onStateChanged?.call();
  }

  Future<void> refresh() async {
    try {
      final path = await store.installedPath(descriptor);
      if (path != null) {
        _setState(
          LanguageModelState(
            status: LanguageModelStatus.installed,
            installedPath: path,
            progress: 1.0,
          ),
        );
      } else {
        _setState(
          const LanguageModelState(status: LanguageModelStatus.notInstalled),
        );
      }
    } catch (e) {
      _setState(
        LanguageModelState(
          status: LanguageModelStatus.error,
          errorMessage: e.toString(),
        ),
      );
    }
  }

  /// Initiates preflight free-space probe and model download.
  ///
  /// Returns `true` if download completes successfully, `false` otherwise.
  Future<bool> startDownload() async {
    if (_state.isDownloading) return false;

    _setState(
      const LanguageModelState(status: LanguageModelStatus.checkingSpace),
    );

    // Free space check: model size + 1 GB warning margin (FR-AI-01).
    final requiredBytes = descriptor.sizeBytes + store.safetyReserveBytes;
    final space = await freeSpaceProbe.query(store.baseDirectory.path);
    if (space == null || space.availableBytes < requiredBytes) {
      _setState(
        const LanguageModelState(
          status: LanguageModelStatus.error,
          errorMessage:
              'Not enough storage to download this model. Gemma 4 E2B needs '
              '2.65 GB plus 1 GB free space.',
        ),
      );
      return false;
    }

    _setState(
      const LanguageModelState(
        status: LanguageModelStatus.downloading,
        progress: 0.0,
      ),
    );

    try {
      final installedPath = await store.install(
        descriptor,
        onProgress: (progress) {
          if (_state.status == LanguageModelStatus.downloading) {
            _setState(
              LanguageModelState(
                status: LanguageModelStatus.downloading,
                progress: progress,
              ),
            );
          }
        },
      );

      _setState(
        LanguageModelState(
          status: LanguageModelStatus.installed,
          installedPath: installedPath,
          progress: 1.0,
        ),
      );
      return true;
    } catch (e) {
      if (e is ModelStorageException && e.message.contains('cancelled')) {
        _setState(
          const LanguageModelState(status: LanguageModelStatus.notInstalled),
        );
      } else {
        _setState(
          LanguageModelState(
            status: LanguageModelStatus.error,
            errorMessage: e is ModelStorageException ? e.message : e.toString(),
          ),
        );
      }
      return false;
    }
  }

  Future<void> cancelDownload() async {
    _setState(
      const LanguageModelState(status: LanguageModelStatus.notInstalled),
    );
    try {
      await store.cancelInstall(modelId: descriptor.id);
    } catch (_) {}
  }

  Future<bool> deleteModel() async {
    try {
      final removed = await store.remove(descriptor);
      _setState(
        const LanguageModelState(status: LanguageModelStatus.notInstalled),
      );
      return removed;
    } catch (e) {
      _setState(
        LanguageModelState(
          status: LanguageModelStatus.error,
          errorMessage: e is ModelStorageException ? e.message : e.toString(),
        ),
      );
      return false;
    }
  }
}

/// Provider for [LanguageModelController].
final languageModelControllerProvider = FutureProvider<LanguageModelController>(
  (ref) async {
    final store = await ref.watch(languageModelStoreProvider.future);
    final freeSpace = ref.watch(freeSpaceProbeProvider);
    final controller = LanguageModelController(
      store: store,
      freeSpaceProbe: freeSpace,
      onStateChanged: () {
        ref.invalidate(installedLanguageModelPathProvider);
      },
    );
    ref.onDispose(controller.dispose);
    return controller;
  },
);

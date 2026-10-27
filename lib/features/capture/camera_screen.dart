import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/tokens.dart';
import '../../data/filesystem/media_paths.dart';
import '../../domain/models/media.dart';
import '../../domain/services/photo_capture_service.dart';
import '../../platform/camera/photo_camera.dart';
import 'recording_providers.dart';

/// In-app camera with a live viewfinder (FR-PHO-01, FR-UI-03) [P1-14].
///
/// The shutter is ready again as soon as the camera has the shot;
/// compression and thumbnails finish in the background. Recording, if
/// any, carries on underneath. Pops with the number of photos taken.
class CameraScreen extends ConsumerStatefulWidget {
  const CameraScreen({super.key, required this.activityId});

  final String activityId;

  /// Opens the camera for [activityId] and returns how many photos were
  /// saved.
  static Future<int> open(BuildContext context, String activityId) async =>
      await Navigator.of(context).push<int>(
        MaterialPageRoute(builder: (_) => CameraScreen(activityId: activityId)),
      ) ??
      0;

  @override
  ConsumerState<CameraScreen> createState() => _CameraScreenState();
}

enum _CameraState { opening, ready, noCamera, accessDenied, failed }

class _CameraScreenState extends ConsumerState<CameraScreen> {
  late final PhotoCaptureService _service;
  _CameraState _state = _CameraState.opening;
  String? _error;
  bool _shutterBusy = false;
  bool _flash = false;
  int _saved = 0;
  Photo? _last;
  Directory? _mediaRoot;
  final List<Future<void>> _pending = [];

  @override
  void initState() {
    super.initState();
    _service = ref.read(photoCaptureServiceProvider);
    unawaited(_open());
  }

  @override
  void dispose() {
    unawaited(_service.close());
    super.dispose();
  }

  Future<void> _open() async {
    try {
      _mediaRoot = await ref.read(mediaRootProvider)();
      await _service.open();
      if (mounted) setState(() => _state = _CameraState.ready);
    } on CameraAccessDeniedException {
      if (mounted) setState(() => _state = _CameraState.accessDenied);
    } on CameraUnavailableException {
      if (mounted) setState(() => _state = _CameraState.noCamera);
    } catch (e) {
      if (mounted) {
        setState(() {
          _state = _CameraState.failed;
          _error = '$e';
        });
      }
    }
  }

  void _takePhoto() {
    if (_state != _CameraState.ready || _shutterBusy) return;
    unawaited(HapticFeedback.lightImpact());
    setState(() {
      _shutterBusy = true;
      _flash = true;
    });
    late final Future<void> job;
    job = _service
        .capture(
          widget.activityId,
          onShutterReady: () {
            if (mounted) setState(() => _shutterBusy = false);
          },
        )
        .then((photo) {
          if (mounted) {
            setState(() {
              _saved++;
              _last = photo;
            });
          }
          unawaited(
            ref
                .read(storageBudgetServiceProvider)
                .checkNow(activityId: widget.activityId),
          );
        })
        .catchError((Object e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text("Couldn't save the photo: $e")),
            );
          }
        })
        .whenComplete(() => _pending.remove(job));
    _pending.add(job);
    Future<void>.delayed(const Duration(milliseconds: 120), () {
      if (mounted) setState(() => _flash = false);
    });
  }

  Future<void> _close() async {
    await Future.wait(List.of(_pending));
    if (mounted) Navigator.of(context).pop(_saved);
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: AppTheme.live(),
      child: Builder(
        builder: (context) {
          final theme = Theme.of(context);
          final colours = theme.extension<AttenlumeColors>();
          final surface = colours?.liveSurface ?? const Color(0xFF00212B);
          final onSurface = colours?.onLiveSurface ?? const Color(0xFFFEFFF8);
          final muted = colours?.onLiveSurfaceMuted ?? onSurface;
          final live = colours?.live ?? const Color(0xFFDCFF38);

          return PopScope(
            canPop: false,
            onPopInvokedWithResult: (didPop, _) {
              if (!didPop) unawaited(_close());
            },
            child: Scaffold(
              key: const Key('camera-screen'),
              backgroundColor: Colors.black,
              body: SafeArea(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(TokenSpace.space2),
                      child: Row(
                        children: [
                          IconButton(
                            key: const Key('camera-close-button'),
                            tooltip: 'Close camera',
                            icon: Icon(Icons.close_rounded, color: onSurface),
                            onPressed: _close,
                          ),
                          const Spacer(),
                          Text(
                            _saved == 1 ? '1 photo' : '$_saved photos',
                            key: const Key('camera-photo-count'),
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: onSurface,
                            ),
                          ),
                          const SizedBox(width: TokenSpace.space4),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Center(child: _viewfinder(theme, onSurface, muted)),
                          IgnorePointer(
                            child: AnimatedOpacity(
                              opacity: _flash ? 0.6 : 0,
                              duration: const Duration(milliseconds: 80),
                              child: const ColoredBox(color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      color: surface,
                      padding: const EdgeInsets.symmetric(
                        horizontal: TokenSpace.space5,
                        vertical: TokenSpace.space4,
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 56,
                            height: 56,
                            child: _lastThumbnail(onSurface),
                          ),
                          const Spacer(),
                          _shutter(onSurface, live),
                          const Spacer(),
                          const SizedBox(width: 56),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _viewfinder(ThemeData theme, Color onSurface, Color muted) {
    final message = switch (_state) {
      _CameraState.opening => null,
      _CameraState.ready => null,
      _CameraState.noCamera => 'No camera found on this device.',
      _CameraState.accessDenied =>
        'Attenlume needs camera access to take photos. Allow it in your '
            'device settings, then open the camera again.',
      _CameraState.failed => "Couldn't open the camera. ${_error ?? ''}",
    };
    if (_state == _CameraState.opening) {
      return const CircularProgressIndicator(key: Key('camera-opening'));
    }
    if (message != null) {
      return Padding(
        padding: const EdgeInsets.all(TokenSpace.space6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.no_photography_outlined, color: muted, size: 48),
            const SizedBox(height: TokenSpace.space4),
            Text(
              message,
              key: const Key('camera-message'),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(color: onSurface),
            ),
          ],
        ),
      );
    }
    return _service.camera.buildPreview();
  }

  Widget _shutter(Color ring, Color fill) {
    final enabled = _state == _CameraState.ready && !_shutterBusy;
    return Semantics(
      button: true,
      label: 'Take photo',
      enabled: enabled,
      child: GestureDetector(
        key: const Key('camera-shutter-button'),
        onTap: enabled ? _takePhoto : null,
        child: Container(
          width: 76,
          height: 76,
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: ring, width: 4),
          ),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: enabled ? fill : fill.withValues(alpha: 0.4),
            ),
          ),
        ),
      ),
    );
  }

  Widget _lastThumbnail(Color border) {
    final last = _last;
    final root = _mediaRoot;
    if (last == null || root == null) return const SizedBox.shrink();
    final path = last.thumbnailPath ?? last.filePath;
    return ClipRRect(
      key: const Key('camera-last-thumbnail'),
      borderRadius: BorderRadius.circular(TokenRadius.radiusSm),
      child: Image.file(
        MediaPaths.resolve(root, path),
        fit: BoxFit.cover,
        cacheWidth: 112,
        errorBuilder: (_, _, _) =>
            ColoredBox(color: border.withValues(alpha: 0.2)),
      ),
    );
  }
}

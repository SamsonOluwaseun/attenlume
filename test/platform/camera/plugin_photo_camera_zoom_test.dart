import 'dart:async';
import 'dart:io';

import 'package:attenlume/platform/camera/photo_camera.dart';
import 'package:attenlume/platform/camera/plugin_photo_camera.dart';
// Test the plugin contract at the platform boundary without physical hardware.
// ignore: depend_on_referenced_packages
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeCameraPlatform extends CameraPlatform {
  double min = 0.5;
  double max = 6;
  bool unsupported = false;
  bool rejectSet = false;
  final levels = <double>[];
  final events = <String>[];
  final audio = <bool>[];
  Completer<void>? zoomGate;
  Completer<void>? captureGate;
  Completer<void>? initializeGate;
  final tempDirectories = <Directory>[];
  int id = 0;
  @override
  Future<List<CameraDescription>> availableCameras() async => const [
    CameraDescription(
      name: 'back',
      lensDirection: CameraLensDirection.back,
      sensorOrientation: 0,
    ),
    CameraDescription(
      name: 'front',
      lensDirection: CameraLensDirection.front,
      sensorOrientation: 0,
    ),
  ];
  @override
  Future<int> createCamera(
    CameraDescription cameraDescription,
    ResolutionPreset? resolutionPreset, {
    bool enableAudio = false,
  }) async {
    audio.add(enableAudio);
    events.add('open');
    return ++id;
  }

  @override
  Stream<DeviceOrientationChangedEvent> onDeviceOrientationChanged() =>
      const Stream.empty();
  @override
  Stream<CameraInitializedEvent> onCameraInitialized(int cameraId) =>
      Stream.value(
        CameraInitializedEvent(
          cameraId,
          640,
          480,
          ExposureMode.auto,
          false,
          FocusMode.auto,
          false,
        ),
      );
  @override
  Stream<CameraErrorEvent> onCameraError(int cameraId) => Stream.multi((_) {});
  @override
  Future<void> initializeCamera(
    int cameraId, {
    ImageFormatGroup imageFormatGroup = ImageFormatGroup.unknown,
  }) async {
    await initializeGate?.future;
  }

  @override
  Future<double> getMinZoomLevel(int cameraId) async {
    if (unsupported) throw UnimplementedError('No driver support');
    return min;
  }

  @override
  Future<double> getMaxZoomLevel(int cameraId) async => max;
  @override
  Future<void> setZoomLevel(int cameraId, double zoom) async {
    if (rejectSet) throw UnimplementedError('No driver support');
    events.add('zoom-start');
    levels.add(zoom);
    await zoomGate?.future;
    events.add('zoom-end');
  }

  @override
  Future<XFile> takePicture(int cameraId) async {
    events.add('capture-start');
    events.add('captured-zoom-${levels.last}');
    await captureGate?.future;
    final dir = await Directory.systemTemp.createTemp('P1-53-shot');
    tempDirectories.add(dir);
    final file = File('${dir.path}/shot.jpg');
    await file.writeAsBytes([1, 2, 3]);
    return XFile(file.path);
  }

  @override
  Future<void> dispose(int cameraId) async {
    events.add('close');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late CameraPlatform previous;
  late FakeCameraPlatform platform;
  late PluginPhotoCamera camera;
  setUp(() {
    previous = CameraPlatform.instance;
    platform = FakeCameraPlatform();
    CameraPlatform.instance = platform;
    camera = PluginPhotoCamera();
  });
  tearDown(() async {
    platform.zoomGate?.complete();
    await camera.close();
    for (final dir in platform.tempDirectories) {
      await dir.delete(recursive: true);
    }
    CameraPlatform.instance = previous;
  });

  test('FR-PHO-09 P1-53 real limits, clamp and no microphone', () async {
    await camera.open();
    expect(camera.zoomRange!.min, 0.5);
    expect(camera.zoomRange!.max, 6);
    await camera.setZoomLevel(99);
    expect(camera.zoomLevel, 6);
    await camera.setZoomLevel(-1);
    expect(camera.zoomLevel, 0.5);
    await camera.setZoomLevel(double.nan);
    expect(camera.zoomLevel, 0.5);
    expect(platform.audio, [false]);
  });
  test(
    'FR-PHO-09 P1-53 unsupported or invalid capability keeps camera open',
    () async {
      platform.unsupported = true;
      await camera.open();
      expect(camera.isOpen, isTrue);
      expect(camera.zoomRange, isNull);
      await camera.close();
      platform.unsupported = false;
      platform.min = double.nan;
      await camera.open();
      expect(camera.isOpen, isTrue);
      expect(camera.zoomRange, isNull);
    },
  );
  test(
    'FR-PHO-09 P1-53 set rejection disables zoom without closing capture',
    () async {
      await camera.open();
      platform.rejectSet = true;
      await camera.setZoomLevel(3);
      expect(camera.zoomRange, isNull);
      expect(camera.isOpen, isTrue);
    },
  );
  test(
    'FR-PHO-09 P1-53 close/reopen new lens queries range and resets',
    () async {
      await camera.open();
      await camera.setZoomLevel(4);
      await camera.close();
      platform.min = 1;
      platform.max = 2;
      await camera.open(
        lens: const CameraLens(id: 'front', facing: CameraFacing.front),
      );
      expect(camera.lens!.id, 'front');
      expect(camera.zoomRange!.max, 2);
      expect(camera.zoomLevel, 1);
      expect(platform.audio, [false, false]);
    },
  );
  test('FR-PHO-09 P1-53 rapid updates coalesce and close waits for native operation', () async {
    await camera.open();
    platform.zoomGate = Completer<void>();
    final first = camera.setZoomLevel(2);
    await Future<void>.delayed(Duration.zero);
    final second = camera.setZoomLevel(3);
    final third = camera.setZoomLevel(5);
    platform.zoomGate!.complete();
    platform.zoomGate = null;
    await Future.wait([first, second, third]);
    expect(platform.levels, [1, 2, 5]);
    platform.zoomGate = Completer<void>();
    final zoom = camera.setZoomLevel(4);
    await Future<void>.delayed(Duration.zero);
    final close = camera.close();
    await Future<void>.delayed(Duration.zero);
    expect(platform.events.last, 'zoom-start');
    platform.zoomGate!.complete();
    platform.zoomGate = null;
    await Future.wait([zoom, close]);
    expect(platform.events.last, 'close');
    expect(camera.zoomRange, isNull);
  });
  test('FR-PHO-09 P1-53 capture and close wait for zoom, unsupported zoom still captures', () async {
    final output = await Directory.systemTemp.createTemp('P1-53-output');
    addTearDown(() => output.delete(recursive: true));
    await camera.open();
    platform.zoomGate = Completer<void>();
    final zoom = camera.setZoomLevel(3);
    await Future<void>.delayed(Duration.zero);
    final latest = camera.setZoomLevel(5);
    final shot = camera.takePhoto('${output.path}/photo.jpg');
    final close = camera.close();
    await Future<void>.delayed(Duration.zero);
    expect(platform.events.contains('capture-start'), isFalse);
    platform.zoomGate!.complete();
    platform.zoomGate = null;
    await zoom;
    await latest;
    final photo = await shot;
    expect(platform.events, contains('captured-zoom-5.0'));
    await close;
    expect(photo.bytes, 3);
    expect(
      platform.events.indexOf('capture-start'),
      greaterThan(platform.events.indexOf('zoom-end')),
    );
    expect(platform.events.last, 'close');
    platform.unsupported = true;
    await camera.open();
    final unsupportedPhoto = await camera.takePhoto(
      '${output.path}/unsupported.jpg',
    );
    expect(unsupportedPhoto.bytes, 3);
  });
  test('FR-PHO-09 P1-53 close requested during opening releases newly initialized camera', () async {
    platform.initializeGate = Completer<void>();
    final opening = camera.open();
    await Future<void>.delayed(Duration.zero);
    final closing = camera.close();
    platform.initializeGate!.complete();
    await opening;
    await closing;
    expect(camera.isOpen, isFalse);
    expect(camera.zoomRange, isNull);
    expect(platform.events.last, 'close');
  });
}

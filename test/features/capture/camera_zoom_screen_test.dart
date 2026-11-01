import 'dart:io';
import 'dart:ui' as ui;

import 'package:attenlume/domain/services/photo_capture_service.dart';
import 'package:attenlume/features/capture/camera_screen.dart';
import 'package:attenlume/features/capture/recording_providers.dart';
import 'package:attenlume/platform/camera/photo_camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fixtures/fake_photo_camera.dart';
import '../../fixtures/fixtures.dart';

class ZoomCamera extends FakePhotoCamera implements PhotoCameraZoom {
  @override
  CameraZoomRange? zoomRange;
  @override
  double zoomLevel = 1;
  @override
  Future<void> open({CameraLens? lens}) async {
    await super.open(lens: lens);
    zoomRange = this.lens?.facing == CameraFacing.front
        ? const CameraZoomRange(1, 2)
        : const CameraZoomRange(0.5, 5);
    zoomLevel = 1;
  }

  @override
  Future<void> setZoomLevel(double level) async {
    zoomLevel = zoomRange!.clamp(level);
  }
}

void main() {
  late TestData data;
  late Directory root;
  setUp(() async {
    data = TestData();
    root = await Directory.systemTemp.createTemp('P1-53-ui');
  });
  tearDown(() async {
    await data.close();
    await root.delete(recursive: true);
  });

  Future<void> show(
    WidgetTester tester,
    FakePhotoCamera camera, {
    double textScale = 2,
  }) async {
    final service = PhotoCaptureService(
      camera: camera,
      activities: data.activities,
      media: data.media,
      mediaRoot: () async => root,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          photoCaptureServiceProvider.overrideWithValue(service),
          mediaRootProvider.overrideWithValue(() async => root),
        ],
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: const RepaintBoundary(
            key: Key('camera-guide-capture'),
            child: CameraScreen(activityId: 'test'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'FR-PHO-09 P1-53 labelled zoom and lens reset at 200 percent text',
    (tester) async {
      final camera = ZoomCamera()
        ..lenses = const [
          CameraLens(id: 'back', facing: CameraFacing.back),
          CameraLens(id: 'front', facing: CameraFacing.front),
        ];
      await show(tester, camera);
      final slider = find.byKey(const Key('camera-zoom-slider'));
      expect(slider, findsOneWidget);
      tester.widget<Slider>(slider).onChanged!(4);
      await tester.pumpAndSettle();
      expect(find.text('Zoom 4.0×'), findsOneWidget);
      await tester.tap(find.byKey(const Key('camera-switch-button')));
      await tester.pumpAndSettle();
      expect(tester.widget<Slider>(slider).max, 2);
      expect(find.text('Zoom 1.0×'), findsOneWidget);
      expect(tester.takeException(), isNull);
      // Root can capture this fake preview for the FR-UI-09 zoom-control guide.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
  testWidgets(
    'FR-PHO-09 P1-53 unsupported camera explains zoom and keeps shutter enabled',
    (tester) async {
      await show(tester, FakePhotoCamera());
      expect(find.byKey(const Key('camera-zoom-slider')), findsNothing);
      expect(
        find.text('Zoom is not available for this camera.'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<GestureDetector>(
              find.byKey(const Key('camera-shutter-button')),
            )
            .onTap,
        isNotNull,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
  if (const bool.fromEnvironment('CAPTURE_CAMERA_GUIDE')) {
    testWidgets('FR-UI-09 camera zoom guide capture (synthetic preview)', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(540, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.runAsync(() async {
        await (FontLoader('Montserrat')
              ..addFont(rootBundle.load('assets/fonts/Montserrat-Regular.ttf'))
              ..addFont(rootBundle.load('assets/fonts/Montserrat-Bold.ttf')))
            .load();
        await (FontLoader(
          'MaterialIcons',
        )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      });
      final camera = ZoomCamera()
        ..lenses = const [
          CameraLens(id: 'back', facing: CameraFacing.back),
          CameraLens(id: 'front', facing: CameraFacing.front),
        ];
      await show(tester, camera, textScale: 1);
      tester
          .widget<Slider>(find.byKey(const Key('camera-zoom-slider')))
          .onChanged!(2);
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const Key('camera-guide-capture')),
        );
        final image = await boundary.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('tool/logs/camera-zoom-guide.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
      await tester.pump();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }
}

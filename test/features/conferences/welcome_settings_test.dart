import 'dart:io';
import 'dart:ui' as ui;

import 'package:attenlume/app/theme/app_theme.dart';
import 'package:attenlume/data/local_database/database_provider.dart';
import 'package:attenlume/domain/services/recording_state.dart';
import 'package:attenlume/features/capture/recording_providers.dart';
import 'package:attenlume/features/onboarding/welcome_screen.dart';
import 'package:attenlume/features/settings/settings_screen.dart';
import 'package:attenlume/features/transcription/transcription_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fixtures/fixtures.dart';

void main() {
  for (final large in [false, true]) {
    testWidgets(
      'P1-52 FR-UI-12 welcome Settings gear opens without creating a conference (large=$large)',
      (tester) async {
        var transcriptionInitialisations = 0;
        final data = TestData();
        addTearDown(data.close);
        tester.view.physicalSize = large
            ? const Size(360, 800)
            : const Size(540, 1200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        if (!large && const bool.fromEnvironment('CAPTURE_WELCOME_SETTINGS')) {
          await tester.runAsync(() async {
            await (FontLoader('Montserrat')
                  ..addFont(
                    rootBundle.load('assets/fonts/Montserrat-Regular.ttf'),
                  )
                  ..addFont(
                    rootBundle.load('assets/fonts/Montserrat-Bold.ttf'),
                  ))
                .load();
            await (FontLoader('MaterialIcons')
                  ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
                .load();
          });
        }
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              appDatabaseProvider.overrideWithValue(data.db),
              recordingStatusProvider.overrideWith(
                (ref) => Stream.value(RecordingStatus.idle),
              ),
              transcriptionControllerProvider.overrideWith((ref) async {
                transcriptionInitialisations++;
                throw StateError('Settings must not initialise transcription');
              }),
            ],
            child: MaterialApp(
              theme: AppTheme.light(),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(large ? 2 : 1)),
                child: child!,
              ),
              home: const RepaintBoundary(
                key: Key('welcome-settings-capture'),
                child: WelcomeScreen(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        if (!large) {
          if (const bool.fromEnvironment('CAPTURE_WELCOME_SETTINGS')) {
            await tester.runAsync(() async {
              final image = tester
                  .widget<Image>(find.byType(Image).first)
                  .image;
              await precacheImage(
                image,
                tester.element(find.byType(WelcomeScreen)),
              );
            });
            await tester.pumpAndSettle();
          }
          await tester.enterText(
            find.byType(TextFormField).first,
            'Samlytics Conference 2026',
          );
          FocusManager.instance.primaryFocus?.unfocus();
          await tester.pumpAndSettle();
          if (const bool.fromEnvironment('CAPTURE_WELCOME_SETTINGS')) {
            await tester.runAsync(() async {
              final boundary = tester.renderObject<RenderRepaintBoundary>(
                find.byKey(const Key('welcome-settings-capture')),
              );
              final image = await boundary.toImage();
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              await File('tool/logs/welcome-settings.png')
                  .writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
            await tester.pump();
          }
        }
        expect(
          find.byKey(const Key('welcome-settings-button')).hitTestable(),
          findsOneWidget,
        );
        expect(find.byTooltip('Settings'), findsOneWidget);
        await tester.tap(find.byKey(const Key('welcome-settings-button')));
        await tester.pumpAndSettle();
        expect(find.byType(SettingsScreen), findsOneWidget);
        expect(transcriptionInitialisations, 0);
        expect(tester.takeException(), isNull);
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.byType(WelcomeScreen), findsOneWidget);
        if (!large) {
          expect(find.text('Samlytics Conference 2026'), findsOneWidget);
        }
      },
    );
  }
}

import 'package:attenlume/app/theme/app_theme.dart';
import 'package:attenlume/domain/models/enums.dart';
import 'package:attenlume/domain/services/capture_settings.dart';
import 'package:attenlume/features/capture/recording_profile_selector.dart';
import 'package:attenlume/features/capture/recording_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const reserve = 100 * 1024 * 1024;

  Future<List<RecordingProfile>> pump(
    WidgetTester tester, {
    RecordingProfile selected = RecordingProfile.balanced,
    CapturePlatform platform = CapturePlatform.android,
    int? freeBytes,
    bool live = false,
    bool enabled = true,
  }) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final changes = <RecordingProfile>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          capturePlatformProvider.overrideWithValue(platform),
          mediaFreeBytesProvider.overrideWith((ref) async => freeBytes),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: RecordingProfileSelector(
                selected: selected,
                live: live,
                onChanged: enabled ? changes.add : null,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return changes;
  }

  group('FR-UI-08 quality selector [P1-09]', () {
    testWidgets('FR-UI-08 lists the three profiles with MB per hour and '
        'safe time left', (tester) async {
      await pump(tester, freeBytes: reserve + 6000 * 60 * 45);

      expect(find.text('Economy'), findsOneWidget);
      expect(find.text('Balanced'), findsOneWidget);
      expect(find.text('Enhanced'), findsOneWidget);
      expect(
        find.text('21.6 MB per hour · About 45 minutes left'),
        findsOneWidget,
      );
      expect(
        find.text('14.4 MB per hour · About 1 h 7 min left'),
        findsOneWidget,
      );
      expect(
        find.text('28.8 MB per hour · About 33 minutes left'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('profile-effective-notice')), findsNothing);
    });

    testWidgets('FR-UI-08 unknown free space says so', (tester) async {
      await pump(tester);
      expect(
        find.textContaining('Space left unknown'),
        findsNWidgets(RecordingProfile.values.length),
      );
    });

    testWidgets('FR-UI-08 is kept apart from the Record button: it has no '
        'record, stop or pause control', (tester) async {
      await pump(tester);
      for (final word in ['Record', 'Stop', 'Pause', 'Start']) {
        expect(
          find.widgetWithText(ButtonStyleButton, word),
          findsNothing,
          reason: word,
        );
      }
      expect(find.byIcon(Icons.fiber_manual_record), findsNothing);
    });

    testWidgets('FR-UI-08 tapping a profile reports it once; the selected '
        'one does nothing', (tester) async {
      final changes = await pump(tester);
      await tester.tap(find.byKey(const Key('profile-option-enhanced')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('profile-option-balanced')));
      await tester.pumpAndSettle();
      expect(changes, [RecordingProfile.enhanced]);
    });

    testWidgets('FR-UI-08 disabled selector ignores taps', (tester) async {
      final changes = await pump(tester, enabled: false);
      await tester.tap(find.byKey(const Key('profile-option-economy')));
      await tester.pumpAndSettle();
      expect(changes, isEmpty);
    });

    testWidgets('FR-UI-08 while recording, shows the profile in use and that '
        'a change starts a new part (FR-QUAL-04)', (tester) async {
      await pump(tester, selected: RecordingProfile.enhanced, live: true);
      expect(find.text('Recording quality: Enhanced'), findsOneWidget);
      expect(find.textContaining('Nothing already recorded'), findsOneWidget);
    });
  });

  group('FR-QUAL-05 effective settings shown before recording [P1-09]', () {
    testWidgets('FR-QUAL-05 Windows shows what will really be used', (
      tester,
    ) async {
      await pump(
        tester,
        selected: RecordingProfile.economy,
        platform: CapturePlatform.windows,
        freeBytes: reserve + 12000 * 60 * 30,
      );
      expect(
        find.textContaining('Economy records at 96 kbps instead of 32 kbps'),
        findsOneWidget,
      );
      expect(
        find.text('43.2 MB per hour · About 30 minutes left'),
        findsNWidgets(RecordingProfile.values.length),
      );
    });
  });
}

import 'dart:io';

import 'package:attenlume/app/app.dart';
import 'package:attenlume/data/local_database/app_database.dart';
import 'package:attenlume/data/local_database/database_provider.dart';
import 'package:attenlume/data/repositories/activity_repository.dart';
import 'package:attenlume/data/repositories/conference_repository.dart';
import 'package:attenlume/data/repositories/media_asset_repository.dart';
import 'package:attenlume/features/capture/recording_providers.dart';
import 'package:attenlume/platform/audio_capture/record_capture_engine.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;

/// The capture journey (PRODUCT_SPEC J2) in the real app, with the real
/// microphone and camera plugins [FR-ACT-02, FR-REC-01, FR-UI-01, FR-UI-03,
/// FR-UI-04, FR-BMK-01].
///
/// Run on the Windows laptop first, then on an Android device:
///   flutter test integration_test/app_capture_journey_test.dart -d windows
///
/// Uses an in-memory database and a temp media folder, so it never touches
/// the user's own conferences. With no microphone (for example a Remote
/// Desktop session without audio recording redirected) it checks that the
/// user is told, instead of failing silently.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'J2 quick start opens the recorder, records, bookmarks, notes and stops',
    (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      final mediaDir = await Directory.systemTemp.createTemp(
        'attenlume_journey_',
      );
      addTearDown(db.close);

      final inputs = await tester.runAsync(
        () => RecordCaptureEngine().listInputs(),
      );
      final hasMic = inputs!.isNotEmpty;
      debugPrint('J2 microphones: ${inputs.map((i) => i.label).toList()}');

      // Lets real time pass for the plugins while keeping frames coming.
      Future<void> wait(Duration d) async {
        await tester.runAsync(() => Future<void>.delayed(d));
        await tester.pump(const Duration(milliseconds: 100));
      }

      Future<void> tapKey(String key) async {
        await tester.tap(find.byKey(Key(key)));
        await wait(const Duration(milliseconds: 800));
      }

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            mediaRootProvider.overrideWithValue(() async => mediaDir),
          ],
          child: const AttenlumeApp(),
        ),
      );
      await wait(const Duration(seconds: 2));

      // J1: quick start a conference.
      await tester.enterText(
        find.byKey(const Key('conference-name-input')),
        'Journey test',
      );
      await tapKey('create-conference-button');
      await wait(const Duration(seconds: 1));
      expect(find.byKey(const Key('quick-start-session')), findsOneWidget);

      // J2 step 1 and 2: Session goes straight to the recording screen.
      await tapKey('quick-start-session');
      await wait(const Duration(seconds: 1));
      expect(
        find.byKey(const Key('recording-screen-scaffold')),
        findsOneWidget,
        reason: 'quick start must open the recorder',
      );

      final conference = (await tester.runAsync(
        () => ConferenceRepository(db).getAll(),
      ))!.single;
      final activity = (await tester.runAsync(
        () => ActivityRepository(db).listForConference(conference.id),
      ))!.single;
      final media = MediaAssetRepository(db);

      // J2 step 5: Photo opens the in-app camera (P1-14). With a camera it
      // takes one shot; without one it must say so. Either way it closes.
      Future<void> photoStep() async {
        await tapKey('record-action-photo');
        await wait(const Duration(seconds: 3));
        expect(find.byKey(const Key('camera-screen')), findsOneWidget);
        final message = find.byKey(const Key('camera-message'));
        if (message.evaluate().isNotEmpty) {
          debugPrint(
            'J2 camera: "${tester.widget<Text>(message).data}". '
            'Shutter step not run.',
          );
        } else {
          await tapKey('camera-shutter-button');
          await wait(const Duration(seconds: 4));
          expect(find.text('1 photo'), findsOneWidget);
          debugPrint('J2 camera: one photo taken');
        }
        await tapKey('camera-close-button');
        await wait(const Duration(seconds: 1));
        expect(find.byKey(const Key('camera-screen')), findsNothing);
      }

      // J2 step 3: Record.
      await tapKey('record-button-start');
      await wait(const Duration(seconds: 2));

      if (!hasMic) {
        expect(
          find.byKey(const Key('record-status-live')),
          findsNothing,
          reason: 'no microphone, so nothing can be live',
        );
        expect(
          find.byType(SnackBar),
          findsOneWidget,
          reason: 'the user must be told why recording did not start',
        );
        debugPrint(
          'J2 no microphone: recording refused with '
          '"${_snackText(tester)}". Bookmark, note and stop steps not run.',
        );
        await photoStep();
        return;
      }

      expect(find.byKey(const Key('record-status-live')), findsOneWidget);
      await wait(const Duration(seconds: 4));

      await photoStep();

      // J2 step 6: Bookmark.
      await tapKey('record-action-bookmark');

      // Quick note.
      await tapKey('record-action-note');
      await tester.enterText(
        find.byKey(const Key('quick-thought-input')),
        'Key point from the journey test',
      );
      await tapKey('quick-thought-save-button');
      await wait(const Duration(seconds: 2));

      // J2 step 7: Stop.
      await tapKey('record-button-stop');
      await wait(const Duration(seconds: 3));
      expect(find.byKey(const Key('record-status-live')), findsNothing);

      final segments = (await tester.runAsync(
        () => media.segmentsFor(activity.id),
      ))!;
      expect(segments, isNotEmpty, reason: 'a recording segment is saved');
      for (final s in segments) {
        final file = File(p.join(mediaDir.path, s.filePath));
        debugPrint(
          'J2 segment ${s.filePath}: ${s.state.name}, '
          '${file.existsSync() ? file.lengthSync() : 0} bytes',
        );
        expect(file.existsSync(), isTrue, reason: s.filePath);
        expect(file.lengthSync(), greaterThan(10 * 1024), reason: s.filePath);
      }

      final bookmarks = (await tester.runAsync(
        () => media.bookmarksFor(activity.id),
      ))!;
      expect(bookmarks, isNotEmpty, reason: 'bookmark and note are saved');
      debugPrint('J2 media folder: ${mediaDir.path}');
    },
    skip: !Platform.isWindows && !Platform.isAndroid,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

String _snackText(WidgetTester tester) {
  final snack = find.byType(SnackBar);
  if (snack.evaluate().isEmpty) return '(no message)';
  return tester
      .widgetList<Text>(find.descendant(of: snack, matching: find.byType(Text)))
      .map((t) => t.data ?? '')
      .join(' ');
}

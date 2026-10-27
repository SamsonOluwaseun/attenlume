import 'package:attenlume/app/theme/app_theme.dart';
import 'package:attenlume/data/local_database/database_provider.dart';
import 'package:attenlume/data/repositories/repository_providers.dart';
import 'package:attenlume/domain/models/activity.dart';
import 'package:attenlume/features/activities/activity_editor_screen.dart';
import 'package:attenlume/features/activities/custom_type_dialog.dart';
import 'package:attenlume/features/conferences/start_activity_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fixtures/fixtures.dart';

void main() {
  late TestData t;

  setUp(() {
    t = TestData();
  });

  tearDown(() async {
    await t.close();
  });

  Widget buildSubject({required Widget child, required WidgetTester tester}) {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    return ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(t.db),
        conferenceRepositoryProvider.overrideWithValue(t.conferences),
        activityRepositoryProvider.overrideWithValue(t.activities),
        mediaAssetRepositoryProvider.overrideWithValue(t.media),
      ],
      child: MaterialApp(theme: AppTheme.light(), home: child),
    );
  }

  group('FR-ACT-06 custom activity types', () {
    testWidgets(
      'FR-ACT-06 CustomTypeDialog creates a new custom activity type',
      (tester) async {
        ActivityType? created;

        await tester.pumpWidget(
          buildSubject(
            tester: tester,
            child: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  created = await CustomTypeDialog.show(context);
                },
                child: const Text('Open Dialog'),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open Dialog'));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('custom-type-dialog')), findsOneWidget);

        // Enter label
        await tester.enterText(
          find.byKey(const Key('custom-type-label-input')),
          'Poster session',
        );

        // Pick icon
        await tester.tap(find.byKey(const Key('custom-type-icon-sparkles')));
        await tester.pumpAndSettle();

        // Submit
        await tester.tap(find.byKey(const Key('custom-type-create-button')));
        await tester.pumpAndSettle();

        expect(created, isNotNull);
        expect(created!.label, 'Poster session');
        expect(created!.key, 'custom_poster_session');
        expect(created!.icon, 'sparkles');
        expect(created!.isBuiltin, isFalse);

        // Verify it was persisted to database
        final types = await t.activities.types();
        expect(types.any((x) => x.key == 'custom_poster_session'), isTrue);
      },
    );

    testWidgets('FR-ACT-06 CustomTypeDialog rejects blank label', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildSubject(
          tester: tester,
          child: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => CustomTypeDialog.show(context),
              child: const Text('Open Dialog'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      // Try to submit blank
      await tester.tap(find.byKey(const Key('custom-type-create-button')));
      await tester.pumpAndSettle();

      expect(find.text('Please enter a type name'), findsOneWidget);
    });

    testWidgets(
      'FR-ACT-06 StartActivitySheet opens CustomTypeDialog and displays created type',
      (tester) async {
        final conf = await t.conference();

        await tester.pumpWidget(
          buildSubject(
            tester: tester,
            child: StartActivitySheet(conferenceId: conf.id),
          ),
        );
        await tester.pumpAndSettle();

        // Tap Add custom type
        await tester.tap(find.byKey(const Key('add-custom-type-chip')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('custom-type-dialog')), findsOneWidget);

        await tester.enterText(
          find.byKey(const Key('custom-type-label-input')),
          'Lab tour',
        );
        await tester.tap(find.byKey(const Key('custom-type-create-button')));
        await tester.pumpAndSettle();

        // Activity should be created with the custom type
        final activities = await t.activities.listForConference(conf.id);
        expect(activities, hasLength(1));
        expect(activities.first.title, contains('Lab tour'));
      },
    );

    testWidgets(
      'FR-ACT-06 ActivityEditorScreen allows creating and deleting unused custom type',
      (tester) async {
        final conf = await t.conference();
        final custom = await t.activities.createCustomType('Unused Type');

        await tester.pumpWidget(
          buildSubject(
            tester: tester,
            child: ActivityEditorScreen(conferenceId: conf.id),
          ),
        );
        await tester.pumpAndSettle();

        // Custom type chip is present with delete icon
        final chipKey = Key('activity-type-choice-${custom.key}');
        expect(find.byKey(chipKey), findsOneWidget);

        // Find delete button on custom type chip
        final deleteButtonFinder = find.descendant(
          of: find.byKey(chipKey),
          matching: find.byIcon(Icons.close),
        );
        expect(deleteButtonFinder, findsOneWidget);

        await tester.tap(deleteButtonFinder);
        await tester.pumpAndSettle();

        // Confirmation dialog
        expect(find.text('Delete type Unused Type?'), findsOneWidget);
        await tester.tap(find.text('Delete'));
        await tester.pumpAndSettle();

        // Verify type was deleted
        expect(await t.activities.typeByKey(custom.key), isNull);
        expect(find.text('Custom type "Unused Type" deleted'), findsOneWidget);
      },
    );
  });
}
